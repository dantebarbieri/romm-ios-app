//
//  LaunchEmulatorUseCase.swift
//  romm
//
//  Created by Ilyas Hallak on 21.12.24.
//

import Foundation

enum LaunchDecision: Identifiable {
    case web(rom: Rom, source: GameLaunchSource?)
    case native(rom: Rom, gameType: DeltaGameType, source: GameLaunchSource?)
    case libretro(rom: Rom, core: LibretroCore, source: GameLaunchSource?)

    var id: String {
        switch self {
        case .web(let rom, _): return "web-\(rom.id)"
        case .native(let rom, _, _): return "native-\(rom.id)"
        case .libretro(let rom, _, _): return "libretro-\(rom.id)"
        }
    }
}

enum EmulatorLaunchResult {
    case success(LaunchDecision)
    case failure(EmulatorLaunchError)
}

enum EmulatorLaunchError: LocalizedError {
    case noServerConfigured
    case unsupportedPlatform(String)
    case romNotAvailable
    case serverUnreachable
    case incompatibleState(expected: String, actual: String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .noServerConfigured:
            return "No server configured. Please set up your ROMM server in Settings."
        case .unsupportedPlatform(let platform):
            return "Platform '\(platform)' is not supported for emulation."
        case .romNotAvailable:
            return "ROM file is not available. Please download it first or check your server connection."
        case .serverUnreachable:
            return "Cannot reach ROMM server. Please check your connection."
        case .incompatibleState(let expected, let actual):
            return "This state was created by \(actual) and cannot be loaded by \(expected). Choose a compatible engine or another state."
        case .unknown(let message):
            return message
        }
    }
}

protocol PLaunchEmulatorUseCase {
    func execute(rom: Rom) async -> EmulatorLaunchResult
}

final class LaunchEmulatorUseCase: PLaunchEmulatorUseCase {
    private let tokenProvider: PTokenProvider
    private let checkEmulatorSupport: PCheckEmulatorSupportUseCase
    private let enginePreference: PEmulatorEnginePreference
    private let platformSupport: PPlatformEngineSupport
    private let launchSourcePreference: PGameLaunchSourcePreference
    private let logger = Logger.viewModel

    init(
        tokenProvider: PTokenProvider,
        checkEmulatorSupport: PCheckEmulatorSupportUseCase,
        enginePreference: PEmulatorEnginePreference,
        platformSupport: PPlatformEngineSupport,
        launchSourcePreference: PGameLaunchSourcePreference
    ) {
        self.tokenProvider = tokenProvider
        self.checkEmulatorSupport = checkEmulatorSupport
        self.enginePreference = enginePreference
        self.platformSupport = platformSupport
        self.launchSourcePreference = launchSourcePreference
    }

    func execute(rom: Rom) async -> EmulatorLaunchResult {
        print("[LaunchEmulator] execute called for rom id=\(rom.id) name=\(rom.name) platformSlug=\(rom.platformSlug ?? "nil")")
        guard tokenProvider.getServerURL() != nil else {
            print("[LaunchEmulator] FAIL: no server configured")
            return .failure(.noServerConfigured)
        }
        guard let platformSlug = rom.platformSlug else {
            print("[LaunchEmulator] FAIL: platformSlug nil")
            return .failure(.unsupportedPlatform("Unknown"))
        }
        guard checkEmulatorSupport.execute(platformSlug: platformSlug) else {
            print("[LaunchEmulator] FAIL: platform '\(platformSlug)' not supported")
            return .failure(.unsupportedPlatform(platformSlug))
        }

        let supported = platformSupport.supportedEngines(for: platformSlug)
        let pref = enginePreference.current
        print("[LaunchEmulator] platformSlug='\(platformSlug)', preference=\(pref.rawValue), supported=\(supported.map { $0.rawValue })")
        let chosen: EmulatorEngine = {
            switch pref {
            case .web: return supported.contains(.web) ? .web : .native
            case .native: return supported.contains(.native) ? .native : .web
            case .auto: return platformSupport.preferred(for: platformSlug)
            }
        }()
        print("[LaunchEmulator] chosen engine=\(chosen.rawValue)")
        let source = launchSourcePreference.source(for: rom.id)

        switch chosen {
        case .web:
            return .success(.web(rom: rom, source: source))
        case .native:
            if let gameType = PlatformSlugToGameType.map(platformSlug) {
                if let error = incompatibilityError(source: source, expectedEmulator: "delta-ios") {
                    return .failure(error)
                }
                return .success(.native(rom: rom, gameType: gameType, source: source))
            }
            if let core = PlatformSlugToLibretroCore.map(platformSlug) {
                let emulator = "libretro-\(core.dylibName)"
                if let error = incompatibilityError(source: source, expectedEmulator: emulator) {
                    return .failure(error)
                }
                return .success(.libretro(rom: rom, core: core, source: source))
            }
            return .success(.web(rom: rom, source: source))
        case .auto:
            return .success(.web(rom: rom, source: source))
        }
    }

    private func incompatibilityError(
        source: GameLaunchSource?,
        expectedEmulator: String
    ) -> EmulatorLaunchError? {
        guard let actual = source?.stateEmulator, !actual.isEmpty, actual != expectedEmulator else {
            return nil
        }
        return .incompatibleState(expected: expectedEmulator, actual: actual)
    }
}
