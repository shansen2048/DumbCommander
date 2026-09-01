import Foundation

struct CommanderSession: Codable, Equatable, Sendable {
    let leftDirectoryPath: String
    let rightDirectoryPath: String
    let activePanel: String
}

@MainActor
protocol CommanderSessionStoring: AnyObject {
    func load() -> CommanderSession?
    func save(_ session: CommanderSession)
}

@MainActor
final class UserDefaultsCommanderSessionStore: CommanderSessionStoring {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "commanderSession") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> CommanderSession? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CommanderSession.self, from: data)
    }

    func save(_ session: CommanderSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: key)
    }
}
