import Foundation
import Darwin

/// Inode and volume identify the entry; size and timestamps also detect edits in place.
struct FileIdentity: Equatable, Sendable {
    let device: Int32
    let inode: UInt64
    let mode: UInt16
    let size: Int64
    let modifiedSeconds: Int
    let modifiedNanos: Int
    let changedSeconds: Int
    let changedNanos: Int
    let birthSeconds: Int
    let birthNanos: Int
    let flags: UInt32

    init(_ value: stat) {
        device = value.st_dev
        inode = value.st_ino
        mode = value.st_mode
        size = value.st_size
        modifiedSeconds = value.st_mtimespec.tv_sec
        modifiedNanos = value.st_mtimespec.tv_nsec
        changedSeconds = value.st_ctimespec.tv_sec
        changedNanos = value.st_ctimespec.tv_nsec
        birthSeconds = value.st_birthtimespec.tv_sec
        birthNanos = value.st_birthtimespec.tv_nsec
        flags = value.st_flags
    }

    var kind: FileSystemEntryKind {
        switch mode & S_IFMT {
        case S_IFREG: return .regularFile
        case S_IFDIR: return .directory
        case S_IFLNK: return .symbolicLink
        default: return .other
        }
    }

    func sameObject(as other: Self) -> Bool {
        device == other.device && inode == other.inode && kind == other.kind
    }

    func sameContents(as other: Self) -> Bool {
        sameObject(as: other) && mode == other.mode && size == other.size
            && modifiedSeconds == other.modifiedSeconds && modifiedNanos == other.modifiedNanos
            && birthSeconds == other.birthSeconds && birthNanos == other.birthNanos && flags == other.flags
    }
}

enum SafeFileError: LocalizedError {
    case changed(URL)
    case unsupported(URL)
    case metadata(URL)
    case recovery(URL, String)
    case invalidName(String)

    var errorDescription: String? {
        switch self {
        case let .changed(url): return "Der Eintrag wurde inzwischen geändert. Bitte neu laden: \(url.path)"
        case let .unsupported(url): return "Dieser spezielle Dateityp wird nicht kopiert: \(url.path)"
        case let .metadata(url): return "Metadaten konnten nicht vollständig erhalten werden: \(url.path)"
        case let .recovery(url, reason):
            return "\(reason) Erhaltene Daten zur Wiederherstellung: \(url.path)"
        case let .invalidName(name): return "Ungültiger Dateiname: \(name)"
        }
    }
}

final class FileDescriptor: @unchecked Sendable {
    let raw: Int32
    init(_ raw: Int32) throws {
        guard raw >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        self.raw = raw
    }
    deinit { Darwin.close(raw) }
    var identity: FileIdentity {
        get throws {
            var value = stat()
            guard fstat(raw, &value) == 0 else { throw SafeDirectory.posixError() }
            return FileIdentity(value)
        }
    }
}

/// All mutations are relative to pinned directories. A renamed/replaced path cannot redirect them.
final class SafeDirectory: @unchecked Sendable {
    let descriptor: FileDescriptor
    let url: URL

    init(url: URL) throws {
        var path = url.standardizedFileURL.path
        // These macOS system aliases are fixed; user-controlled path components are never followed.
        for alias in ["/tmp", "/var", "/etc"] where path == alias || path.hasPrefix(alias + "/") {
            path = "/private" + path
            break
        }
        var handle = try FileDescriptor(Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC))
        for component in path.split(separator: "/") {
            handle = try FileDescriptor(openat(handle.raw, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC))
        }
        descriptor = handle
        self.url = URL(fileURLWithPath: path, isDirectory: true)
    }

    init(parent: SafeDirectory, name: String) throws {
        try Self.validate(name)
        descriptor = try FileDescriptor(openat(parent.descriptor.raw, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC))
        url = parent.url.appendingPathComponent(name, isDirectory: true)
    }

    static func validate(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else {
            throw SafeFileError.invalidName(name)
        }
    }

    static func posixError() -> POSIXError { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }

    func identity(_ name: String) throws -> FileIdentity? {
        try Self.validate(name)
        var value = stat()
        if fstatat(descriptor.raw, name, &value, AT_SYMLINK_NOFOLLOW) == 0 { return FileIdentity(value) }
        if errno == ENOENT { return nil }
        throw Self.posixError()
    }

    func require(_ name: String, expected: FileIdentity? = nil) throws -> FileIdentity {
        guard let value = try identity(name) else { throw FileSystemServiceError.sourceMissing(url.appendingPathComponent(name)) }
        if let expected, value != expected { throw SafeFileError.changed(url.appendingPathComponent(name)) }
        return value
    }

    func openFile(_ name: String, flags: Int32, mode: mode_t = 0o600) throws -> FileDescriptor {
        try Self.validate(name)
        let noFollow = flags & O_SYMLINK == 0 ? O_NOFOLLOW : 0
        return try FileDescriptor(openat(descriptor.raw, name, flags | noFollow | O_CLOEXEC | O_NONBLOCK, mode))
    }

    func names() throws -> [String] {
        let duplicate = openat(descriptor.raw, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard duplicate >= 0 else { throw Self.posixError() }
        guard let stream = fdopendir(duplicate) else {
            Darwin.close(duplicate)
            throw Self.posixError()
        }
        defer { closedir(stream) }
        var result: [String] = []
        while true {
            errno = 0
            guard let entry = readdir(stream) else {
                if errno != 0 { throw Self.posixError() }
                break
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
            }
            if name != ".", name != ".." { result.append(name) }
        }
        return result.sorted()
    }

    func makeDirectory(_ name: String, mode: mode_t = 0o700) throws {
        try Self.validate(name)
        guard mkdirat(descriptor.raw, name, mode) == 0 else { throw Self.posixError() }
    }

    func linkTarget(_ name: String) throws -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
        let count = readlinkat(descriptor.raw, name, &buffer, buffer.count - 1)
        guard count >= 0, count < buffer.count - 1 else { throw Self.posixError() }
        return String(cString: buffer)
    }

    func makeLink(_ name: String, target: String) throws {
        try Self.validate(name)
        guard !target.contains("\0"), symlinkat(target, descriptor.raw, name) == 0 else { throw Self.posixError() }
    }

    func move(_ name: String, to target: SafeDirectory, named targetName: String) throws {
        try Self.validate(name)
        try Self.validate(targetName)
        // Unlike FileManager.moveItem, this never emulates EXDEV or overwrites a racing destination.
        guard renameatx_np(descriptor.raw, name, target.descriptor.raw, targetName, UInt32(RENAME_EXCL)) == 0 else {
            throw Self.posixError()
        }
    }

    /// Only used inside a private workspace or for an empty, identity-checked merge source.
    func removeOwned(_ name: String) throws {
        let info = try require(name)
        if info.kind == .directory {
            let child = try SafeDirectory(parent: self, name: name)
            guard try child.descriptor.identity.sameObject(as: info) else { throw SafeFileError.changed(child.url) }
            // Metadata may have made the private copy read-only.
            guard fchmod(child.descriptor.raw, 0o700) == 0 else { throw Self.posixError() }
            for entry in try child.names() { try child.removeOwned(entry) }
            guard try require(name).sameObject(as: info) else { throw SafeFileError.changed(child.url) }
            guard unlinkat(descriptor.raw, name, AT_REMOVEDIR) == 0 else { throw Self.posixError() }
        } else {
            guard unlinkat(descriptor.raw, name, 0) == 0 else { throw Self.posixError() }
        }
    }

    func tree(_ name: String) throws -> [String: FileIdentity] {
        var result: [String: FileIdentity] = [:]
        func visit(_ parent: SafeDirectory, _ name: String, _ path: String) throws {
            try Task.checkCancellation()
            let info = try parent.require(name)
            result[path] = info
            if info.kind == .directory {
                let child = try SafeDirectory(parent: parent, name: name)
                guard try child.descriptor.identity.sameObject(as: info) else { throw SafeFileError.changed(child.url) }
                for entry in try child.names() { try visit(child, entry, path + "/" + entry) }
            }
        }
        try visit(self, name, "")
        return result
    }
}

final class FileWorkspace {
    let parent: SafeDirectory
    let name = ".dumbcommander-" + UUID().uuidString
    let directory: SafeDirectory
    private let identity: FileIdentity

    init(in parent: SafeDirectory) throws {
        self.parent = parent
        try parent.makeDirectory(name)
        directory = try SafeDirectory(parent: parent, name: name)
        identity = try directory.descriptor.identity
    }

    func cleanUp() throws {
        guard let current = try parent.identity(name) else { return }
        guard current.sameObject(as: identity) else { throw SafeFileError.changed(directory.url) }
        try parent.removeOwned(name)
    }

    /// Retain the workspace on cleanup failure and report its actual path instead of hiding data.
    func finish(after error: Error? = nil) throws {
        do { try cleanUp() }
        catch let cleanup { throw SafeFileError.recovery(directory.url, (error?.localizedDescription ?? "") + " " + cleanup.localizedDescription) }
        if let error { throw error }
    }
}

enum FileMetadata {
    static func copy(from source: FileDescriptor, to destination: FileDescriptor, url: URL) throws {
        let before = try source.identity
        guard fcopyfile(source.raw, destination.raw, nil, copyfile_flags_t(COPYFILE_METADATA)) == 0 else {
            throw SafeDirectory.posixError()
        }
        // fcopyfile may choose an earlier destination creation time. Our contract preserves the source value.
        var birthAttributes = attrlist()
        birthAttributes.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        birthAttributes.commonattr = attrgroup_t(ATTR_CMN_CRTIME)
        var birth = timespec(tv_sec: before.birthSeconds, tv_nsec: before.birthNanos)
        guard fsetattrlist(destination.raw, &birthAttributes, &birth, MemoryLayout<timespec>.size, 0) == 0 else {
            throw SafeDirectory.posixError()
        }
        let after = try destination.identity
        guard before.mode == after.mode,
              before.modifiedSeconds == after.modifiedSeconds, before.modifiedNanos == after.modifiedNanos,
              before.birthSeconds == after.birthSeconds, before.birthNanos == after.birthNanos,
              before.flags == after.flags,
              try attributes(source) == attributes(destination),
              try acl(source) == acl(destination) else { throw SafeFileError.metadata(url) }
    }

    static func attributes(_ fd: FileDescriptor) throws -> [String: Data] {
        let size = flistxattr(fd.raw, nil, 0, 0)
        guard size >= 0 else { throw SafeDirectory.posixError() }
        if size == 0 { return [:] }
        var buffer = [CChar](repeating: 0, count: size)
        guard flistxattr(fd.raw, &buffer, size, 0) == size else { throw SafeDirectory.posixError() }
        var result: [String: Data] = [:]
        for bytes in buffer.split(separator: 0) {
            let name = String(decoding: bytes.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            let length = fgetxattr(fd.raw, name, nil, 0, 0, 0)
            guard length >= 0 else { throw SafeDirectory.posixError() }
            var data = Data(count: length)
            let read = data.withUnsafeMutableBytes { fgetxattr(fd.raw, name, $0.baseAddress, length, 0, 0) }
            guard read == length else { throw SafeDirectory.posixError() }
            result[name] = data
        }
        return result
    }

    static func acl(_ fd: FileDescriptor) throws -> String {
        guard let acl = acl_get_fd_np(fd.raw, ACL_TYPE_EXTENDED) else {
            if errno == ENOENT { return "" }
            throw SafeDirectory.posixError()
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        var size = 0
        guard let text = acl_to_text(acl, &size) else { throw SafeDirectory.posixError() }
        defer { acl_free(text) }
        return String(cString: text)
    }
}
