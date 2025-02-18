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

    let actorSystem = await ActorSystem(nodeId: .server, port: 8888)
    let eventReceiver = HomeEventReceiver(continuation: app.homeEventsContinuation, actorSystem: actorSystem.webSocketActorSystem)
    await actorSystem.checkIn(actorId: .homeEventReceiver, eventReceiver)
    app.homeEventReceiver = eventReceiver

    // MARK: - home automation setup

    app.homeAutomationConfigService = HomeAutomationConfigService.loadOrDefault()
    let homeManager = await HomeManager(
        getAdapter: {
            await actorSystem.resolve(.homeKitCommandReceiver)
        },
        storageRepo: app.entityStorageDbRepository,
        location: app.homeAutomationConfigService.location)
    app.homeManager = homeManager
    let automationService = try AutomationService(using: homeManager,
                                                  getAutomations: {
        await app.homeAutomationConfigService.automations
            .map(\.automation)
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

    app.logger.notice("ActorSystem server running on \(actorSystem.webSocketActorSystem.cluster.node.host):\(actorSystem.webSocketActorSystem.cluster.node.port)")

    // register routes
    try routes(app)
}
