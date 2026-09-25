import Foundation

enum PrivacySettings {
    case fullDiskAccess
    case appManagement

    var url: URL {
        switch self {
        case .fullDiskAccess: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        case .appManagement: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles")!
        }
    }
}
