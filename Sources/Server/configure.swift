import CoreFoundation
import FluentMySQLDriver
import HAApplicationLayer
import HAImplementations
import HAModels
import Logging
import Vapor

// public distributed actor HomeKitCommandReceiver: EntityAdapterable {  // this crashes the 6.0.3 swift compiler on linux so we moved it to an extension
extension HomeKitCommandReceiver: EntityAdapterable {}

// configures your application
public func configure(_ app: Application) async throws {

    // change time zone if it is set as the TZ environment variable
    // ATTENTION: DO NOT USE TimeZone.current before this! I will not change after first use
    if let timeZoneString = Environment.get("TZ") {
        setenv("TZ", timeZoneString, 1)
        CFTimeZoneResetSystem()
    }
    app.logger.info("Using timezone: \(TimeZone.current.description)")

    // MARK: - database setup

    var tlsConfiguration = TLSConfiguration.makeClientConfiguration()
    tlsConfiguration.certificateVerification = .none
    app.databases.use(DatabaseConfigurationFactory.mysql(
        hostname: Environment.get("DATABASE_HOST") ?? "localhost",
        port: Environment.get("DATABASE_PORT").flatMap(Int.init(_:)) ?? MySQLConfiguration.ianaPortNumber,
        username: Environment.get("DATABASE_USERNAME") ?? "vapor_username",
        password: Environment.get("DATABASE_PASSWORD") ?? "vapor_password",
        database: Environment.get("DATABASE_NAME") ?? "vapor_database",
        tlsConfiguration: tlsConfiguration
    ), as: .mysql)

    app.migrations.add(CreateEntityStorageDbItem())

    // MARK: - actor system setup

    let actorSystem = await CustomActorSystem(nodeId: .server, port: 8888)
    let eventReceiver = actorSystem.makeLocalActor(actorId: .homeEventReceiver) { system in
        HomeEventReceiver(continuation: app.homeEventsContinuation, actorSystem: system)
    }
    await actorSystem.checkIn(actorId: .homeEventReceiver, eventReceiver)
    app.homeEventReceiver = eventReceiver

    // MARK: - home automation setup

    app.homeAutomationConfigService = HomeAutomationConfigService.loadOrDefault()
    let homeManager = await HomeManager(
        getAdapter: {
            await actorSystem.lookup(.homeKitCommandReceiver)
        },
        storageRepo: app.entityStorageDbRepository,
        location: app.homeAutomationConfigService.location)
    app.homeManager = homeManager
    let automationService = try AutomationService(using: homeManager,
                                                  getAutomations: {
        await app.homeAutomationConfigService.automations
    })

    // MARK: - register jobs

    let location = await app.homeAutomationConfigService.location
    let jobs: [any Job] = [
        ClockJob(location: location,
                 homeEventsContinuation: app.homeEventsContinuation),
        HomeEventProcessingJob(homeEventsStream: app.homeEventsStream,
                               automationService: automationService,
                               homeManager: app.homeManager)
    ]

    Task.detached {
        await withTaskGroup(of: Void.self) { group in
            for job in jobs {
                group.addTask {
                    await job.run()
                }
            }
            await group.waitForAll()
        }
    }

    // MARK: - register routes

    // register routes
    try routes(app)

    app.logger.notice("CustomActorSystem server running on \(actorSystem.endpointDescription)")
}
