import Foundation

enum CommanderPreferences {
    static let isTesting: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return environment["DUMBCOMMANDER_UI_TESTING"] == "1"
            || environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }()

    private static let testSuiteName: String? = {
        guard isTesting else { return nil }
        let suite = ProcessInfo.processInfo.environment["DUMBCOMMANDER_TEST_DEFAULTS"]
            ?? "DumbCommander-Tests-\(UUID().uuidString)"
        // The prefix prevents an accidental test configuration from using the real app domain.
        precondition(suite.hasPrefix("DumbCommander-Tests-"))
        return suite
    }()

    static let defaults: UserDefaults = {
        guard let suite = testSuiteName else { return .standard }
        return UserDefaults(suiteName: suite)!
    }()

    static let initialDirectory: URL = {
        guard isTesting else { return FileManager.default.homeDirectoryForCurrentUser }
        if let path = ProcessInfo.processInfo.environment["DUMBCOMMANDER_UI_TEST_DIRECTORY"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        // App-hosted unit tests have no UI fixture. They get an empty, private root.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DumbCommander-TestHost-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        } catch {
            preconditionFailure("Testverzeichnis konnte nicht angelegt werden: \(error)")
        }
        return url
    }()

    static func cleanUpTestHost() throws {
        guard isTesting, let suite = testSuiteName else { return }
        defaults.removePersistentDomain(forName: suite)
        if ProcessInfo.processInfo.environment["DUMBCOMMANDER_UI_TEST_DIRECTORY"] == nil {
            try FileManager.default.removeItem(at: initialDirectory)
        }
    }
}

struct PanelSession: Codable, Equatable, Sendable {
    let directoryPath: String
    var sort = PanelSort()
    var filterText = ""
}

struct CommanderSession: Codable, Equatable, Sendable {
    let version: Int
    let leftTabs: [PanelSession]
    let rightTabs: [PanelSession]
    let selectedLeftTabIndex: Int
    let selectedRightTabIndex: Int
    let activePanel: String

    var leftDirectoryPath: String { selectedPath(in: leftTabs, index: selectedLeftTabIndex) }
    var rightDirectoryPath: String { selectedPath(in: rightTabs, index: selectedRightTabIndex) }

    init(leftDirectoryPath: String, rightDirectoryPath: String, activePanel: String) {
        self.init(
            leftTabs: [PanelSession(directoryPath: leftDirectoryPath)],
            rightTabs: [PanelSession(directoryPath: rightDirectoryPath)],
            selectedLeftTabIndex: 0,
            selectedRightTabIndex: 0,
            activePanel: activePanel
        )
    }

    init(
        leftTabs: [PanelSession], rightTabs: [PanelSession],
        selectedLeftTabIndex: Int, selectedRightTabIndex: Int, activePanel: String
    ) {
        version = 2
        self.leftTabs = leftTabs
        self.rightTabs = rightTabs
        self.selectedLeftTabIndex = selectedLeftTabIndex
        self.selectedRightTabIndex = selectedRightTabIndex
        self.activePanel = activePanel
    }

    private enum CodingKeys: String, CodingKey {
        case version, leftTabs, rightTabs, selectedLeftTabIndex, selectedRightTabIndex, activePanel
        case leftDirectoryPath, rightDirectoryPath
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        guard (1...2).contains(version) else {
            throw DecodingError.dataCorruptedError(
                forKey: .version, in: values, debugDescription: "Unbekanntes Sitzungsformat"
            )
        }
        let active = try values.decode(String.self, forKey: .activePanel)
        if version == 1 {
            self.init(
                leftDirectoryPath: try values.decode(String.self, forKey: .leftDirectoryPath),
                rightDirectoryPath: try values.decode(String.self, forKey: .rightDirectoryPath),
                activePanel: active
            )
        } else {
            self.init(
                leftTabs: try values.decode([PanelSession].self, forKey: .leftTabs),
                rightTabs: try values.decode([PanelSession].self, forKey: .rightTabs),
                selectedLeftTabIndex: try values.decode(Int.self, forKey: .selectedLeftTabIndex),
                selectedRightTabIndex: try values.decode(Int.self, forKey: .selectedRightTabIndex),
                activePanel: active
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(version, forKey: .version)
        try values.encode(leftTabs, forKey: .leftTabs)
        try values.encode(rightTabs, forKey: .rightTabs)
        try values.encode(selectedLeftTabIndex, forKey: .selectedLeftTabIndex)
        try values.encode(selectedRightTabIndex, forKey: .selectedRightTabIndex)
        try values.encode(activePanel, forKey: .activePanel)
    }

    private func selectedPath(in tabs: [PanelSession], index: Int) -> String {
        guard !tabs.isEmpty else { return "/" }
        return tabs[min(max(0, index), tabs.count - 1)].directoryPath
    }
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
