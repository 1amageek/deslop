import Foundation
import Testing
@testable import DeslopSwift

/// How the Xcode frontend reads projects and workspaces, without building.
@Suite("Xcode project reading")
struct XcodeProjectTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("deslop-xcode-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    /// A project of two targets: `App`, whose files are listed in groups
    /// (`Sources/App/A.swift`, and `Shared.swift` by its project-relative
    /// path), and `Kit`, a synchronized folder `Kit` whose exceptions take
    /// `Kit/Skipped.swift` out of it.
    private func project(in root: URL) throws -> URL {
        let project = root.appendingPathComponent("App.xcodeproj")
        try write("""
            // !$*UTF8*$!
            {
                archiveVersion = 1;
                objectVersion = 77;
                objects = {
                    P0 = { isa = PBXProject; mainGroup = G0; projectDirPath = ""; targets = (T1, T2); };
                    G0 = { isa = PBXGroup; children = (G1, F2, S1); sourceTree = "<group>"; };
                    G1 = { isa = PBXGroup; children = (F1); path = Sources/App; sourceTree = "<group>"; };
                    F1 = { isa = PBXFileReference; path = A.swift; sourceTree = "<group>"; };
                    F2 = { isa = PBXFileReference; path = Shared.swift; sourceTree = SOURCE_ROOT; };
                    B1 = { isa = PBXBuildFile; fileRef = F1; };
                    B2 = { isa = PBXBuildFile; fileRef = F2; };
                    BP = { isa = PBXSourcesBuildPhase; files = (B1, B2); };
                    T1 = { isa = PBXNativeTarget; name = App; buildPhases = (BP); productType = "com.apple.product-type.application"; };
                    S1 = { isa = PBXFileSystemSynchronizedRootGroup; path = Kit; sourceTree = "<group>"; exceptions = (E1); };
                    E1 = { isa = PBXFileSystemSynchronizedBuildFileExceptionSet; membershipExceptions = (Skipped.swift); target = T2; };
                    T2 = { isa = PBXNativeTarget; name = KitTests; fileSystemSynchronizedGroups = (S1); productType = "com.apple.product-type.bundle.unit-test"; };
                };
                rootObject = P0;
            }
            """, to: project.appendingPathComponent("project.pbxproj"))
        for file in ["Sources/App/A.swift", "Shared.swift", "Kit/Kept.swift", "Kit/Deep/Also.swift", "Kit/Skipped.swift"] {
            try write("let x = 1\n", to: root.appendingPathComponent(file))
        }
        return project
    }

    @Test("a target's files are found through its groups, and a synchronized folder's less its exceptions")
    func targets() throws {
        let root = try directory()
        defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: root) } }
        let file = try XcodeProjectFile.read(try project(in: root), root: root, runner: CommandRunner())
        let app = try #require(file.targets.first { $0.name == "App" })
        #expect(app.listedSources == ["Shared.swift", "Sources/App/A.swift"])
        #expect(!app.isTest)
        let kit = try #require(file.targets.first { $0.name == "KitTests" })
        #expect(kit.synchronizedFolders == ["Kit"])
        #expect(kit.listedSources == ["Kit/Deep/Also.swift", "Kit/Kept.swift"])
        #expect(kit.isTest)
    }

    @Test("the one workspace, else the one project, is what is built; none or two is an error")
    func locate() throws {
        let root = try directory()
        defer { #expect(throws: Never.self) { try FileManager.default.removeItem(at: root) } }
        #expect(throws: FrontendError.noProject(directory: root.path)) {
            try XcodeContainer.locate(root: root, project: nil, workspace: nil)
        }
        _ = try project(in: root)
        #expect(try XcodeContainer.locate(root: root, project: nil, workspace: nil).kind == .project)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Other.xcodeproj"), withIntermediateDirectories: true)
        #expect(throws: FrontendError.ambiguousProject(directory: root.path, candidates: ["App.xcodeproj", "Other.xcodeproj"])) {
            try XcodeContainer.locate(root: root, project: nil, workspace: nil)
        }
        try write("""
            <?xml version="1.0" encoding="UTF-8"?>
            <Workspace version = "1.0">
               <FileRef location = "group:App.xcodeproj"></FileRef>
               <Group location = "group:Nested" name = "Nested">
                  <FileRef location = "group:Inner.xcodeproj"></FileRef>
               </Group>
            </Workspace>
            """, to: root.appendingPathComponent("All.xcworkspace/contents.xcworkspacedata"))
        let workspace = try XcodeContainer.locate(root: root, project: nil, workspace: nil)
        #expect(workspace.kind == .workspace)
        #expect(workspace.projects.map(\.lastPathComponent) == ["App.xcodeproj", "Inner.xcodeproj"])
        #expect(workspace.projects.last?.deletingLastPathComponent().lastPathComponent == "Nested")
    }

    @Test("a non-test target no built scheme compiled is an error, unless only some schemes were asked for")
    func targetNotBuilt() throws {
        let root = URL(fileURLWithPath: "/project")
        let targets = [
            XcodeProjectFile.Target(name: "App", productType: "com.apple.product-type.application",
                                    synchronizedFolders: ["App"], listedSources: ["App/A.swift"]),
            XcodeProjectFile.Target(name: "Widget", productType: "com.apple.product-type.app-extension",
                                    synchronizedFolders: ["Widget"], listedSources: ["Widget/W.swift"]),
        ]
        let compiled = [(module: "App", file: "/project/App/A.swift"), (module: "Kit", file: "/project/Kit/Sources/Kit/K.swift")]
        let derivedData = root.appendingPathComponent(".build/deslop/xcode")
        #expect(throws: FrontendError.targetNotBuilt(target: "Widget")) {
            try XcodeFrontend.layoutTargets(targets, compiled: compiled, root: root, derivedData: derivedData, schemesNamed: false)
        }
        let some = try XcodeFrontend.layoutTargets(targets, compiled: compiled, root: root, derivedData: derivedData, schemesNamed: true)
        #expect(some.map(\.name) == ["App", "Widget", "Kit"])
        #expect(some.map(\.indexed) == [true, false, true])
        #expect(some.last?.root == "Kit/Sources/Kit")
    }
}
