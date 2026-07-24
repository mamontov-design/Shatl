import UserNotifications

enum MacNotificationAuthorizationRequester {
    @MainActor
    static func requestNativeAuthorization() async -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return false
        }
        #endif

        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }
}
