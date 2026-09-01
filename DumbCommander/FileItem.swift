import Foundation

enum FileSortKey: String, CaseIterable, Sendable {
    case name
    case type
    case size
}

struct PanelSort: Equatable, Sendable {
    var key: FileSortKey = .name
    var ascending = true
}

struct FileItem: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let pathExtension: String
    let size: Int64
    let modificationDate: Date?
    let permissions: String
    let isDirectory: Bool
    let isPackage: Bool
    let isSymbolicLink: Bool
    let isAlias: Bool
    let isHidden: Bool

    var id: URL { url }

    var isNavigableDirectory: Bool {
        isDirectory && !isSymbolicLink
    }

    var typeDescription: String {
        if isSymbolicLink { return "Link" }
        if isAlias { return "Alias" }
        if isPackage { return "Paket" }
        if isDirectory { return "Ordner" }
        return pathExtension.isEmpty ? "Datei" : pathExtension
    }

    var formattedSize: String {
        guard !isNavigableDirectory else { return "—" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

enum PanelCursor: Hashable, Sendable {
    case currentDirectory
    case parentDirectory
    case item(URL)

    var itemURL: URL? {
        guard case let .item(url) = self else { return nil }
        return url
    }
}

extension Array where Element == FileItem {
    func sorted(using descriptor: PanelSort) -> [FileItem] {
        sorted { lhs, rhs in
            if lhs.isNavigableDirectory != rhs.isNavigableDirectory {
                return lhs.isNavigableDirectory
            }

            let comparison: ComparisonResult
            switch descriptor.key {
            case .name:
                comparison = lhs.name.localizedStandardCompare(rhs.name)
            case .type:
                let typeComparison = lhs.typeDescription.localizedStandardCompare(rhs.typeDescription)
                comparison = typeComparison == .orderedSame
                    ? lhs.name.localizedStandardCompare(rhs.name)
                    : typeComparison
            case .size:
                if lhs.size == rhs.size {
                    comparison = lhs.name.localizedStandardCompare(rhs.name)
                } else {
                    comparison = lhs.size < rhs.size ? .orderedAscending : .orderedDescending
                }
            }

            if comparison == .orderedSame {
                return lhs.url.path < rhs.url.path
            }
            return descriptor.ascending
                ? comparison == .orderedAscending
                : comparison == .orderedDescending
        }
    }
}
