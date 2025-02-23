import HAModels
import Logging
import Vapor

@main
enum Entrypoint {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)
//        try LoggingSystem.bootstrap(from: &env) { level in
//            return { label in
//                var logger = StreamLogHandler.standardOutput(label: label)
//                logger.logLevel = level
//                return TimestampLogHandler(underlying: logger)
//            }
//        }

        let app = try await Application.make(env)

        // This attempts to install NIO as the Swift Concurrency global executor.
        // You can enable it if you'd like to reduce the amount of context switching between NIO and Swift Concurrency.
        // Note: this has caused issues with some libraries that use `.wait()` and cleanly shutting down.
        // If enabled, you should be careful about calling async functions before this point as it can cause assertion failures.
        // #warning("This caused problems with WebSocketActors")
        // let executorTakeoverSuccess = NIOSingletons.unsafeTryInstallSingletonPosixEventLoopGroupAsConcurrencyGlobalExecutor()
        // app.logger.debug("Tried to install SwiftNIO's EventLoopGroup as Swift's global concurrency executor", metadata: ["success": .stringConvertible(executorTakeoverSuccess)])

        do {
            try await configure(app)
        } catch {
            app.logger.report(error: error)
            try? await app.asyncShutdown()
            throw error
        }

        #if DEBUG
//        Task.detached {
////            try! await Task.sleep(for: .seconds(2))
////            app.homeEventsContinuation.yield(.sunrise)
//            
////            let light = EntityId(placeId: "Julians Arbeitszimmer", name: "Schrank", characteristicsName: nil, characteristic: .switcher)
//            let light = EntityId(placeId: "Kaminzimmer", name: "LED Streifen", characteristicsName: nil, characteristic: .switcher)
//            print("DEBUGGING \(Date()) light action start")
////            await app.homeManager.perform(.turnOn(light))
//            print("DEBUGGING \(Date()) light action end")
//            
////            let repo = app.entityStorageDbRepository
////            let item = try! await repo.getPrevious(EntityId(placeId: "Kaminzimmer", name: "Eve Motion", characteristicsName: "Eve Motion", characteristic: .motionSensor))
////            
////            print(item)
////            print(item)
//        }
        #endif

        try await app.execute()
        try await app.asyncShutdown()
    }
}
