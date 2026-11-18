//
//  FileLogHandlerTests.swift
//  SharedTests
//

import Foundation
@testable import Shared
import Testing

struct FileLogHandlerTests {
    @Test func writeToUnavailableLogDirectoryDoesNotTerminateTheProcess() async {
        await #expect(processExitsWith: .success) {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            // A regular file where the log directory belongs makes every open fail, as a protected
            // container does before the first unlock.
            FileManager.default.createFile(atPath: directory.path, contents: nil)
            let stream = FileLogHandler.FileHandlerOutputStream(basePath: directory)
            await stream.write("lost\n")
        }
    }

    @Test func writeOpensTheLogFileOnceTheDirectoryBecomesAvailable() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try #require(FileManager.default.createFile(atPath: directory.path, contents: nil))
        let stream = FileLogHandler.FileHandlerOutputStream(basePath: directory)

        await stream.write("lost\n")
        try FileManager.default.removeItem(at: directory)
        await stream.write("kept\n")

        let logFiles = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let contents = try logFiles.map { try String(contentsOf: $0, encoding: .utf8) }.joined()
        #expect(contents == "kept\n")
        try FileManager.default.removeItem(at: directory)
    }
}
