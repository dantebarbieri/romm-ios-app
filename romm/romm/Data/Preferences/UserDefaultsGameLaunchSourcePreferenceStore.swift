import Foundation

final class UserDefaultsGameLaunchSourcePreferenceStore: PGameLaunchSourcePreference {
    private let key = "emulator.launch.sources"
    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func source(for romID: Int) -> GameLaunchSource? {
        load()[romID]
    }

    func setSource(_ source: GameLaunchSource?, for romID: Int) {
        var sources = load()
        sources[romID] = source
        guard !sources.isEmpty else {
            userDefaults.removeObject(forKey: key)
            return
        }
        guard let data = try? encoder.encode(sources) else { return }
        userDefaults.set(data, forKey: key)
    }

    private func load() -> [Int: GameLaunchSource] {
        guard let data = userDefaults.data(forKey: key),
              let sources = try? decoder.decode([Int: GameLaunchSource].self, from: data) else {
            return [:]
        }
        return sources
    }
}
