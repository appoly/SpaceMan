import SwiftUI

nonisolated enum StorageCategory: String, CaseIterable, Sendable {
    case appleDevelopment
    case androidDevelopment
    case aiTools
    case developerTools
    case applications
    case appData
    case browsers
    case caches
    case userFiles
    case macOS
    case other

    var title: String {
        switch self {
        case .appleDevelopment: "iOS & Apple development"
        case .androidDevelopment: "Android development"
        case .aiTools: "AI models & tools"
        case .developerTools: "Other developer tools"
        case .applications: "Applications"
        case .appData: "App data"
        case .browsers: "Web browsers"
        case .caches: "Caches & temporary files"
        case .userFiles: "Your files"
        case .macOS: "macOS"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .appleDevelopment: "hammer"
        case .androidDevelopment: "smartphone"
        case .aiTools: "sparkles"
        case .developerTools: "terminal"
        case .applications: "square.grid.2x2"
        case .appData: "tray.full"
        case .browsers: "globe"
        case .caches: "arrow.clockwise.circle"
        case .userFiles: "person.crop.square"
        case .macOS: "apple.logo"
        case .other: "questionmark.folder"
        }
    }

    var colour: Color {
        switch self {
        case .appleDevelopment: .blue
        case .androidDevelopment: .green
        case .aiTools: .purple
        case .developerTools: .teal
        case .applications: .orange
        case .appData: .yellow
        case .browsers: .cyan
        case .caches: .pink
        case .userFiles: .indigo
        case .macOS: .gray
        case .other: .brown
        }
    }
}
