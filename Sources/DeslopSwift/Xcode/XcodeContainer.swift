import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// What `xcodebuild` builds: a workspace, or a project; and the projects it holds.
struct XcodeContainer: Sendable {
    enum Kind: Sendable {
        case project
        case workspace
    }

    let kind: Kind
    /// The `.xcodeproj` or `.xcworkspace`.
    let path: URL
    /// The `.xcodeproj`s it holds: itself, for a project.
    let projects: [URL]

    /// Where it is, as messages name it.
    var location: String { path.path }

    /// How `xcodebuild` is told what to build.
    var arguments: [String] {
        kind == .workspace ? ["-workspace", path.path] : ["-project", path.path]
    }

    /// The container at `root`: the one `project` or `workspace` names,
    /// relative to `root`; else the one workspace at the top of `root`; else
    /// the one project there.
    static func locate(root: URL, project: String?, workspace: String?) throws(FrontendError) -> XcodeContainer {
        if let workspace {
            return try XcodeContainer.workspace(URL(fileURLWithPath: workspace, relativeTo: root).standardizedFileURL)
        }
        if let project {
            let url = URL(fileURLWithPath: project, relativeTo: root).standardizedFileURL
            return XcodeContainer(kind: .project, path: url, projects: [url])
        }
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        } catch {
            throw .noProject(directory: root.path)
        }
        let workspaces = entries.filter { $0.pathExtension == "xcworkspace" }.sorted { $0.path < $1.path }
        let projects = entries.filter { $0.pathExtension == "xcodeproj" }.sorted { $0.path < $1.path }
        if workspaces.count > 1 {
            throw .ambiguousProject(directory: root.path, candidates: workspaces.map(\.lastPathComponent))
        }
        if let only = workspaces.first {
            return try XcodeContainer.workspace(only)
        }
        if projects.count > 1 {
            throw .ambiguousProject(directory: root.path, candidates: projects.map(\.lastPathComponent))
        }
        guard let only = projects.first else { throw .noProject(directory: root.path) }
        return XcodeContainer(kind: .project, path: only, projects: [only])
    }

    /// A workspace and the projects its `contents.xcworkspacedata` names.
    private static func workspace(_ url: URL) throws(FrontendError) -> XcodeContainer {
        let data: Data
        do {
            data = try Data(contentsOf: url.appendingPathComponent("contents.xcworkspacedata"))
        } catch {
            throw .projectUnreadable(path: url.path, reason: String(describing: error))
        }
        let reader = WorkspaceReader(base: url.deletingLastPathComponent())
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse() else {
            throw .projectUnreadable(path: url.path, reason: parser.parserError.map(String.init(describing:)) ?? "not XML")
        }
        return XcodeContainer(kind: .workspace, path: url, projects: reader.projects)
    }
}

/// Collects the projects a workspace's contents name, through its groups.
private final class WorkspaceReader: NSObject, XMLParserDelegate {
    private var directories: [URL]
    private(set) var projects: [URL] = []

    init(base: URL) {
        directories = [base]
    }

    func parser(
        _ parser: XMLParser,
        didStartElement name: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        guard name == "Group" || name == "FileRef", let location = attributes["location"],
              let url = resolve(location) else {
            if name == "Group" { directories.append(directories.last ?? URL(fileURLWithPath: "/")) }
            return
        }
        if name == "Group" {
            directories.append(url)
        } else if url.pathExtension == "xcodeproj" {
            projects.append(url.standardizedFileURL)
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "Group", directories.count > 1 { directories.removeLast() }
    }

    /// A location as a workspace writes it: `group:App.xcodeproj`,
    /// `container:App.xcodeproj`, `absolute:/path`.
    private func resolve(_ location: String) -> URL? {
        guard let colon = location.firstIndex(of: ":") else { return nil }
        let scheme = location[..<colon]
        let path = String(location[location.index(after: colon)...])
        switch scheme {
        case "absolute":
            return URL(fileURLWithPath: path)
        case "group", "container", "self":
            let base = directories.last ?? URL(fileURLWithPath: "/")
            return path.isEmpty ? base : base.appendingPathComponent(path)
        default:
            return nil
        }
    }
}
