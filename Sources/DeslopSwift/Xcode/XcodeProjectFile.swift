import Foundation

/// The native targets of an Xcode project, read from its `project.pbxproj`
/// (as `plutil` converts it to JSON): what each is, where its files are,
/// and which Swift files it lists.
struct XcodeProjectFile: Sendable {
    /// A native target, its paths relative to the root `deslop` runs on.
    struct Target: Sendable {
        let name: String
        let productType: String
        /// Its file-system-synchronized folders, in the order the project lists them.
        let synchronizedFolders: [String]
        /// The Swift files the project names for it: those of its
        /// synchronized folders, less the files its exceptions take out, and
        /// those of its sources build phase.
        let listedSources: [String]

        var isTest: Bool {
            productType.hasSuffix(".bundle.unit-test") || productType.hasSuffix(".bundle.ui-testing")
        }
    }

    let targets: [Target]

    /// The targets of the project at `project`, a `.xcodeproj`; paths are
    /// made relative to `root`, and those outside it are left out.
    static func read(_ project: URL, root: URL, runner: CommandRunner) throws(FrontendError) -> XcodeProjectFile {
        let file = project.appendingPathComponent("project.pbxproj")
        let data = try runner.run(["plutil", "-convert", "json", "-o", "-", file.path])
        let document: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw FrontendError.projectUnreadable(path: file.path, reason: "not a property list of objects")
            }
            document = parsed
        } catch let error as FrontendError {
            throw error
        } catch {
            throw .projectUnreadable(path: file.path, reason: String(describing: error))
        }
        guard let objects = document["objects"] as? [String: [String: Any]],
              let rootObject = document["rootObject"] as? String,
              let projectObject = objects[rootObject] else {
            throw .projectUnreadable(path: file.path, reason: "no root object")
        }
        let paths = ObjectPaths(
            objects: objects,
            projectDirectory: project.deletingLastPathComponent()
                .appendingPathComponent(projectObject["projectDirPath"] as? String ?? "")
        )
        let rootPath = IndexStoreReader.canonical(root.path)
        func relative(_ url: URL) -> String? {
            let path = IndexStoreReader.canonical(url.path)
            guard path.hasPrefix(rootPath + "/") else { return nil }
            return String(path.dropFirst(rootPath.count + 1))
        }
        var targets: [Target] = []
        for id in projectObject["targets"] as? [String] ?? [] {
            guard let target = objects[id], target["isa"] as? String == "PBXNativeTarget",
                  let name = target["name"] as? String else { continue }
            var folders: [String] = []
            var listed: [String] = []
            for groupID in target["fileSystemSynchronizedGroups"] as? [String] ?? [] {
                guard let folder = paths.url(of: groupID) else { continue }
                if let path = relative(folder) { folders.append(path) }
                let excluded = paths.exceptions(of: groupID, for: id).map { folder.appendingPathComponent($0).standardizedFileURL }
                listed += swiftFiles(in: folder).filter { !excluded.contains($0) }.compactMap(relative)
            }
            for phaseID in target["buildPhases"] as? [String] ?? [] {
                guard let phase = objects[phaseID], phase["isa"] as? String == "PBXSourcesBuildPhase" else { continue }
                for buildFileID in phase["files"] as? [String] ?? [] {
                    guard let reference = objects[buildFileID]?["fileRef"] as? String,
                          let url = paths.url(of: reference), url.pathExtension == "swift",
                          let path = relative(url) else { continue }
                    listed.append(path)
                }
            }
            targets.append(Target(
                name: name,
                productType: target["productType"] as? String ?? "",
                synchronizedFolders: folders,
                listedSources: Array(Set(listed)).sorted()
            ))
        }
        return XcodeProjectFile(targets: targets)
    }

    /// Every Swift file below `folder`, symbolic links resolved.
    private static func swiftFiles(in folder: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { return [] }
        var found: [URL] = []
        while let next = walker.nextObject() as? URL {
            if next.pathExtension == "swift" { found.append(next.standardizedFileURL) }
        }
        return found
    }
}

/// Where the objects of a project file are on disk: each file reference's
/// and group's path through the groups that hold it.
private struct ObjectPaths {
    let objects: [String: [String: Any]]
    let projectDirectory: URL
    /// By object, the group that holds it.
    private let parents: [String: String]

    init(objects: [String: [String: Any]], projectDirectory: URL) {
        self.objects = objects
        self.projectDirectory = projectDirectory
        var parents: [String: String] = [:]
        for (id, object) in objects {
            for child in object["children"] as? [String] ?? [] {
                parents[child] = id
            }
        }
        self.parents = parents
    }

    /// Where the object `id` is, if its source tree is the project's.
    func url(of id: String, depth: Int = 0) -> URL? {
        guard depth < 64, let object = objects[id] else { return nil }
        let path = object["path"] as? String ?? ""
        switch object["sourceTree"] as? String ?? "<group>" {
        case "<group>":
            guard let parent = parents[id] else { return projectDirectory.appendingPathComponent(path) }
            return url(of: parent, depth: depth + 1).map { path.isEmpty ? $0 : $0.appendingPathComponent(path) }
        case "SOURCE_ROOT":
            return projectDirectory.appendingPathComponent(path)
        case "<absolute>":
            return URL(fileURLWithPath: path)
        default:
            return nil
        }
    }

    /// The files, relative to the synchronized folder `group`, that its
    /// exceptions take out of the target `target`.
    func exceptions(of group: String, for target: String) -> [String] {
        (objects[group]?["exceptions"] as? [String] ?? []).flatMap { id -> [String] in
            guard let set = objects[id], set["target"] as? String == target else { return [] }
            return set["membershipExceptions"] as? [String] ?? []
        }
    }
}
