import Testing
import Foundation
@testable import romm

private final class StubPreference: PEmulatorEnginePreference {
    var current: EmulatorEngine
    init(_ engine: EmulatorEngine) { self.current = engine }
}

private final class StubSupport: PPlatformEngineSupport {
    var engines: Set<EmulatorEngine> = []
    func supportedEngines(for platformSlug: String) -> Set<EmulatorEngine> { engines }
    func preferred(for platformSlug: String) -> EmulatorEngine {
        engines.contains(.web) ? .web : .native
    }
}

private final class StubTokenProvider: PTokenProvider {
    var serverURL: String? = "https://server"
    func getAuthToken() -> String? { nil }
    func getServerURL() -> String? { serverURL }
    func getUsername() -> String? { nil }
    func getPassword() -> String? { nil }
    func isConfigured() -> Bool { serverURL != nil }
    func getAuthMethod() -> AuthMethod { .classic }
    func getClientToken() -> String? { nil }
    func getClientTokenInfo() -> ClientTokenInfo? { nil }
    func hasScope(_ scope: String) -> Bool { false }
    var availableScopes: [String]? { nil }
}

private final class StubCheckSupport: PCheckEmulatorSupportUseCase {
    var supported = true
    func execute(platformSlug: String) -> Bool { supported }
}

private final class StubLaunchSourcePreference: PGameLaunchSourcePreference {
    var selected: GameLaunchSource?
    func source(for romID: Int) -> GameLaunchSource? { selected }
    func setSource(_ source: GameLaunchSource?, for romID: Int) { selected = source }
}

private func makeRom(slug: String = "gba") -> Rom {
    Rom(id: 1, name: "Test", platformId: 0, urlCover: nil,
        isFavourite: false, hasRetroAchievements: false, isPlayable: true,
        fileName: "Test.gba", platformSlug: slug)
}

struct LaunchEmulatorUseCaseTests {
    @Test func failsWhenNoServer() async {
        let token = StubTokenProvider(); token.serverURL = nil
        let useCase = LaunchEmulatorUseCase(
            tokenProvider: token,
            checkEmulatorSupport: StubCheckSupport(),
            enginePreference: StubPreference(.web),
            platformSupport: StubSupport(),
            launchSourcePreference: StubLaunchSourcePreference()
        )
        let result = await useCase.execute(rom: makeRom())
        if case .failure(.noServerConfigured) = result {} else { Issue.record("expected .noServerConfigured") }
    }

    @Test func webPreferenceReturnsWebDecision() async {
        let support = StubSupport(); support.engines = [.web]
        let useCase = LaunchEmulatorUseCase(
            tokenProvider: StubTokenProvider(),
            checkEmulatorSupport: StubCheckSupport(),
            enginePreference: StubPreference(.web),
            platformSupport: support,
            launchSourcePreference: StubLaunchSourcePreference()
        )
        let result = await useCase.execute(rom: makeRom())
        if case .success(let decision) = result, case .web = decision {} else {
            Issue.record("expected .web decision")
        }
    }

    @Test func deltaPreferenceReturnsDeltaDecisionForGBA() async {
        let support = StubSupport(); support.engines = [.web, .native]
        let useCase = LaunchEmulatorUseCase(
            tokenProvider: StubTokenProvider(),
            checkEmulatorSupport: StubCheckSupport(),
            enginePreference: StubPreference(.native),
            platformSupport: support,
            launchSourcePreference: StubLaunchSourcePreference()
        )
        let result = await useCase.execute(rom: makeRom(slug: "gba"))
        if case .success(let decision) = result,
           case .native(_, let gameType, _) = decision {
            #expect(gameType == .gba)
        } else {
            Issue.record("expected .native(.gba) decision")
        }
    }

    @Test func deltaPreferenceFallsBackToWebWhenUnsupported() async {
        let support = StubSupport(); support.engines = [.web]
        let useCase = LaunchEmulatorUseCase(
            tokenProvider: StubTokenProvider(),
            checkEmulatorSupport: StubCheckSupport(),
            enginePreference: StubPreference(.native),
            platformSupport: support,
            launchSourcePreference: StubLaunchSourcePreference()
        )
        let result = await useCase.execute(rom: makeRom(slug: "psx"))
        if case .success(let decision) = result, case .web = decision {} else {
            Issue.record("expected fallback to .web")
        }
    }

    @Test func rejectsStateCreatedByDifferentNativeEngine() async {
        let support = StubSupport(); support.engines = [.native]
        let launchSource = StubLaunchSourcePreference()
        launchSource.selected = .state(
            serverID: 9,
            slot: 1,
            fileName: "state.state",
            updatedAt: nil,
            emulator: "mgba"
        )
        let useCase = LaunchEmulatorUseCase(
            tokenProvider: StubTokenProvider(),
            checkEmulatorSupport: StubCheckSupport(),
            enginePreference: StubPreference(.native),
            platformSupport: support,
            launchSourcePreference: launchSource
        )

        let result = await useCase.execute(rom: makeRom(slug: "gba"))

        if case .failure(.incompatibleState(expected: "delta-ios", actual: "mgba")) = result {
        } else {
            Issue.record("expected incompatible state failure")
        }
    }
}
