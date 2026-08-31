import Foundation

final class TemporaryDirectory {
    let url: URL

    init(fileManager: FileManager = .default) throws {
        url = fileManager.temporaryDirectory
            .appendingPathComponent("DumbCommanderTests")
            .appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func createFile(named name: String, contents: String = "test") throws -> URL {
        let fileURL = url.appendingPathComponent(name)
        try Data(contents.utf8).write(to: fileURL)
        return fileURL
    }

    @discardableResult
    func createDirectory(named name: String) throws -> URL {
        let directoryURL = url.appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        return directoryURL
    }
}
