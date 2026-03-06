import Foundation
import Security

// MARK: - Keychain

private let keychainService = "de.juliankahnert.HomeAutomation"

func keychainRead(_ account: String) -> String? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: keychainService,
        kSecAttrAccount as String: account,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
          let data = result as? Data else {
        return nil
    }
    return String(data: data, encoding: .utf8)
}

func keychainWrite(_ account: String, value: String) {
    let deleteQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: keychainService,
        kSecAttrAccount as String: account,
    ]
    SecItemDelete(deleteQuery as CFDictionary)

    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: keychainService,
        kSecAttrAccount as String: account,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        kSecValueData as String: value.data(using: .utf8)!,
    ]
    SecItemAdd(query as CFDictionary, nil)
}

// MARK: - Error & Usage

struct HomeCLIError: Error, CustomStringConvertible {
    let description: String
}

func printUsage() {
    let usage = """
    Usage: home --place <place-id> --name <lamp-name> [--color <hex>] [--brightness <0-100>]
           home setup --url <server-url> --token <auth-token>

    Commands:
      setup               Store server URL and auth token in Keychain

    Options:
      --place, -p         Place identifier / room name (required)
      --name, -n          Name of the lamp (required)
      --color, -c         Hex color value (e.g. "#FF0000" or "FF0000")
      --brightness, -b    Brightness level 0-100
      --url               Server URL (overrides Keychain, e.g. "http://server:8080")
      --token             Auth token (overrides Keychain)

    Credentials are read from Keychain (shared with FlowKit Controller app).
    Use 'home setup' to store them, or pass --url/--token directly.
    """
    print(usage)
}

// MARK: - Arg Parsing

enum Command {
    case setLight(placeId: String, name: String, color: String?, brightness: Int?, url: String?, token: String?)
    case setup(url: String, token: String)
}

func parseArgs() throws -> Command {
    let args = CommandLine.arguments

    guard args.count > 1 else {
        printUsage()
        exit(0)
    }

    if args[1] == "setup" {
        var url: String?
        var token: String?
        var i = 2
        while i < args.count {
            switch args[i] {
            case "--url":
                i += 1
                guard i < args.count else { throw HomeCLIError(description: "Missing value for --url") }
                url = args[i]
            case "--token":
                i += 1
                guard i < args.count else { throw HomeCLIError(description: "Missing value for --token") }
                token = args[i]
            default:
                throw HomeCLIError(description: "Unknown argument for setup: \(args[i])")
            }
            i += 1
        }
        guard let url else { throw HomeCLIError(description: "setup requires --url") }
        guard let token else { throw HomeCLIError(description: "setup requires --token") }
        return .setup(url: url, token: token)
    }

    var placeId: String?
    var name: String?
    var color: String?
    var brightness: Int?
    var url: String?
    var token: String?

    var i = 1
    while i < args.count {
        switch args[i] {
        case "--place", "-p":
            i += 1
            guard i < args.count else { throw HomeCLIError(description: "Missing value for --place") }
            placeId = args[i]
        case "--name", "-n":
            i += 1
            guard i < args.count else { throw HomeCLIError(description: "Missing value for --name") }
            name = args[i]
        case "--color", "-c":
            i += 1
            guard i < args.count else { throw HomeCLIError(description: "Missing value for --color") }
            color = args[i]
        case "--brightness", "-b":
            i += 1
            guard i < args.count else { throw HomeCLIError(description: "Missing value for --brightness") }
            guard let b = Int(args[i]), (0...100).contains(b) else {
                throw HomeCLIError(description: "Brightness must be an integer between 0 and 100")
            }
            brightness = b
        case "--url":
            i += 1
            guard i < args.count else { throw HomeCLIError(description: "Missing value for --url") }
            url = args[i]
        case "--token":
            i += 1
            guard i < args.count else { throw HomeCLIError(description: "Missing value for --token") }
            token = args[i]
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            throw HomeCLIError(description: "Unknown argument: \(args[i])")
        }
        i += 1
    }

    guard let placeId else { throw HomeCLIError(description: "Missing required argument: --place") }
    guard let name else { throw HomeCLIError(description: "Missing required argument: --name") }
    guard color != nil || brightness != nil else {
        throw HomeCLIError(description: "At least one of --color or --brightness must be provided")
    }

    return .setLight(placeId: placeId, name: name, color: color, brightness: brightness, url: url, token: token)
}

// MARK: - Run

func run() async throws {
    let command = try parseArgs()

    switch command {
    case .setup(let url, let token):
        keychainWrite("serverURL", value: url)
        keychainWrite("authToken", value: token)
        print("OK - Credentials stored in Keychain (service: \(keychainService))")

    case .setLight(let placeId, let name, let color, let brightness, let urlOverride, let tokenOverride):
        // Resolve server URL: CLI arg > Keychain > default
        let serverURL: String
        if let urlOverride {
            serverURL = urlOverride
        } else if let stored = keychainRead("serverURL") {
            serverURL = stored
        } else {
            throw HomeCLIError(description: "No server URL configured. Run 'home setup' or pass --url")
        }

        // Resolve auth token: CLI arg > Keychain
        let authToken = tokenOverride ?? keychainRead("authToken")

        let base = serverURL.hasSuffix("/") ? String(serverURL.dropLast()) : serverURL
        let url = URL(string: "\(base)/lights/set")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let authToken, !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = ["placeId": placeId, "name": name]
        if let color {
            body["hexColor"] = color
        }
        if let brightness {
            body["brightness"] = brightness
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HomeCLIError(description: "Invalid response from server")
        }

        switch httpResponse.statusCode {
        case 200:
            print("OK - Light '\(placeId)/\(name)' updated")
        case 400:
            print("Error: Bad request - check your parameters")
            exit(1)
        case 401:
            print("Error: Authentication failed - run 'home setup' or pass --token")
            exit(1)
        default:
            print("Error: Server returned status \(httpResponse.statusCode)")
            exit(1)
        }
    }
}

do {
    try await run()
} catch let error as HomeCLIError {
    print("Error: \(error.description)")
    printUsage()
    exit(1)
} catch {
    print("Error: \(error)")
    exit(1)
}
