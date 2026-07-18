import Foundation
import Testing
@testable import romm

struct RomMWebLaunchURLAdapterTests {
    @Test func normalLaunchUsesCurrentRoute() throws {
        let url = try EmulatorViewModel.RomMWebLaunchURLAdapter.makeURL(
            serverURL: "https://romm.example/",
            romID: 42,
            source: nil,
            serverVersion: nil
        )
        #expect(url.absoluteString == "https://romm.example/rom/42/ejs")
    }

    @Test func romMFiveSaveUsesConsoleRoute() throws {
        let source = GameLaunchSource.save(serverID: 7, fileName: "game.srm", updatedAt: nil)
        let url = try EmulatorViewModel.RomMWebLaunchURLAdapter.makeURL(
            serverURL: "https://romm.example",
            romID: 42,
            source: source,
            serverVersion: "5.0.0"
        )
        #expect(url.absoluteString == "https://romm.example/console/rom/42/play?save=7")
    }

    @Test func romMFiveStateUsesOnlyStateQuery() throws {
        let source = GameLaunchSource.state(serverID: 9, slot: 2, fileName: "state.state", updatedAt: nil, emulator: nil)
        let url = try EmulatorViewModel.RomMWebLaunchURLAdapter.makeURL(
            serverURL: "https://romm.example",
            romID: 42,
            source: source,
            serverVersion: "5.0.0"
        )
        #expect(url.absoluteString == "https://romm.example/console/rom/42/play?state=9")
        #expect(!url.absoluteString.contains("save="))
    }

    @Test func selectedSourceRejectsUnsupportedVersion() {
        let source = GameLaunchSource.save(serverID: 7, fileName: "game.srm", updatedAt: nil)
        #expect(throws: EmulatorViewModel.RomMWebLaunchURLAdapter.AdapterError.self) {
            try EmulatorViewModel.RomMWebLaunchURLAdapter.makeURL(
                serverURL: "https://romm.example",
                romID: 42,
                source: source,
                serverVersion: "4.9.0"
            )
        }
    }
}
