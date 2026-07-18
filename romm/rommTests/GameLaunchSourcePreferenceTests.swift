import Foundation
import Testing
@testable import romm

struct GameLaunchSourcePreferenceTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    }

    @Test func persistsOneSourcePerRom() {
        let defaults = makeDefaults()
        let store = UserDefaultsGameLaunchSourcePreferenceStore(userDefaults: defaults)
        let source = GameLaunchSource.state(
            serverID: 42,
            slot: 3,
            fileName: "slot3.state",
            updatedAt: Date(timeIntervalSince1970: 100),
            emulator: "delta-ios"
        )

        store.setSource(source, for: 7)

        let reloaded = UserDefaultsGameLaunchSourcePreferenceStore(userDefaults: defaults)
        #expect(reloaded.source(for: 7) == source)
    }

    @Test func replacingStateWithSaveIsMutuallyExclusive() {
        let store = UserDefaultsGameLaunchSourcePreferenceStore(userDefaults: makeDefaults())
        store.setSource(.state(serverID: 1, slot: 1, fileName: "one.state", updatedAt: nil, emulator: nil), for: 9)
        store.setSource(.save(serverID: 2, fileName: "game.sav", updatedAt: nil), for: 9)

        #expect(store.source(for: 9) == .save(serverID: 2, fileName: "game.sav", updatedAt: nil))
    }

    @Test func clearReturnsToNormalLaunch() {
        let store = UserDefaultsGameLaunchSourcePreferenceStore(userDefaults: makeDefaults())
        store.setSource(.save(serverID: nil, fileName: "battery.sav", updatedAt: nil), for: 12)

        store.setSource(nil, for: 12)

        #expect(store.source(for: 12) == nil)
    }
}
