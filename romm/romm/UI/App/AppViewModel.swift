//
//  AppViewModel.swift
//  romm
//
//  Created by Ilyas Hallak on 08.08.25.
//

import Combine
import Foundation
import Observation
import os

enum AppState {
    case loading
    case setup
    case authenticated
    case authenticationFailed
}

@Observable
@MainActor
class AppViewModel {
    var appState: AppState = .loading

    private let logger = Logger.viewModel
    private let launchArguments = ProcessInfo.processInfo.arguments

    // Shared data for environment
    let appData = AppData()

    // Use Cases
    private let saveSetupConfigurationUseCase: PSaveSetupConfigurationUseCase
    private let getSetupConfigurationUseCase: PGetSetupConfigurationUseCase
    private let clearSetupConfigurationUseCase: PClearSetupConfigurationUseCase
    private let checkServerVersionUseCase: CheckServerVersionUseCase
    private let clearServerVersionUseCase: ClearServerVersionUseCase
    private let saveServerVersionUseCase: SaveServerVersionUseCase
    private let getHeartbeatUseCase: GetHeartbeatUseCase

    private let factory: PDependencyFactory

    private var cancellables = Set<AnyCancellable>()
    private var isUITesting: Bool { launchArguments.contains("-ui_testing") || launchArguments.contains("-FASTLANE_SNAPSHOT") }
    private var shouldForceSetupForUITests: Bool { launchArguments.contains("-ui_testing_force_setup") }
    private var shouldForceAuthenticatedForUITests: Bool { launchArguments.contains("-ui_testing_force_authenticated") }

    init(factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.factory = factory
        self.saveSetupConfigurationUseCase = factory.makeSaveSetupConfigurationUseCase()
        self.getSetupConfigurationUseCase = factory.makeGetSetupConfigurationUseCase()
        self.clearSetupConfigurationUseCase = factory.makeClearSetupConfigurationUseCase()
        self.checkServerVersionUseCase = factory.makeCheckServerVersionUseCase()
        self.clearServerVersionUseCase = factory.makeClearServerVersionUseCase()
        self.saveServerVersionUseCase = factory.makeSaveServerVersionUseCase()
        self.getHeartbeatUseCase = factory.makeGetHeartbeatUseCase()

        // Listen for restart setup requests
        NotificationCenter.default.addObserver(
            forName: .restartSetupRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleRestartSetupRequest()
            }
        }

        // Listen for session expiration (401 errors during usage)
        NotificationCenter.default.addObserver(
            forName: .sessionExpired,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let expiration = notification.object as? RommSessionExpiration else {
                return
            }
            Task { @MainActor in
                RommImageSessionManager.shared.performIfCurrentExpiration(
                    expiration
                ) {
                    self?.handleSessionExpiration()
                }
            }
        }
    }

    // MARK: - Public Methods

    func checkInitialState() async {
        logger.debug("Checking initial state...")

        if shouldForceSetupForUITests {
            resetAuthenticationState()
            appData.updateConfiguration(nil)
            appState = .setup
            return
        }

        if shouldForceAuthenticatedForUITests {
            seedUITestAuthenticatedState()
            appState = .authenticated
            return
        }

        let config = try? getSetupConfigurationUseCase.execute()

        if let config {
            let setupRepository = SetupRepository()
            let authMethod = setupRepository.getAuthMethod()
            let hasAuth = StoredAuthenticationPolicy.isAuthenticated(
                configuration: config,
                authMethod: authMethod,
                clientToken: ClientTokenAuthService().getToken()
            )

            if hasAuth {
                logger.info("Authentication state: \(appData.isAuthenticated) (method: \(authMethod.displayName))")
                updateAppConfig(config)
                appState = .authenticated
            } else {
                logger.info("Setup not complete, showing setup")
                appState = .setup
            }
        } else {
            logger.info("No configuration found, showing setup")
            appState = .setup
        }
    }

    // MARK: - Setup Methods

    func saveConfiguration(serverURL: String, username: String, password: String) async {
        logger.debug("Save configuration requested")
        appState = .loading
        guard !serverURL.isEmpty, !username.isEmpty, !password.isEmpty else {
            logger.warning("Missing required fields")
            appData.updateError("Please fill in all required fields")
            return
        }

        appData.updateLoading(true)
        appData.updateError(nil)

        do {
            logger.debug("Calling save setup configuration use case...")
            let setupConfig = try await saveSetupConfigurationUseCase.execute(
                serverURL: serverURL,
                username: username,
                password: password,
                allowIncompatibleVersionLogin: true
            )

            updateAppConfig(setupConfig)
            logger.info("Setup configuration saved successfully")
            appData.updateLoading(false)
            appState = .authenticated
        } catch {
            logger.error("Setup configuration failed: \(error)")
            appData.updateLoading(false)
            appData.updateError(error.localizedDescription)
            appState = .setup
        }
    }

    func restartSetup() {
        logger.debug("Restarting setup...")

        do {
            try clearSetupConfigurationUseCase.execute()
            resetAuthenticationState()
            clearServerVersionUseCase.execute()
            appData.updateConfiguration(nil)
            appState = .loading
        } catch {
            logger.error("Failed to restart setup: \(error)")
            appData.updateError(error.localizedDescription)
        }
    }

    private func updateAppConfig(_ config: SetupConfiguration) {
        appData.updateConfiguration(
            .init(
                serverURL: config.serverURL, username: config.username, password: "",
                token: config.token, refreshToken: config.refreshToken))
    }

    private func resetAuthenticationState() {
        logger.debug("Resetting authentication state")
        appData.updateAuthState(false)
        appData.updateUser(nil)
        appData.updateError(nil)
    }

    func clearError() {
        appData.updateError(nil)
    }

    // MARK: - Private Methods

    private func handleRestartSetupRequest() {
        logger.info("Handling restart setup request from notification")
        resetAuthenticationState()
        clearServerVersionUseCase.execute()
        appData.updateConfiguration(nil)
        appState = .setup
    }

    private func handleSessionExpiration() {
        logger.warning("Session expired - 401 error detected during usage")

        // Only handle session expiration if user was authenticated (not during setup)
        guard appState == .authenticated else {
            logger.debug("Ignoring session expiration - not in authenticated state")
            return
        }

        // Clear configuration and redirect to setup
        do {
            try clearSetupConfigurationUseCase.execute()
            resetAuthenticationState()
            clearServerVersionUseCase.execute()
            appData.updateConfiguration(nil)
            appData.updateError("Your session has expired. Please login again.")
            appState = .setup
            logger.info("User logged out due to session expiration")
        } catch {
            logger.error("Failed to clear configuration on session expiration: \(error)")
            appData.updateError("Session expired - please restart the app")
        }
    }

    // MARK: - Server Version Check

    /// Check server version on app foreground. Handles errors and logs out if needed.
    func checkServerVersionOnForeground() async {
        if isUITesting {
            logger.debug("Skipping version check in UI testing mode")
            return
        }

        // Only check if authenticated
        guard appState == .authenticated else {
            logger.debug("Skipping version check - not authenticated")
            return
        }

        // Check throttle via use case
        if checkServerVersionUseCase.shouldThrottle() {
            logger.debug("Skipping version check - throttled")
            return
        }

        logger.info("Checking server version on foreground...")

        // Get current configuration to check allowIncompatibleVersionLogin flag
        let config = try? getSetupConfigurationUseCase.execute()
        let allowIncompatibleVersion = config?.allowIncompatibleVersionLogin ?? false

        do {
            _ = try await checkServerVersionUseCase.execute(allowIncompatibleVersion: allowIncompatibleVersion)
            logger.info("Server version check passed")
        } catch let error as HeartbeatError {
            handleHeartbeatError(error, allowIncompatibleVersion: allowIncompatibleVersion)
        } catch {
            // Network errors should not trigger logout
            logger.warning("Version check failed (network error): \(error.localizedDescription)")
        }
    }

    /// Handle HeartbeatError by logging out and showing appropriate message
    private func handleHeartbeatError(_ error: HeartbeatError, allowIncompatibleVersion: Bool) {
        logger.warning("Heartbeat error: \(error.localizedDescription)")

        // If user allowed incompatible versions and error is serverVersionTooHigh, don't log out
        if allowIncompatibleVersion, case .serverVersionTooHigh = error {
            logger.info("User allowed incompatible version login - not logging out for serverVersionTooHigh")
            return
        }

        do {
            try clearSetupConfigurationUseCase.execute()
            resetAuthenticationState()
            clearServerVersionUseCase.execute()
            appData.updateConfiguration(nil)
            appData.updateError(error.localizedDescription)
            appState = .setup
            logger.info("User logged out due to heartbeat error")
        } catch {
            logger.error("Failed to handle heartbeat error: \(error)")
            appData.updateError("Error - please restart the app")
        }
    }

    // MARK: - Version Check Helpers (for SetupView)

    /// Check if a server version is compatible
    func isVersionCompatible(_ serverVersion: String) -> Bool {
        checkServerVersionUseCase.isVersionCompatible(serverVersion)
    }

    /// Get minimum supported server version
    var minSupportedServerVersion: String {
        checkServerVersionUseCase.minSupportedServerVersion
    }

    /// Get maximum supported server version
    var maxSupportedServerVersion: String {
        checkServerVersionUseCase.maxSupportedServerVersion
    }

    /// Save server version after successful login
    func saveServerVersion(_ version: String) {
        saveServerVersionUseCase.execute(version: version)
    }

    /// Fetch server version from a specific URL (for setup flow before login)
    func fetchServerVersion(from serverURL: String) async throws -> String {
        let heartbeat = try await getHeartbeatUseCase.execute(from: serverURL)
        return heartbeat.version
    }

    private func seedUITestAuthenticatedState() {
        appData.updateAuthState(true)
        appData.updateError(nil)
        appData.updateConfiguration(
            AppConfiguration(
                serverURL: "https://demo.romm.app",
                username: "snapshot-user",
                password: nil,
                token: "snapshot-token",
                refreshToken: nil
            )
        )
        appData.updateUser(
            User(
                id: 1,
                username: "snapshot-user",
                email: "snapshot@example.com",
                role: .admin,
                avatarPath: nil,
                enabled: true
            )
        )
    }
}
