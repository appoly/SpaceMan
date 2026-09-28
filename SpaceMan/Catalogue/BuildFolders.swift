import Foundation

nonisolated enum ProjectKind: Sendable, Equatable {
    case apple
    case gradle
    case web
}

nonisolated struct BuildProject: Sendable, Equatable {
    let kind: ProjectKind
    /// The folder named in the row: the Xcode or Swift package project, the Gradle root, or the web app.
    let root: String
}

/// Recognises `build`/`.build` folders that hold regenerable output. A folder qualifies only when git ignores it
/// itself but not the folder it sits in: that excludes tracked `build` folders and ones inside ignored dependency
/// trees such as `.venv/` or `vendor/`, where "build" is often library source.
nonisolated struct BuildFolderDetector: Sendable {
    typealias GitStatus = @Sendable (_ folder: String) -> GitIgnoreStatus

    private let detect: @Sendable (_ buildFolder: String) -> BuildProject?

    init(gitStatus: @escaping GitStatus = { Git.ignoreStatus(of: $0) }) {
        detect = { path in
            let parent = path.deletingLastPathComponent
            guard gitStatus(path) == .ignored, gitStatus(parent) != .ignored else { return nil }
            return Self.project(containing: parent)
        }
    }

    init(detect: @escaping @Sendable (_ buildFolder: String) -> BuildProject?) {
        self.detect = detect
    }

    func project(forBuildFolderAt path: String) -> BuildProject? {
        detect(path)
    }

    private static func project(containing parent: String) -> BuildProject? {
        let names = contents(of: parent)
        if names.contains(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") })
            || names.contains("Package.swift") {
            return BuildProject(kind: .apple, root: parent)
        }
        if names.contains(where: gradleBuildFiles.contains) {
            // A module's build folder (app/build) is named after the Gradle root that holds settings.gradle.
            let grandparent = parent.deletingLastPathComponent
            let root = names.contains(where: gradleSettingsFiles.contains) ? parent
                : contents(of: grandparent).contains(where: gradleSettingsFiles.contains) ? grandparent : parent
            return BuildProject(kind: .gradle, root: root)
        }
        // Laravel and similar keep their build output in public/build, a level below package.json.
        for folder in [parent, parent.deletingLastPathComponent]
        where contents(of: folder).contains(where: webManifests.contains) {
            return BuildProject(kind: .web, root: folder)
        }
        return nil
    }

    private static let gradleBuildFiles: Set = ["build.gradle", "build.gradle.kts"]
    private static let gradleSettingsFiles: Set = ["settings.gradle", "settings.gradle.kts"]
    private static let webManifests: Set = ["package.json", "composer.json"]

    private static func contents(of folder: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
    }
}

nonisolated enum GitIgnoreStatus: Sendable, Equatable {
    case ignored
    /// Tracked, untracked-but-not-ignored, or not in a repository.
    case notIgnored
    case unknown
}

nonisolated enum Git {
    /// `/usr/bin/git` is a stub that offers to install the command line tools when they're missing, so only use it
    /// once `xcode-select` confirms they're present; otherwise fall back to Homebrew's git.
    static let executable: String? = {
        let selectTool = Process()
        selectTool.executableURL = URL(filePath: "/usr/bin/xcode-select")
        selectTool.arguments = ["-p"]
        selectTool.standardOutput = FileHandle.nullDevice
        selectTool.standardError = FileHandle.nullDevice
        if (try? selectTool.run()) != nil {
            selectTool.waitUntilExit()
            if selectTool.terminationStatus == 0 {
                return "/usr/bin/git"
            }
        }
        return ["/opt/homebrew/bin/git", "/usr/local/bin/git"].first(where: FileManager.default.isExecutableFile)
    }()

    static func ignoreStatus(of folder: String) -> GitIgnoreStatus {
        guard let executable else { return .unknown }
        let parent = folder.deletingLastPathComponent
        let name = folder.lastPathComponent
        guard let hasTrackedFiles = run(executable, in: parent, ["ls-files", "--", name]).map({ !$0.output.isEmpty })
        else { return .unknown }
        if hasTrackedFiles {
            return .notIgnored
        }
        // Exit status 0 means ignored, 1 not ignored, 128 not a repository.
        return run(executable, in: parent, ["check-ignore", "-q", "--", name])?.status == 0 ? .ignored : .notIgnored
    }

    private static func run(
        _ executable: String, in folder: String, _ arguments: [String]
    ) -> (status: Int32, output: Data)? {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = ["-C", folder] + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, data)
    }
}

nonisolated extension Namer {
    /// `~/Code/UDRN-Android/app/build` → `UDRN-Android build artefacts`, subtitled `app/build`.
    static func buildArtefactsName(path: String, context: NamingContext) -> ItemName {
        let root = context.buildProject(at: path)?.root ?? path.deletingLastPathComponent
        let relativePath = String(path.dropFirst(root.count + 1))
        return ItemName(
            title: "\(root.lastPathComponent) build artefacts",
            subtitle: relativePath == "build" ? nil : relativePath
        )
    }
}

nonisolated extension Catalogue {
    /// `build` and `.build` folders at any depth in the usual code folders, sorted by project kind.
    private static let projectBuildFolders = "~/{Code,Projects,Developer}/**/{build,.build}"

    static let projectBuildFolderRules: [Rule] = [
        Rule(.appleDevelopment, "Project build folders", projectBuildFolders, .buildArtefacts,
             about: "Build output an Xcode project or Swift package wrote beside its sources rather than into " +
                "DerivedData. Git ignores it, and building again recreates it.",
             condition: .buildFolder(.apple)),
        Rule(.androidDevelopment, "Project build folders", projectBuildFolders, .buildArtefacts,
             about: "Gradle build output. Git ignores it, and building again recreates it.",
             condition: .buildFolder(.gradle)),
        Rule(.webDevelopment, "Project build folders", projectBuildFolders, .buildArtefacts,
             about: "Compiled front-end assets. Git ignores them, and the project's build command recreates them.",
             condition: .buildFolder(.web))
    ]
}
