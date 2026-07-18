//
//  EmulatorViewModel.swift
//  romm
//
//  Created by Ilyas Hallak on 11.12.25.
//

import Foundation
import Observation
import WebKit

@Observable
@MainActor
class EmulatorViewModel {
    // State
    var isLoading: Bool = true
    var showControls: Bool = false
    var errorMessage: String?
    var emulatorURL: URL?

    // Dependencies
    private let rom: Rom
    private let launchSource: GameLaunchSource?
    private let tokenProvider: PTokenProvider
    private let serverVersionProvider: () -> String?
    private let logger = Logger.viewModel

    init(
        rom: Rom,
        launchSource: GameLaunchSource?,
        tokenProvider: PTokenProvider = TokenProvider(),
        serverVersionProvider: @escaping () -> String? = {
            UserDefaults.standard.string(forKey: "heartbeat.lastKnownServerVersion")
        }
    ) {
        self.rom = rom
        self.launchSource = launchSource
        self.tokenProvider = tokenProvider
        self.serverVersionProvider = serverVersionProvider
    }

    func startEmulator() {
        logger.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        logger.info("🎮 Starting emulator for ROM: \(rom.name) (ID: \(rom.id))")
        logger.info("Platform: \(rom.platformSlug ?? "unknown")")

        guard let serverURLString = tokenProvider.getServerURL() else {
            logger.error("❌ No server configured")
            errorMessage = "No server configured. Please set up your ROMM server in Settings."
            isLoading = false
            return
        }
        logger.info("✅ Server URL: \(serverURLString)")

        let url: URL
        do {
            url = try RomMWebLaunchURLAdapter.makeURL(
                serverURL: serverURLString,
                romID: rom.id,
                source: launchSource,
                serverVersion: serverVersionProvider()
            )
        } catch {
            logger.error("❌ Failed to create emulator URL: \(error)")
            errorMessage = error.localizedDescription
            isLoading = false
            return
        }

        emulatorURL = url
        logger.info("✅ Emulator URL: \(url.absoluteString)")
        logger.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }

    enum RomMWebLaunchURLAdapter {
        enum AdapterError: LocalizedError {
            case selectedSourceIsLocalOnly
            case unsupportedServerVersion(String?)
            case invalidServerURL

            var errorDescription: String? {
                switch self {
                case .selectedSourceIsLocalOnly:
                    return "This save is only on this device. Upload it before using it with RomM Web."
                case .unsupportedServerVersion(let version):
                    return "Selected save and state launching in RomM Web requires RomM 5.0.0. Server version: \(version ?? "unknown")."
                case .invalidServerURL:
                    return "Failed to create emulator URL."
                }
            }
        }

        static func makeURL(
            serverURL: String,
            romID: Int,
            source: GameLaunchSource?,
            serverVersion: String?
        ) throws -> URL {
            let cleanServerURL = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let source else {
                guard let url = URL(string: "\(cleanServerURL)/rom/\(romID)/ejs") else {
                    throw AdapterError.invalidServerURL
                }
                return url
            }
            guard let serverID = source.serverID else {
                throw AdapterError.selectedSourceIsLocalOnly
            }
            // This legacy route is verified only for final RomM 5.0.0.
            guard serverVersion == "5.0.0" else {
                throw AdapterError.unsupportedServerVersion(serverVersion)
            }

            guard var components = URLComponents(string: "\(cleanServerURL)/console/rom/\(romID)/play") else {
                throw AdapterError.invalidServerURL
            }
            switch source {
            case .save:
                components.queryItems = [URLQueryItem(name: "save", value: String(serverID))]
            case .state:
                components.queryItems = [URLQueryItem(name: "state", value: String(serverID))]
            }
            guard let url = components.url else {
                throw AdapterError.invalidServerURL
            }
            return url
        }
    }


    func cleanup() {
        logger.info("Cleaning up emulator session for ROM: \(rom.name)")
        // Optional: Send "exit" event to server to save state
        // Or rely on server's auto-save
        // Future: Could call /api/states to ensure state is saved
    }

    func clearError() {
        errorMessage = nil
    }

    func clearCacheAndReload() {
        logger.info("🗑️ Clearing cache and reloading emulator...")

        Task {
            // Clear all website data (cookies, cache, local storage, etc.)
            let dataStore = WKWebsiteDataStore.default()
            let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()

            await dataStore.removeData(ofTypes: dataTypes, modifiedSince: .distantPast)
            logger.info("✅ Cache cleared")

            // Reload emulator
            isLoading = true
            errorMessage = nil

            // Re-sync cookies from HTTPCookieStorage
            let sharedCookies = HTTPCookieStorage.shared.cookies ?? []
            logger.info("🍪 Re-syncing \(sharedCookies.count) cookies after cache clear")
            for cookie in sharedCookies {
                await dataStore.httpCookieStore.setCookie(cookie)
            }

            // Trigger reload by resetting and setting URL again
            let currentURL = emulatorURL
            emulatorURL = nil
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            emulatorURL = currentURL

            logger.info("✅ Emulator reloading with fresh cache")
        }
    }
}
