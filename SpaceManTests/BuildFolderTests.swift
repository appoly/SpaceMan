import Foundation
import Testing
@testable import SpaceMan

struct BuildFolderDetectorTests {
    private let root = FileManager.default.temporaryDirectory.appending(path: "BuildFolders-\(UUID().uuidString)").path

    private func make(_ relativePath: String, file: Bool = false) throws {
        let url = URL(filePath: root).appending(path: relativePath)
        if file {
            let parent = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            try Data().write(to: url)
        } else {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    /// Git reports the named folders as ignored and everything else as not.
    private func detector(ignoring ignored: Set<String>) -> BuildFolderDetector {
        let root = root
        return BuildFolderDetector { ignored.contains(String($0.dropFirst(root.count + 1))) ? .ignored : .notIgnored }
    }

    private func project(_ relativePath: String, ignoring ignored: Set<String>) -> BuildProject? {
        detector(ignoring: ignored).project(forBuildFolderAt: root + "/" + relativePath)
    }

    @Test func recognisesEachKindOfProjectAndItsRoot() throws {
        try make("App/App.xcodeproj")
        try make("App/build")
        try make("Package/Package.swift", file: true)
        try make("Package/.build")
        try make("Android/settings.gradle", file: true)
        try make("Android/app/build.gradle.kts", file: true)
        try make("Android/app/build")
        try make("Site/composer.json", file: true)
        try make("Site/public/build")
        let ignored: Set = ["App/build", "Package/.build", "Android/app/build", "Site/public/build"]

        #expect(project("App/build", ignoring: ignored) == BuildProject(kind: .apple, root: root + "/App"))
        #expect(project("Package/.build", ignoring: ignored) == BuildProject(kind: .apple, root: root + "/Package"))
        #expect(project("Android/app/build", ignoring: ignored) == BuildProject(kind: .gradle, root: root + "/Android"))
        #expect(project("Site/public/build", ignoring: ignored) == BuildProject(kind: .web, root: root + "/Site"))
    }

    @Test func refusesFoldersGitDoesNotIgnoreOrThatSitInsideIgnoredFolders() throws {
        try make("Tracked/Tracked.xcodeproj")
        try make("Tracked/build")
        try make("venv/package.json", file: true)
        try make("venv/build")

        #expect(project("Tracked/build", ignoring: []) == nil)
        #expect(project("venv/build", ignoring: ["venv", "venv/build"]) == nil)
    }

    @Test func refusesFoldersOutsideAnyRecognisedProject() throws {
        try make("Notes/build")
        #expect(project("Notes/build", ignoring: ["Notes/build"]) == nil)
    }
}

struct BuildFolderRuleTests {
    private func folder(_ name: String, _ size: Int64 = 0, _ children: [FSNode] = []) -> FSNode {
        FSNode(name: name, isDirectory: true, size: size + children.reduce(0) { $0 + $1.size }, children: children)
    }

    private func folder(_ name: String, _ children: [FSNode]) -> FSNode {
        folder(name, 0, children)
    }

    @Test func anyDepthMatchesClaimOnlyOutermostFoldersThatMeetTheCondition() throws {
        let tree = folder("/", [folder("Users", [folder("test", [folder("Code", [
            folder("Shallow", [folder("build", 10)]),
            folder("Group", [folder("Deep", [folder(".build", 20, [folder("build", 5)])])]),
            folder("Android", [folder("build", 7)])
        ])])])])
        let kinds: [String: ProjectKind] = [
            "/Users/test/Code/Shallow/build": .apple, "/Users/test/Code/Group/Deep/.build": .apple,
            "/Users/test/Code/Group/Deep/.build/build": .apple, "/Users/test/Code/Android/build": .gradle
        ]
        let context = NamingContext(
            home: "/Users/test", osBuild: "26A1", simulatorRuntimes: nil, unavailableSimulatorUDIDs: [],
            buildFolderDetector: BuildFolderDetector { path in
                kinds[path].map { BuildProject(kind: $0, root: path.deletingLastPathComponent) }
            }
        )
        let rule = Rule(
            .appleDevelopment, "Builds", "~/Code/**/{build,.build}", .buildArtefacts, condition: .buildFolder(.apple)
        )

        let categories = Classifier(root: tree, rules: [rule], context: context, minimumSize: 1).classify()

        let group = try #require(categories.item(withID: "group:appleDevelopment:Builds"))
        #expect(Set(group.children?.compactMap(\.path) ?? []) == [
            "/Users/test/Code/Shallow/build", "/Users/test/Code/Group/Deep/.build"
        ])
        let nested = try #require(categories.item(withPath: "/Users/test/Code/Group/Deep/.build"))
        #expect(nested.size == 25)
        #expect(nested.title == "Deep build artefacts")
        #expect(nested.subtitle == ".build")
        #expect(categories.item(withPath: "/Users/test/Code/Shallow/build")?.subtitle == nil)
    }
}
