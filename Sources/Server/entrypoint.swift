import HAModels
import Logging
import Shared
import Vapor

@main
enum Entrypoint {
    static func main() async throws {
        var env = try Environment.detect()

        // Read the level from the `LOG_LEVEL` env (and `--log` flag) so it can be set once in
        // docker-compose, `HA_DEBUG_LOGGING=1` lowers it to debug, and wrap each handler with
        // CriticalNotifyingLogHandler so CRITICAL log events trigger push notifications.
        let isDebugLoggingEnabled = DebugLogging.isEnabled()
        try LoggingSystem.bootstrap(from: &env) { level in
            { label in
                var underlying = StreamLogHandler.standardOutput(label: label)
                underlying.logLevel = DebugLogging.level(level, enabled: isDebugLoggingEnabled)
                return CriticalNotifyingLogHandler(label: label, underlying: underlying)
            }
        }

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

        try await app.execute()
        try await app.asyncShutdown()
    }
}
