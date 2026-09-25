import CoreServices
import Foundation
import Synchronization

nonisolated struct SimulatorRuntime: Sendable, Decodable {
    let platformIdentifier: String?
    let version: String
    let build: String
    let sizeBytes: Int64?
    let path: String?
    let lastUsedAt: String?

    var title: String {
        "\(platformName) \(version) (\(build))"
    }

    private var platformName: String {
        switch platformIdentifier {
        case "com.apple.platform.iphonesimulator": "iOS"
        case "com.apple.platform.watchsimulator": "watchOS"
        case "com.apple.platform.appletvsimulator": "tvOS"
        case "com.apple.platform.xrsimulator": "visionOS"
        default: platformIdentifier?.split(separator: ".").last.map(String.init) ?? "Simulator"
        }
    }

    var lastUsed: String? {
        guard let lastUsedAt, let date = try? Date(lastUsedAt, strategy: .iso8601) else { return nil }
        return "Last used \(date.formatted(date: .abbreviated, time: .omitted))"
    }
}

/// Machine state the namers consult: what `simctl` knows about, the running OS build, and a bundle ID → app name cache.
nonisolated final class NamingContext: Sendable {
    let home: String
    let osBuild: String
    let simulatorRuntimes: [SimulatorRuntime]?
    let unavailableSimulatorUDIDs: Set<String>
    private let appNames = Mutex<[String: String?]>([:])

    init(
        home: String, osBuild: String, simulatorRuntimes: [SimulatorRuntime]?, unavailableSimulatorUDIDs: Set<String>
    ) {
        self.home = home
        self.osBuild = osBuild
        self.simulatorRuntimes = simulatorRuntimes
        self.unavailableSimulatorUDIDs = unavailableSimulatorUDIDs
    }

    static func current() async -> NamingContext {
        async let runtimes = Simctl.runtimes()
        async let unavailable = Simctl.unavailableDeviceUDIDs()
        return await NamingContext(
            home: NSHomeDirectory(),
            osBuild: Self.currentOSBuild(),
            simulatorRuntimes: runtimes,
            unavailableSimulatorUDIDs: unavailable
        )
    }

    func runtime(containing path: String) -> SimulatorRuntime? {
        simulatorRuntimes?.first { runtime in
            guard let imagePath = runtime.path else { return false }
            return imagePath == path || imagePath.hasPrefix(path + "/")
        }
    }

    func appName(forBundleIdentifier identifier: String) -> String? {
        if let cached = appNames.withLock({ $0[identifier] }) {
            return cached
        }
        let name = Self.lookUpAppName(forBundleIdentifier: identifier)
        appNames.withLock { $0[identifier] = .some(name) }
        return name
    }

    private static func lookUpAppName(forBundleIdentifier identifier: String) -> String? {
        let handle = LSCopyApplicationURLsForBundleIdentifier(identifier as CFString, nil)?.takeRetainedValue()
        guard let urls = handle as? [URL], let url = urls.first else { return nil }
        return AppBundleInfo(path: url.path).name
    }

    private static func currentOSBuild() -> String {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        var buffer = [UInt8](repeating: 0, count: size)
        sysctlbyname("kern.osversion", &buffer, &size, nil, 0)
        return String(bytes: buffer.prefix { $0 != 0 }, encoding: .utf8) ?? ""
    }
}

nonisolated struct AppBundleInfo {
    let name: String
    let version: String?

    init(path: String) {
        let info = NSDictionary(contentsOfFile: path.appendingPathComponent("Contents/Info.plist"))
        let fileName = (path.lastPathComponent as NSString).deletingPathExtension
        name = info?["CFBundleDisplayName"] as? String ?? info?["CFBundleName"] as? String ?? fileName
        version = info?["CFBundleShortVersionString"] as? String
    }
}

nonisolated enum Simctl {
    static func runtimes() async -> [SimulatorRuntime]? {
        guard let data = await run(["simctl", "runtime", "list", "-j"]) else { return nil }
        return try? Array(JSONDecoder().decode([String: SimulatorRuntime].self, from: data).values)
    }

    static func unavailableDeviceUDIDs() async -> Set<String> {
        guard let data = await run(["simctl", "list", "devices", "-j"]),
              let decoded = try? JSONDecoder().decode(SimctlDevices.self, from: data)
        else { return [] }
        return Set(decoded.devices.values.joined().filter { !$0.isAvailable }.map(\.udid))
    }

    private static func run(_ arguments: [String]) async -> Data? {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/xcrun")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }
}

nonisolated private struct SimctlDevice: Decodable {
    let udid: String
    let isAvailable: Bool
}

nonisolated private struct SimctlDevices: Decodable {
    let devices: [String: [SimctlDevice]]
}
