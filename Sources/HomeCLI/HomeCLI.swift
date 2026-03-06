import ArgumentParser
import Foundation
#if canImport(Security)
import Shared
#endif

@main
struct HomeCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "home",
        abstract: "Control HomeAutomation lights from the command line.",
        subcommands: [Setup.self, SetLight.self],
        defaultSubcommand: SetLight.self
    )
}

// MARK: - setup

struct Setup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Store server URL and auth token in Keychain."
    )

    @Option(help: "Server URL (e.g. \"http://server:8080\")")
    var url: String

    @Option(help: "Authentication token")
    var token: String

    func run() async throws {
        #if canImport(Security)
        KeychainHelper.writeString("serverURL", value: url)
        KeychainHelper.writeString("authToken", value: token)
        print("OK - Credentials stored in Keychain")
        #else
        print("Error: Keychain is not available on this platform")
        throw ExitCode.failure
        #endif
    }
}

// MARK: - set-light

struct SetLight: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set-light",
        abstract: "Set color and/or brightness of a light."
    )

    @Option(name: [.short, .long], help: "Place identifier / room name")
    var place: String

    @Option(name: [.short, .long], help: "Name of the lamp")
    var name: String

    @Option(name: [.short, .long], help: "Hex color value (e.g. \"#FF0000\" or \"FF0000\")")
    var color: String?

    @Option(name: [.short, .long], help: "Brightness level 0-100")
    var brightness: Int?

    @Option(help: "Server URL (overrides Keychain)")
    var url: String?

    @Option(help: "Auth token (overrides Keychain)")
    var token: String?

    func validate() throws {
        guard color != nil || brightness != nil else {
            throw ValidationError("At least one of --color or --brightness must be provided")
        }
        if let brightness, !(0...100).contains(brightness) {
            throw ValidationError("Brightness must be between 0 and 100")
        }
    }

    func run() async throws {
        let serverURL = try resolveServerURL()
        let authToken = resolveAuthToken()

        let base = serverURL.hasSuffix("/") ? String(serverURL.dropLast()) : serverURL
        guard let requestURL = URL(string: "\(base)/lights/set") else {
            throw ValidationError("Invalid server URL: \(serverURL)")
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let authToken, !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = ["placeId": place, "name": name]
        if let color {
            body["hexColor"] = color
        }
        if let brightness {
            body["brightness"] = brightness
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CleanExit.message("Error: Invalid response from server")
        }

        switch httpResponse.statusCode {
        case 200:
            print("OK - Light '\(place)/\(name)' updated")
        case 400:
            print("Error: Bad request - check your parameters")
            throw ExitCode.failure
        case 401:
            print("Error: Authentication failed - run 'home setup' or pass --token")
            throw ExitCode.failure
        default:
            print("Error: Server returned status \(httpResponse.statusCode)")
            throw ExitCode.failure
        }
    }

    private func resolveServerURL() throws -> String {
        if let url { return url }
        #if canImport(Security)
        if let stored = KeychainHelper.readString("serverURL") { return stored }
        #endif
        throw ValidationError("No server URL configured. Run 'home setup' or pass --url")
    }

    private func resolveAuthToken() -> String? {
        if let token { return token }
        #if canImport(Security)
        return KeychainHelper.readString("authToken")
        #else
        return nil
        #endif
    }
}
