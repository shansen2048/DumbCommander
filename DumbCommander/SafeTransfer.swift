import Foundation
import Darwin

struct MutationExpectation: Sendable {
    var source: FileIdentity?
    var destination: FileIdentity?
    var sourceParent: FileIdentity?
    var destinationParent: FileIdentity?
    var sourceTree: [String: FileIdentity]?
    var destinationTree: [String: FileIdentity]?
}

/// Hooks inject races and errors deterministically in fixtures; production uses no hooks.
struct FileMutationHooks: Sendable {
    var beforePublish: (@Sendable (URL) throws -> Void)?
    var beforeMetadata: (@Sendable (URL) throws -> Void)?
    var beforeSourceRemoval: (@Sendable (URL) throws -> Void)?
    var afterTargetCapture: (@Sendable (URL) throws -> Void)?
}

struct SafeTransfer {
    let hooks: FileMutationHooks
    let chunkSize: Int
    let chunkDelay: Duration?
    let moveHandler: LocalFileSystemService.MoveHandler?

    func transfer(
        source: URL, destination: URL, moving: Bool, replacing: Bool,
        expectation: MutationExpectation?,
        progress: @escaping @Sendable (Int64) async -> Void
    ) async throws {
        try Task.checkCancellation()
        let from = try SafeDirectory(url: source.deletingLastPathComponent())
        let to = try SafeDirectory(url: destination.deletingLastPathComponent())
        let sourceName = source.lastPathComponent
        let targetName = destination.lastPathComponent
        try validateParents(from, to, expectation)
        let original = try from.require(sourceName, expected: expectation?.source)
        let target = try to.identity(targetName)
        if let expectation, replacing, target != expectation.destination { throw SafeFileError.changed(destination) }
        if !replacing, target != nil { throw FileSystemServiceError.destinationExists(destination) }
        if let target, original.sameObject(as: target) { throw SafeFileError.changed(destination) }
        if original.kind == .directory {
            // Compare pinned paths too: aliases, case-insensitive names and mount points must not permit self-copy.
            let sourcePath = source.resolvingSymlinksInPath().standardizedFileURL.path
            var ancestor = to
            while true {
                if try ancestor.descriptor.identity.sameObject(as: original) { throw SafeFileError.changed(destination) }
                if ancestor.url.path == "/" { break }
                ancestor = try SafeDirectory(url: ancestor.url.deletingLastPathComponent())
            }
            guard to.url.path != sourcePath, !to.url.path.hasPrefix(sourcePath + "/") else {
                throw SafeFileError.changed(destination)
            }
        }
        let sourceTree = try from.tree(sourceName)
        if let expected = expectation?.sourceTree, sourceTree != expected { throw SafeFileError.changed(source) }
        if sourceTree.values.contains(where: { $0.kind == .other }) { throw SafeFileError.unsupported(source) }

        if moving, !replacing {
            try hooks.beforePublish?(destination)
            _ = try from.require(sourceName, expected: original)
            do {
                if let moveHandler { try moveHandler(source, destination) }
                else { try from.move(sourceName, to: to, named: targetName) }
                guard let moved = try to.identity(targetName), moved.sameContents(as: original) else {
                    do { try to.move(targetName, to: from, named: sourceName) }
                    catch { throw SafeFileError.recovery(destination, error.localizedDescription) }
                    throw SafeFileError.changed(source)
                }
                await progress(max(1, original.size))
                return
            } catch let error as POSIXError where error.code == .EXDEV {
                // Only EXDEV permits copying followed by guarded source retirement.
            } catch {
                let underlying = error as NSError
                guard underlying.domain == NSPOSIXErrorDomain, underlying.code == Int(EXDEV) else { throw error }
            }
        }

        let workspace = try FileWorkspace(in: to)
        var retainWorkspace = false
        do {
            let expectedTargetTree = replacing && target != nil ? try to.tree(targetName) : nil
            if let expected = expectation?.destinationTree, expectedTargetTree != expected {
                throw SafeFileError.changed(destination)
            }
            var copied: Int64 = 0
            try await copyEntry(from: from, name: sourceName, to: workspace.directory, named: "new",
                                copied: &copied, progress: progress)
            guard try from.tree(sourceName) == sourceTree else { throw SafeFileError.changed(source) }
            try Task.checkCancellation()
            try hooks.beforePublish?(destination)
            // A replaced directory path must not silently redirect the final operation.
            try validateParents(SafeDirectory(url: source.deletingLastPathComponent()),
                                SafeDirectory(url: destination.deletingLastPathComponent()),
                                MutationExpectation(sourceParent: try from.descriptor.identity,
                                                    destinationParent: try to.descriptor.identity))
            if replacing, let expectedTargetTree {
                guard try to.tree(targetName) == expectedTargetTree else { throw SafeFileError.changed(destination) }
                try to.move(targetName, to: workspace.directory, named: "previous")
                retainWorkspace = true
                do {
                    let captured = try workspace.directory.tree("previous")
                    guard treesMatchAfterRename(captured, expectedTargetTree) else { throw SafeFileError.changed(destination) }
                    try hooks.afterTargetCapture?(destination)
                    try workspace.directory.move("new", to: to, named: targetName)
                } catch {
                    try restorePrevious(workspace, to: to, named: targetName)
                    retainWorkspace = false
                    throw error
                }
                retainWorkspace = false
            } else {
                try workspace.directory.move("new", to: to, named: targetName)
            }
            if moving {
                do {
                    try hooks.beforeSourceRemoval?(source)
                    // Publication is complete. Cancellation now must not leave an unreported partial move.
                    try await Task.detached {
                        try retireSource(from: from, name: sourceName, expected: sourceTree)
                    }.value
                } catch {
                    throw FileSystemServiceError.partialMove(source: source, destination: destination, reason: error.localizedDescription)
                }
            }
        } catch {
            if retainWorkspace { throw SafeFileError.recovery(workspace.directory.url, error.localizedDescription) }
            try workspace.finish(after: error)
        }
        try workspace.finish()
    }

    private func validateParents(_ from: SafeDirectory, _ to: SafeDirectory, _ expectation: MutationExpectation?) throws {
        if let expected = expectation?.sourceParent,
           try !from.descriptor.identity.sameObject(as: expected) { throw SafeFileError.changed(from.url) }
        if let expected = expectation?.destinationParent,
           try !to.descriptor.identity.sameObject(as: expected) { throw SafeFileError.changed(to.url) }
    }

    private func restorePrevious(_ workspace: FileWorkspace, to parent: SafeDirectory, named name: String) throws {
        do { try workspace.directory.move("previous", to: parent, named: name) }
        catch { throw SafeFileError.recovery(workspace.directory.url.appendingPathComponent("previous"), error.localizedDescription) }
    }

    private func treesMatchAfterRename(_ actual: [String: FileIdentity], _ expected: [String: FileIdentity]) -> Bool {
        guard actual.keys.count == expected.keys.count else { return false }
        return expected.allSatisfy { path, info in
            guard let other = actual[path] else { return false }
            return path.isEmpty ? info.sameContents(as: other) : info == other
        }
    }

    private func retireSource(from: SafeDirectory, name: String, expected: [String: FileIdentity]) throws {
        guard try from.tree(name) == expected else { throw SafeFileError.changed(from.url.appendingPathComponent(name)) }
        let workspace = try FileWorkspace(in: from)
        do {
            try from.move(name, to: workspace.directory, named: "source")
        } catch { try workspace.finish(after: error); return }
        let captured: [String: FileIdentity]
        do { captured = try workspace.directory.tree("source") }
        catch { throw SafeFileError.recovery(workspace.directory.url.appendingPathComponent("source"), error.localizedDescription) }
        guard treesMatchAfterRename(captured, expected) else {
            do { try workspace.directory.move("source", to: from, named: name) }
            catch { throw SafeFileError.recovery(workspace.directory.url.appendingPathComponent("source"), error.localizedDescription) }
            try workspace.finish(after: SafeFileError.changed(from.url.appendingPathComponent(name)))
            return
        }
        try workspace.finish()
    }

    private func copyEntry(
        from: SafeDirectory, name: String, to: SafeDirectory, named target: String,
        copied: inout Int64, progress: @escaping @Sendable (Int64) async -> Void
    ) async throws {
        try Task.checkCancellation()
        let info = try from.require(name)
        let sourceURL = from.url.appendingPathComponent(name)
        switch info.kind {
        case .other: throw SafeFileError.unsupported(sourceURL)
        case .symbolicLink:
            let link = try from.linkTarget(name)
            let input = try from.openFile(name, flags: O_RDONLY | O_SYMLINK)
            guard try input.identity == info else { throw SafeFileError.changed(sourceURL) }
            try to.makeLink(target, target: link)
            let output = try to.openFile(target, flags: O_RDONLY | O_SYMLINK)
            try hooks.beforeMetadata?(sourceURL)
            // Link descriptors preserve the link itself, including broken links.
            guard fcopyfile(input.raw, output.raw, nil, copyfile_flags_t(COPYFILE_METADATA)) == 0 else {
                throw SafeDirectory.posixError()
            }
            _ = try from.require(name, expected: info)
            copied += max(1, info.size)
            await progress(copied)
        case .directory:
            let sourceDirectory = try SafeDirectory(parent: from, name: name)
            guard try sourceDirectory.descriptor.identity == info else { throw SafeFileError.changed(sourceURL) }
            try to.makeDirectory(target)
            let targetDirectory = try SafeDirectory(parent: to, name: target)
            for child in try sourceDirectory.names() {
                try await copyEntry(from: sourceDirectory, name: child, to: targetDirectory,
                                    named: child, copied: &copied, progress: progress)
            }
            try hooks.beforeMetadata?(sourceURL)
            try FileMetadata.copy(from: sourceDirectory.descriptor, to: targetDirectory.descriptor, url: sourceURL)
        case .regularFile:
            let input = try from.openFile(name, flags: O_RDONLY)
            guard try input.identity == info else { throw SafeFileError.changed(sourceURL) }
            let output = try to.openFile(target, flags: O_WRONLY | O_CREAT | O_EXCL)
            var buffer = [UInt8](repeating: 0, count: chunkSize)
            while true {
                try Task.checkCancellation()
                let count = Darwin.read(input.raw, &buffer, buffer.count)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw SafeDirectory.posixError()
                }
                if count == 0 { break }
                try buffer.withUnsafeBytes { bytes in
                    var offset = 0
                    while offset < count {
                        let written = Darwin.write(output.raw, bytes.baseAddress!.advanced(by: offset), count - offset)
                        if written < 0, errno == EINTR { continue }
                        guard written > 0 else { throw SafeDirectory.posixError() }
                        offset += written
                    }
                }
                copied += Int64(count)
                await progress(copied)
                if let chunkDelay { try await Task.sleep(for: chunkDelay) }
            }
            try hooks.beforeMetadata?(sourceURL)
            try FileMetadata.copy(from: input, to: output, url: sourceURL)
            guard fsync(output.raw) == 0 else { throw SafeDirectory.posixError() }
            guard try input.identity == info else { throw SafeFileError.changed(sourceURL) }
        }
    }
}
