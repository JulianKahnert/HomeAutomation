import FluentMySQLDriver
import HAApplicationLayer
import HAImplementations
import HAModels
import Logging
import Vapor

// public distributed actor HomeKitCommandReceiver: EntityAdapterable {  // this crashes the 6.0.3 swift compiler on linux so we moved it to an extension
extension HomeKitCommandReceiver: @retroactive EntityAdapterable {}

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

    do {
        app.homeAutomationConfigService = try await HomeAutomationConfigService.load()
    } catch {
        fatalError("Could not find config file from \(HomeAutomationConfigService.url)")
//        app.homeAutomationConfigService = HomeAutomationConfigService(location: Location(latitude: 53.14194, longitude: 8.21292), automations: [])
//        try await app.homeAutomationConfigService.save()
    }

    let getAutomations: () async -> [any Automatable] = {
        return await app.homeAutomationConfigService.automations
            .map(\.automation)
    }

    let homeManager = await HomeManager(
        getAdapter: {
            return await actorSystem.resolve(.homeKitCommandReceiver)
        },
        storageRepo: app.entityStorageDbRepository,
        location: app.homeAutomationConfigService.location)
    app.homeManager = homeManager

    let automationManager = try AutomationService(
        using: homeManager, getAutomations: getAutomations)

    Task.detached {
        for await event in app.homeEventsStream {
            app.logger.debug("trigger automation with \(event.description)")

            // add item to history
            switch event {
            case .change(let item):
                await homeManager.addEntityHistory(item)
            case .time, .sunset, .sunrise:
                break
            }

            // perform automation
            await automationManager.trigger(with: event)
        }
    }

    // MARK: - register routes

    app.logger.notice("ActorSystem server running on \(actorSystem.webSocketActorSystem.cluster.node.host):\(actorSystem.webSocketActorSystem.cluster.node.port)")

    // register routes
    try routes(app)
}
