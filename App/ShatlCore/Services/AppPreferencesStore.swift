import Foundation

/// Persists user preferences separately from durable torrent session state.
final class AppPreferencesStore: @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let storageKey = "mamontov.design.shatl.app-preferences"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    func load() -> AppPreferences {
        guard let data = userDefaults.data(forKey: storageKey) else {
            return .defaultValue
        }

        guard let preferences = try? decoder.decode(AppPreferences.self, from: data) else {
            return .defaultValue
        }

        return preferences
    }

    func save(_ preferences: AppPreferences) {
        guard let data = try? encoder.encode(preferences) else {
            return
        }

        userDefaults.set(data, forKey: storageKey)
    }
}
