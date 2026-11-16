import Foundation

enum AppIdentity {
    /// Used only when the Info.plist value was not substituted. Keep it in sync with
    /// `BUNDLE_ID_PREFIX` in Config/Shared.xcconfig.
    static let fallbackGroupID = "group.com.example.savessorter"

    static var appGroupID: String {
        let raw = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty || trimmed.contains("$(") {
            return fallbackGroupID
        }
        return trimmed
    }

    static var keychainService: String { "savessorter.api-keys" }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.example.savessorter"
    }
}

enum AppDefaults {
    static var suite: UserDefaults {
        UserDefaults(suiteName: AppIdentity.appGroupID) ?? .standard
    }
}

enum AILog {
    private static let key = "ai.lastError"

    static func record(_ message: String) {
        AppDefaults.suite.set(message, forKey: key)
    }

    static func clear() {
        AppDefaults.suite.removeObject(forKey: key)
    }

    static var last: String? {
        AppDefaults.suite.string(forKey: key)
    }
}
