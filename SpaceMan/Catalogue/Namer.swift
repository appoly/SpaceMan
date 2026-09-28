import Foundation

nonisolated struct ItemName: Sendable, Equatable {
    var title: String
    var subtitle: String?
    var flags: [String] = []
}

/// How to derive a human-friendly name for a folder or file from its path and, where available, its metadata.
nonisolated enum Namer: Sendable {
    case fixed(String)
    case folderName
    case appBundle
    case bundleIdentifier
    case appContainer
    case groupContainer
    case simulatorRuntimeAsset
    case simulatorRuntimeBundle
    case simulatorDevice
    case deviceSupportFolder
    case deviceSupportVersion
    case derivedData
    case xcarchive
    case hashSuffixed
    case swiftPMArtifact
    case mobileAsset
    case dyldCache
    case huggingFaceRepo
    case deviceBackup
    /// A project's `build` folder, named after the project; relies on `RuleCondition.buildFolder`.
    case buildArtefacts

    func name(for path: String, context: NamingContext) -> ItemName {
        let folder = path.lastPathComponent
        switch self {
        case .fixed, .folderName, .appBundle, .bundleIdentifier, .appContainer, .groupContainer, .hashSuffixed:
            return identifierName(folder: folder, path: path, context: context)
        case .simulatorRuntimeAsset, .simulatorRuntimeBundle, .simulatorDevice, .deviceSupportFolder,
             .deviceSupportVersion, .derivedData, .xcarchive:
            return xcodeName(folder: folder, path: path, context: context)
        case .swiftPMArtifact, .mobileAsset, .dyldCache, .huggingFaceRepo, .deviceBackup, .buildArtefacts:
            return systemName(folder: folder, path: path, context: context)
        }
    }

    // MARK: - Case groups

    private func identifierName(folder: String, path: String, context: NamingContext) -> ItemName {
        switch self {
        case let .fixed(title):
            return ItemName(title: title)
        case .folderName:
            return ItemName(title: folder)
        case .appBundle:
            return Self.appBundleName(path: path)
        case .bundleIdentifier:
            return Self.bundleIdentifierName(folder, context: context)
        case .appContainer:
            let metadataPath = path.appendingPathComponent(".com.apple.containermanagerd.metadata.plist")
            let metadata = NSDictionary(contentsOfFile: metadataPath)
            return Self.bundleIdentifierName(metadata?["MCMMetadataIdentifier"] as? String ?? folder, context: context)
        case .groupContainer:
            return Self.bundleIdentifierName(Self.strippingGroupPrefix(folder), context: context)
        case .hashSuffixed:
            return ItemName(title: folder.replacing(/-[0-9a-f]{8}$/, with: ""), subtitle: nil)
        case .simulatorRuntimeAsset, .simulatorRuntimeBundle, .simulatorDevice, .deviceSupportFolder,
             .deviceSupportVersion, .derivedData, .xcarchive, .swiftPMArtifact, .mobileAsset, .dyldCache,
             .huggingFaceRepo, .deviceBackup, .buildArtefacts:
            preconditionFailure("name(for:context:) routes this case elsewhere")
        }
    }

    private func xcodeName(folder: String, path: String, context: NamingContext) -> ItemName {
        switch self {
        case .simulatorRuntimeAsset:
            return Self.simulatorRuntimeAssetName(path: path, context: context)
        case .simulatorRuntimeBundle:
            let runtime = context.runtime(containing: path)
            return ItemName(title: runtime?.title ?? folder, subtitle: runtime?.lastUsed)
        case .simulatorDevice:
            return Self.simulatorDeviceName(path: path, context: context)
        case .deviceSupportFolder:
            return ItemName(title: folder.replacingOccurrences(of: "DeviceSupport", with: "device support"))
        case .deviceSupportVersion:
            return Self.deviceSupportVersionName(folder)
        case .derivedData:
            return Self.derivedDataName(path: path)
        case .xcarchive:
            return Self.archiveName(path: path)
        case .fixed, .folderName, .appBundle, .bundleIdentifier, .appContainer, .groupContainer, .hashSuffixed,
             .swiftPMArtifact, .mobileAsset, .dyldCache, .huggingFaceRepo, .deviceBackup, .buildArtefacts:
            preconditionFailure("name(for:context:) routes this case elsewhere")
        }
    }

    private func systemName(folder: String, path: String, context: NamingContext) -> ItemName {
        switch self {
        case .swiftPMArtifact:
            return Self.swiftPMArtifactName(folder)
        case .mobileAsset:
            return Self.mobileAssetName(folder)
        case .dyldCache:
            let isCurrent = folder == context.osBuild
            return ItemName(
                title: "For macOS build \(folder)",
                flags: isCurrent ? [] : ["Built for a macOS version that is no longer running"]
            )
        case .huggingFaceRepo:
            return Self.huggingFaceName(folder)
        case .deviceBackup:
            let info = NSDictionary(contentsOfFile: path.appendingPathComponent("Info.plist"))
            let device = info?["Device Name"] as? String ?? folder
            let date = (info?["Last Backup Date"] as? Date)?.formatted(date: .abbreviated, time: .omitted)
            return ItemName(title: device, subtitle: date.map { "Backed up \($0)" })
        case .buildArtefacts:
            return Self.buildArtefactsName(path: path, context: context)
        case .fixed, .folderName, .appBundle, .bundleIdentifier, .appContainer, .groupContainer, .hashSuffixed,
             .simulatorRuntimeAsset, .simulatorRuntimeBundle, .simulatorDevice, .deviceSupportFolder,
             .deviceSupportVersion, .derivedData, .xcarchive:
            preconditionFailure("name(for:context:) routes this case elsewhere")
        }
    }

    // MARK: - Apps & bundle identifiers

    private static func appBundleName(path: String) -> ItemName {
        let info = AppBundleInfo(path: path)
        var title = [info.name, info.version].compactMap(\.self).joined(separator: " ")
        let isBeta = path.lastPathComponent.localizedCaseInsensitiveContains("beta")
        if isBeta, !title.localizedCaseInsensitiveContains("beta") {
            title += " beta"
        }
        return ItemName(title: title)
    }

    static func bundleIdentifierName(_ identifier: String, context: NamingContext) -> ItemName {
        let components = identifier.split(separator: ".").map(String.init)
        guard components.count >= 2 else { return ItemName(title: identifier) }

        for length in stride(from: components.count, through: 2, by: -1) {
            let candidate = components.prefix(length).joined(separator: ".")
            guard let appName = context.appName(forBundleIdentifier: candidate) else { continue }
            let suffix = components.dropFirst(length).joined(separator: ".")
            return ItemName(title: suffix.isEmpty ? appName : "\(appName) (\(suffix))")
        }
        return ItemName(title: identifier)
    }

    private static func strippingGroupPrefix(_ folder: String) -> String {
        if folder.hasPrefix("group.") {
            return String(folder.dropFirst("group.".count))
        }
        return folder.replacing(/^[A-Z0-9]{10}\./, with: "")
    }

    // MARK: - Simulators & Xcode

    private static func simulatorRuntimeAssetName(path: String, context: NamingContext) -> ItemName {
        let info = NSDictionary(contentsOfFile: path.appendingPathComponent("Info.plist"))
        let properties = info?["MobileAssetProperties"] as? [String: Any]
        let platform = path.deletingLastPathComponent.lastPathComponent
            .replacing("com_apple_MobileAsset_", with: "")
            .replacing("SimulatorRuntime", with: "")
            .replacing("xrOS", with: "visionOS")
        guard let version = properties?["SimulatorVersion"] as? String else {
            return ItemName(title: "\(platform) simulator runtime")
        }

        var name = ItemName(title: "\(platform) \(version)")
        if let build = properties?["Build"] as? String {
            name.title += " (\(build))"
        }
        if let runtimes = context.simulatorRuntimes {
            if let runtime = context.runtime(containing: path) {
                name.subtitle = runtime.lastUsed
            } else if !runtimes.isEmpty {
                name.flags.append(
                    "Not registered with CoreSimulator (`simctl runtime list`), so simulators can't use it"
                )
            }
        }
        return name
    }

    private static func simulatorDeviceName(path: String, context: NamingContext) -> ItemName {
        let udid = path.lastPathComponent
        let device = NSDictionary(contentsOfFile: path.appendingPathComponent("device.plist"))
        guard let deviceName = device?["name"] as? String else { return ItemName(title: udid) }

        let runtime = (device?["runtime"] as? String)
            .map { $0.replacing("com.apple.CoreSimulator.SimRuntime.", with: "") }
            .map(Self.humaniseRuntimeIdentifier)
        var name = ItemName(title: [deviceName, runtime].compactMap(\.self).joined(separator: " · "))
        if context.unavailableSimulatorUDIDs.contains(udid) {
            name.flags.append("Unavailable: its runtime is no longer installed")
        }
        return name
    }

    /// `iOS-27-0` → `iOS 27.0`
    private static func humaniseRuntimeIdentifier(_ identifier: String) -> String {
        let parts = identifier.split(separator: "-")
        guard let platform = parts.first, parts.count > 1 else { return identifier }
        return "\(platform) \(parts.dropFirst().joined(separator: "."))"
    }

    /// `iPhone18,1 27.0 (24A437)` → `27.0 (24A437)`, subtitled with the device model.
    private static func deviceSupportVersionName(_ folder: String) -> ItemName {
        guard let match = folder.wholeMatch(of: /(\S+,\S+) (.+)/) else { return ItemName(title: folder) }
        return ItemName(title: String(match.2), subtitle: String(match.1))
    }

    private static let derivedDataFolderNames = [
        "ModuleCache.noindex": "Clang module cache",
        "SDKExplicitPrecompiledModules": "Precompiled SDK modules",
        "CompilationCache.noindex": "Compilation cache"
    ]

    private static func derivedDataName(path: String) -> ItemName {
        let folder = path.lastPathComponent
        let info = NSDictionary(contentsOfFile: path.appendingPathComponent("info.plist"))
        guard let workspace = info?["WorkspacePath"] as? String else {
            return ItemName(title: derivedDataFolderNames[folder] ?? folder.replacing(/-[a-z]{28}$/, with: ""))
        }

        var name = ItemName(
            title: (workspace.lastPathComponent as NSString).deletingPathExtension,
            subtitle: workspace.abbreviatingWithTilde
        )
        if !FileManager.default.fileExists(atPath: workspace) {
            name.flags.append("Project no longer exists at this location")
        }
        return name
    }

    private static func archiveName(path: String) -> ItemName {
        let info = NSDictionary(contentsOfFile: path.appendingPathComponent("Info.plist"))
        let properties = info?["ApplicationProperties"] as? [String: Any]
        let appName = info?["Name"] as? String ?? (path.lastPathComponent as NSString).deletingPathExtension
        let version = properties?["CFBundleShortVersionString"] as? String
        let build = (properties?["CFBundleVersion"] as? String).map { "(\($0))" }
        let date = (info?["CreationDate"] as? Date)?.formatted(date: .abbreviated, time: .shortened)
        return ItemName(title: [appName, version, build].compactMap(\.self).joined(separator: " "), subtitle: date)
    }

    /// `https___dl_google_com_firebase_ios_appads_2_3_0_GoogleAdsOnDeviceConversion_zip`
    /// → `GoogleAdsOnDeviceConversion 2.3.0`
    private static func swiftPMArtifactName(_ folder: String) -> ItemName {
        guard folder.hasPrefix("https___") || folder.hasPrefix("http___") else { return ItemName(title: folder) }

        let tokens = folder.split(separator: "_")
            .filter { !["zip", "xcframework", "artifactbundle"].contains($0.lowercased()) }
        guard let nameIndex = tokens.lastIndex(where: { $0.first?.isLetter == true }) else {
            return ItemName(title: folder)
        }
        let version = tokens[..<nameIndex].reversed().prefix { $0.allSatisfy(\.isNumber) }.reversed()
        let title = version.isEmpty
            ? String(tokens[nameIndex])
            : "\(tokens[nameIndex]) \(version.joined(separator: "."))"
        return ItemName(title: title)
    }

}

nonisolated extension Namer {
    // MARK: - System & AI

    private static let knownMobileAssets: [String: String] = [
        "iOSSimulatorRuntime": "iOS simulator runtimes",
        "watchOSSimulatorRuntime": "watchOS simulator runtimes",
        "tvOSSimulatorRuntime": "tvOS simulator runtimes",
        "xrOSSimulatorRuntime": "visionOS simulator runtimes",
        "AppleDeveloperDocumentation": "Xcode developer documentation",
        "MetalToolchain": "Metal toolchain",
        "MacSoftwareUpdate": "Downloaded macOS updates",
        "UAF_Siri_Understanding": "Siri language understanding",
        "UAF_Siri_TextToSpeech": "Siri voices",
        "UAF_LinguisticData": "Language & dictionary data",
        "UAF_Speech_AutomaticSpeechRecognition": "Speech recognition (dictation)",
        "UAF_Photos_SpatialPhotosRelive": "Photos spatial scenes",
        "UAF_Translation_Assets": "Translation languages",
        "TTSAXResourceModelAssets": "Accessibility voices",
        "VoiceTriggerAssetsASMac": "“Hey Siri” voice trigger"
    ]

    private static func mobileAssetName(_ folder: String) -> ItemName {
        let key = folder.replacing("com_apple_MobileAsset_", with: "")
        if let known = knownMobileAssets[key] {
            return ItemName(title: known)
        }
        let words = key.replacing("UAF_", with: "")
            .replacing(/([a-z])([A-Z])/) { "\($0.1) \($0.2)" }
            .replacing("_", with: " ")
        return ItemName(title: words)
    }

    /// `models--mistralai--Mistral-7B-v0.1` → `mistralai/Mistral-7B-v0.1`
    private static func huggingFaceName(_ folder: String) -> ItemName {
        let parts = folder.components(separatedBy: "--")
        guard parts.count >= 2 else { return ItemName(title: folder) }
        let kind = parts[0].hasSuffix("s") ? String(parts[0].dropLast()) : parts[0]
        return ItemName(title: parts.dropFirst().joined(separator: "/"), subtitle: kind)
    }
}
