import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Runs `xcodebuild` on a container: lists its schemes, chooses where each
/// builds, and builds each into one derived data directory, writing its index.
struct XcodeBuild: Sendable {
    let runner: CommandRunner
    let container: XcodeContainer
    /// The environment `xcodebuild` runs in: Xcode's toolchain unless one is named.
    let environment: [String: String]

    init(runner: CommandRunner, container: XcodeContainer, toolchain: String?) {
        self.runner = runner
        self.container = container
        var environment = ProcessInfo.processInfo.environment
        environment["TOOLCHAINS"] = toolchain
        self.environment = environment
    }

    /// The schemes the container itself defines that build something
    /// other than tests: those with a scheme file under it or under one of
    /// its projects, unless every target the file builds is a test target;
    /// and those named after one of its targets that is not a test target.
    /// Package dependencies' schemes are not among them.
    func schemes(targets: Set<String>, testTargets: Set<String>) throws(FrontendError) -> [String] {
        let data = try runner.run(["xcodebuild", "-list", "-json"] + container.arguments, environment: environment)
        struct Listing: Decodable {
            struct Container: Decodable { let schemes: [String]? }
            let project: Container?
            let workspace: Container?
        }
        let listing: Listing
        do {
            listing = try JSONDecoder().decode(Listing.self, from: data)
        } catch {
            throw .projectUnreadable(path: container.location, reason: "`xcodebuild -list` printed no listing: \(error)")
        }
        let listed = (listing.workspace ?? listing.project)?.schemes ?? []
        var built: [String: [String]] = [:]
        for container in [container.path] + container.projects {
            for file in try XcodeBuild.schemeFiles(under: container) where built[file.name] == nil {
                built[file.name] = try XcodeBuild.builtTargets(of: file.url)
            }
        }
        return listed.filter { scheme in
            if let targetsBuilt = built[scheme] {
                return !targetsBuilt.allSatisfy(testTargets.contains)
            }
            return targets.contains(scheme) && !testTargets.contains(scheme)
        }
    }

    /// Where `scheme` builds: for macOS when every target in it supports
    /// macOS, else for the iOS Simulator, else for a simulator all of them support.
    func destination(of scheme: String) throws(FrontendError) -> String {
        let arguments = ["xcodebuild", "-showBuildSettings", "-json", "-scheme", scheme] + container.arguments
        let data = try runner.run(arguments, environment: environment)
        struct Settings: Decodable {
            struct Values: Decodable {
                let supported: String?
                enum CodingKeys: String, CodingKey { case supported = "SUPPORTED_PLATFORMS" }
            }
            let buildSettings: Values
        }
        let settings: [Settings]
        do {
            settings = try JSONDecoder().decode([Settings].self, from: data)
        } catch {
            throw .projectUnreadable(path: container.location, reason: "scheme \(scheme): no build settings: \(error)")
        }
        let platforms = settings.map { Set(($0.buildSettings.supported ?? "").split(separator: " ").map(String.init)) }
        let common = platforms.dropFirst().reduce(platforms.first ?? []) { $0.intersection($1) }
        let destinations = [
            ("macosx", "generic/platform=macOS"),
            ("iphonesimulator", "generic/platform=iOS Simulator"),
            ("xrsimulator", "generic/platform=visionOS Simulator"),
            ("appletvsimulator", "generic/platform=tvOS Simulator"),
            ("watchsimulator", "generic/platform=watchOS Simulator"),
        ]
        guard let chosen = destinations.first(where: { common.contains($0.0) }) else {
            throw .noDestination(scheme: scheme)
        }
        return chosen.1
    }

    /// Builds `scheme` for `destination` into `derivedData`, writing the index,
    /// unsigned, for the running Mac's architecture only.
    func build(scheme: String, destination: String, derivedData: URL) throws(FrontendError) {
        let arguments = ["xcodebuild", "build", "-scheme", scheme, "-destination", destination,
                         "-derivedDataPath", derivedData.path] + container.arguments + [
            "COMPILER_INDEX_STORE_ENABLE=YES", "CODE_SIGNING_ALLOWED=NO",
            "ARCHS=\(XcodeBuild.architecture)", "ONLY_ACTIVE_ARCH=YES",
        ]
        let output = try runner.runAllowingFailure(arguments, environment: environment)
        guard output.status == 0 else {
            let printed = String(decoding: output.standardOutput, as: UTF8.self)
            let errors = (printed + output.standardError).split(separator: "\n").filter { $0.contains("error:") }
            throw .commandFailed(
                command: arguments.joined(separator: " "),
                status: output.status,
                output: errors.isEmpty ? output.standardError : errors.joined(separator: "\n")
            )
        }
    }

    /// The running Mac's architecture, as `xcodebuild` names it.
    static var architecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }

    /// The scheme files under a project or workspace, shared and per user,
    /// by scheme name. A directory that is not there holds none; one that is
    /// there and cannot be read is an error.
    private static func schemeFiles(under container: URL) throws(FrontendError) -> [(name: String, url: URL)] {
        func entries(_ directory: URL) throws(FrontendError) -> [String] {
            guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
            do {
                return try FileManager.default.contentsOfDirectory(atPath: directory.path)
            } catch {
                throw .projectUnreadable(path: directory.path, reason: String(describing: error))
            }
        }
        var directories = [container.appendingPathComponent("xcshareddata/xcschemes")]
        let users = container.appendingPathComponent("xcuserdata")
        directories += try entries(users).map { users.appendingPathComponent($0).appendingPathComponent("xcschemes") }
        var files: [(name: String, url: URL)] = []
        for directory in directories {
            for entry in try entries(directory) where entry.hasSuffix(".xcscheme") {
                files.append((String(entry.dropLast(".xcscheme".count)), directory.appendingPathComponent(entry)))
            }
        }
        return files
    }

    /// The targets a scheme file's build action builds, by name.
    private static func builtTargets(of scheme: URL) throws(FrontendError) -> [String] {
        let data: Data
        do {
            data = try Data(contentsOf: scheme)
        } catch {
            throw .projectUnreadable(path: scheme.path, reason: String(describing: error))
        }
        let reader = SchemeReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse() else {
            throw .projectUnreadable(path: scheme.path, reason: parser.parserError.map(String.init(describing:)) ?? "not XML")
        }
        return reader.built
    }
}

/// Collects the targets a scheme's build action names.
private final class SchemeReader: NSObject, XMLParserDelegate {
    private var inBuildAction = false
    private(set) var built: [String] = []

    func parser(
        _ parser: XMLParser,
        didStartElement name: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        if name == "BuildAction" { inBuildAction = true }
        if inBuildAction, name == "BuildableReference", let target = attributes["BlueprintName"] {
            built.append(target)
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "BuildAction" { inBuildAction = false }
    }
}
