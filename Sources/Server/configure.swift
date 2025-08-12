import APNS
import APNSCore
import APNSURLSession
import CoreFoundation
import FluentMySQLDriver
import HAApplicationLayer
import HAImplementations
import HAModels
import Logging
import Vapor
import VaporAPNS

#warning("TODO: remove TibberSwift from HomeAutomationKit or also use NotificationSender there")

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
    app.logger.info("Using environment: \(app.environment.name) (isRelease: \(app.environment.isRelease))")

    // MARK: - env parsing

    let notificationTopic = Environment.get("PUSH_NOTIFICATION_TOPIC") ?? "de.juliankahnert.HomeAutomation"
    let notificationPrivateKey = String.fromBase64(Environment.get("PUSH_NOTIFICATION_PRIVATE_KEY_BASE64")!)!
    let notificationKeyIdentifier = Environment.get("PUSH_NOTIFICATION_KEY_IDENTIFIER")!
    let notificationTeamIdentifier = Environment.get("PUSH_NOTIFICATION_TEAM_IDENTIFIER")!

    // MARK: - database setup

    var tlsConfiguration = TLSConfiguration.makeClientConfiguration()
    tlsConfiguration.certificateVerification = .none
    app.databases.use(
        DatabaseConfigurationFactory.mysql(
            hostname: Environment.get("DATABASE_HOST") ?? "localhost",
            port: Environment.get("DATABASE_PORT").flatMap(Int.init(_:))
                ?? MySQLConfiguration.ianaPortNumber,
            username: Environment.get("DATABASE_USERNAME") ?? "vapor_username",
            password: Environment.get("DATABASE_PASSWORD") ?? "vapor_password",
            database: Environment.get("DATABASE_NAME") ?? "vapor_database",
            tlsConfiguration: tlsConfiguration
        ), as: .mysql)

    app.migrations.add(CreateEntityStorageDbItem())
    app.migrations.add(DeviceTokenItem())

    // MARK: - configure APNS

    // Configure APNS using JWT authentication.
    let apnsEnvironment: APNSEnvironment = app.environment == .production ? .production : .development
    app.logger.info("Using apns url \(apnsEnvironment.absoluteURL)")
    let apnsConfig = APNSClientConfiguration(
        authenticationMethod: .jwt(
            privateKey: try .loadFrom(string: notificationPrivateKey),
            keyIdentifier: notificationKeyIdentifier,
            teamIdentifier: notificationTeamIdentifier
        ),
        environment: apnsEnvironment
    )

    await app.apns.containers.use(
        apnsConfig,
        eventLoopGroupProvider: .shared(app.eventLoopGroup),
        responseDecoder: JSONDecoder(),
        requestEncoder: JSONEncoder(),
        as: .default
    )

    // MARK: - actor system setup

    let actorSystem = await CustomActorSystem(nodeId: .server, port: 8888)
    let eventReceiver = actorSystem.makeLocalActor(actorId: .homeEventReceiver) { system in
        HomeEventReceiver(continuation: app.homeEventsContinuation, actorSystem: system)
    }
    await actorSystem.checkIn(actorId: .homeEventReceiver, eventReceiver)
    app.homeEventReceiver = eventReceiver

    // MARK: - home automation setup

    app.homeAutomationConfigService = HomeAutomationConfigService.loadOrDefault()
    let notificationSender = await PushNotifcationService(database: app.db,
                                                          apnsClient: app.apns.client,
                                                          notificationTopic: notificationTopic)

    let homeManager = await HomeManager(getAdapter: {
        await actorSystem.lookup(.homeKitCommandReceiver)
    },
                                        storageRepo: app.entityStorageDbRepository,
                                        notificationSender: notificationSender,
                                        location: app.homeAutomationConfigService.location)
    app.homeManager = homeManager
    let automationService = try AutomationService(using: homeManager,
                                                  getAutomations: {
        await app.homeAutomationConfigService.automations
    })
    app.automationService = automationService

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
