import Foundation

struct LightCLIError: Error, CustomStringConvertible {
    let description: String
}

func printUsage() {
    let usage = """
    Usage: light-cli --name <lamp-name> [--color <hex>] [--brightness <0-100>]

    Options:
      --name, -n        Name of the lamp (required)
      --color, -c       Hex color value (e.g. "#FF0000" or "FF0000")
      --brightness, -b  Brightness level 0-100

    Environment:
      LIGHT_CLI_HOST    Server host (default: localhost)
      LIGHT_CLI_PORT    Server port (default: 8080)
      AUTH_TOKEN        Bearer token for authentication
    """
    print(usage)
}

func parseArgs() throws -> (name: String, color: String?, brightness: Int?) {
    let args = CommandLine.arguments
    var name: String?
    var color: String?
    var brightness: Int?

    var i = 1
    while i < args.count {
        switch args[i] {
        case "--name", "-n":
            i += 1
            guard i < args.count else { throw LightCLIError(description: "Missing value for --name") }
            name = args[i]
        case "--color", "-c":
            i += 1
            guard i < args.count else { throw LightCLIError(description: "Missing value for --color") }
            color = args[i]
        case "--brightness", "-b":
            i += 1
            guard i < args.count else { throw LightCLIError(description: "Missing value for --brightness") }
            guard let b = Int(args[i]), (0...100).contains(b) else {
                throw LightCLIError(description: "Brightness must be an integer between 0 and 100")
            }
            brightness = b
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            throw LightCLIError(description: "Unknown argument: \(args[i])")
        }
        i += 1
    }

    guard let name else {
        throw LightCLIError(description: "Missing required argument: --name")
    }
    guard color != nil || brightness != nil else {
        throw LightCLIError(description: "At least one of --color or --brightness must be provided")
    }

    return (name, color, brightness)
}

func run() async throws {
    let parsed = try parseArgs()

    let host = ProcessInfo.processInfo.environment["LIGHT_CLI_HOST"] ?? "localhost"
    let port = ProcessInfo.processInfo.environment["LIGHT_CLI_PORT"] ?? "8080"
    let authToken = ProcessInfo.processInfo.environment["AUTH_TOKEN"]

    let url = URL(string: "http://\(host):\(port)/lights/set")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let authToken {
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
    }

    var body: [String: Any] = ["name": parsed.name]
    if let color = parsed.color {
        body["hexColor"] = color
    }
    if let brightness = parsed.brightness {
        body["brightness"] = brightness
    }

    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (_, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
        throw LightCLIError(description: "Invalid response from server")
    }

    switch httpResponse.statusCode {
    case 200:
        print("OK - Light '\(parsed.name)' updated")
    case 404:
        print("Error: No light found with name '\(parsed.name)'")
        exit(1)
    case 400:
        print("Error: Bad request - check your parameters")
        exit(1)
    case 401:
        print("Error: Authentication failed - check AUTH_TOKEN")
        exit(1)
    default:
        print("Error: Server returned status \(httpResponse.statusCode)")
        exit(1)
    }
}

do {
    try await run()
} catch let error as LightCLIError {
    print("Error: \(error.description)")
    printUsage()
    exit(1)
} catch {
    print("Error: \(error)")
    exit(1)
}
