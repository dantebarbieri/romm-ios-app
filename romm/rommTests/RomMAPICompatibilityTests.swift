import Foundation
import Dispatch
import Kingfisher
import Testing
@testable import romm

struct RomMAPICompatibilityTests {

    @Test func platformDecodesRomMFourAspectRatio() throws {
        let platform = try decodePlatform(aspectRatio: "\"4 / 3\"")

        #expect(platform.aspectRatio == "4 / 3")
    }

    @Test func platformDecodesRomMFiveWithoutAspectRatio() throws {
        let platform = try decodePlatform(aspectRatio: nil)

        #expect(platform.aspectRatio == "2 / 3")
    }

    @Test func relativeAssetPathResolvesAgainstConfiguredServer() throws {
        let tokenProvider = MockTokenProvider(serverURL: "https://romm.example/base/")
        let client = RommAPIClient(tokenProvider: tokenProvider)

        let url = try client.buildURL(path: "/api/raw/assets/saves/legacy.sav")

        #expect(url.absoluteString == "https://romm.example/base/api/raw/assets/saves/legacy.sav")
    }

    @Test func sameOriginAbsoluteAssetURLIsAccepted() throws {
        let client = RommAPIClient(
            tokenProvider: MockTokenProvider(serverURL: "https://romm.example")
        )

        let url = try client.buildURL(
            path: "https://ROMM.example:443/api/states/7/content?timestamp=1"
        )

        #expect(url.absoluteString == "https://romm.example/api/states/7/content?timestamp=1")
    }

    @Test func crossOriginAbsoluteAssetURLIsRejected() {
        let client = RommAPIClient(
            tokenProvider: MockTokenProvider(serverURL: "https://romm.example")
        )

        expectDisallowedURL {
            try client.buildURL(path: "https://cdn.example/api/states/7/content")
        }
    }

    @Test func unsupportedSchemesAreRejected() {
        let client = RommAPIClient(
            tokenProvider: MockTokenProvider(serverURL: "https://romm.example")
        )

        for reference in [
            "file:///private/save.sav",
            "data:text/plain,save",
            "ftp://romm.example/save.sav"
        ] {
            expectDisallowedURL {
                try client.buildURL(path: reference)
            }
        }
    }

    @Test func malformedAndProtocolRelativeURLsAreRejected() {
        let client = RommAPIClient(
            tokenProvider: MockTokenProvider(serverURL: "https://romm.example")
        )

        for reference in ["https://", "https:missing-authority"] {
            expectInvalidURL {
                try client.buildURL(path: reference)
            }
        }
        expectDisallowedURL {
            try client.buildURL(path: "//other.example/save.sav")
        }
    }

    @Test func absoluteAssetRequiresServerConfiguration() {
        let client = RommAPIClient(tokenProvider: MockTokenProvider())

        expectNoConfiguration {
            try client.buildURL(path: "https://romm.example/api/saves/1/content")
        }
    }

    @Test func malformedConfiguredServerIsRejected() {
        let client = RommAPIClient(
            tokenProvider: MockTokenProvider(serverURL: "https://")
        )

        expectInvalidURL {
            try client.buildURL(path: "/api/saves/1/content")
        }
    }

    @Test func implicitAndExplicitHTTPDefaultPortsShareOrigin() throws {
        let client = RommAPIClient(
            tokenProvider: MockTokenProvider(serverURL: "http://romm.example")
        )

        let url = try client.buildURL(path: "http://romm.example:80/api/saves/1/content")

        #expect(client.isSameOriginAsServer(url))
    }

    @Test func implicitAndExplicitHTTPSDefaultPortsShareOrigin() throws {
        let client = RommAPIClient(
            tokenProvider: MockTokenProvider(serverURL: "https://romm.example:443")
        )

        let url = try client.buildURL(path: "https://romm.example/api/saves/1/content")

        #expect(client.isSameOriginAsServer(url))
    }

    @Test func nondefaultPortMismatchIsRejected() {
        let client = RommAPIClient(
            tokenProvider: MockTokenProvider(serverURL: "https://romm.example:8443")
        )

        expectDisallowedURL {
            try client.buildURL(path: "https://romm.example/api/saves/1/content")
        }
    }

    @Test func schemeMismatchIsRejected() {
        let client = RommAPIClient(
            tokenProvider: MockTokenProvider(serverURL: "https://romm.example")
        )

        expectDisallowedURL {
            try client.buildURL(path: "http://romm.example/api/saves/1/content")
        }
    }

    @Test func rawAssetFilenameIsEncodedWithoutChangingQuery() throws {
        let client = RommAPIClient(
            tokenProvider: MockTokenProvider(serverURL: "https://romm.example/base")
        )

        let url = try client.buildURL(
            path: "/api/raw/assets/saves/My Save #100% 日本%20copy:slot.sav?timestamp=1700&mode=raw%20copy"
        )
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        #expect(
            components?.percentEncodedPath
                == "/base/api/raw/assets/saves/My%20Save%20%23100%25%20%E6%97%A5%E6%9C%AC%20copy%3Aslot.sav"
        )
        #expect(components?.percentEncodedQuery == "timestamp=1700&mode=raw%20copy")
        #expect(components?.fragment == nil)
    }

    @Test func sameOriginAssetUsesAuthentication() throws {
        let tokenProvider = MockTokenProvider(
            serverURL: "https://romm.example",
            username: "user",
            password: "pass"
        )
        let client = RommAPIClient(tokenProvider: tokenProvider)
        let url = try client.buildURL(path: "/api/screenshots/4/content")

        #expect(try client.authorizationHeader(for: url) == "Basic dXNlcjpwYXNz")
    }

    @Test func crossOriginAssetDoesNotReceiveAuthentication() throws {
        let tokenProvider = MockTokenProvider(
            serverURL: "https://romm.example",
            username: "user",
            password: "pass"
        )
        let client = RommAPIClient(tokenProvider: tokenProvider)
        let url = try #require(URL(string: "https://cdn.example/signed/asset"))

        #expect(try client.authorizationHeader(for: url) == nil)
    }

    @Test func relativeImageUsesAuthenticatedRomMPolicy() throws {
        let request = try authenticatedImagePolicy().resolve(
            "/api/screenshots/4/content"
        )

        #expect(request.accessPolicy == .romm)
        #expect(request.usesRommAuthentication)
        #expect(request.usesPrivateNetworkTrust)
        #expect(!request.usesSharedPersistentCache)
    }

    @Test func sameOriginAbsoluteImageUsesAuthenticatedRomMPolicy() throws {
        let request = try authenticatedImagePolicy().resolve(
            "https://romm.example/api/screenshots/4/content"
        )

        #expect(request.accessPolicy == .romm)
        #expect(request.usesRommAuthentication)
        #expect(request.usesPrivateNetworkTrust)
    }

    @Test func externalProviderArtworkUsesPublicPolicy() throws {
        let policy = authenticatedImagePolicy()

        for urlString in [
            "https://images.igdb.com/igdb/image/upload/t_cover_big/example.jpg",
            "http://cdn.steamgriddb.com/grid/example.png"
        ] {
            let request = try policy.resolve(urlString)
            let sessionManager = imageSessionManager()
            let options = KingfisherParsedOptionsInfo(
                request.kingfisherOptions(
                    sessionManager: sessionManager
                )
            )

            #expect(request.accessPolicy == .publicExternal)
            #expect(request.authorizationHeader == nil)
            #expect(!request.usesPrivateNetworkTrust)
            #expect(request.usesSharedPersistentCache)
            #expect(options.downloader == nil)
            #expect(!options.cacheMemoryOnly)
            #expect(!options.forceRefresh)
            #expect(options.cacheOriginalImage)
            #expect(options.requestModifier == nil)
            #expect(sessionManager.currentSession == nil)
        }
    }

    @Test func crossOriginPrivateImageUsesStandardTLSWithoutAuth() throws {
        let request = try authenticatedImagePolicy().resolve(
            "https://192.168.1.21/provider/cover.jpg"
        )
        let sessionManager = imageSessionManager()
        let options = KingfisherParsedOptionsInfo(
            request.kingfisherOptions(
                sessionManager: sessionManager
            )
        )

        #expect(request.accessPolicy == .publicExternal)
        #expect(request.authorizationHeader == nil)
        #expect(!request.usesPrivateNetworkTrust)
        #expect(options.downloader == nil)
        #expect(options.requestModifier == nil)
        #expect(sessionManager.currentSession == nil)
    }

    @Test func privateImageRedirectsRemainSameOrigin() throws {
        let manager = imageSessionManager()
        let session = manager.session(for: imageAuthScope("account-a"))
        let initiatingURL = try #require(
            URL(string: "https://romm.example/api/screenshots/4/content")
        )
        let origin = try #require(RommImageRequestOrigin(url: initiatingURL))
        let handler = RommImageRedirectHandler(
            origin: origin,
            authorizationHeader: "TestAuthorization",
            session: session
        )
        let sameOriginURL = try #require(
            URL(string: "https://romm.example:443/api/screenshots/4/content")
        )
        let crossOriginURL = try #require(
            URL(string: "https://cdn.example/screenshots/4.jpg")
        )

        let sameOriginRequest = try #require(
            handler.redirectedRequest(URLRequest(url: sameOriginURL))
        )

        #expect(
            sameOriginRequest.value(forHTTPHeaderField: "Authorization")
                == "TestAuthorization"
        )
        #expect(handler.redirectedRequest(URLRequest(url: crossOriginURL)) == nil)
    }

    @Test func invalidatedPrivateImageRedirectCannotRetainOldCredentials() throws {
        let tokenProvider = MockTokenProvider(
            serverURL: "https://old-romm.example",
            username: "user",
            password: "old-password"
        )
        let client = RommAPIClient(tokenProvider: tokenProvider)
        let manager = RommImageSessionManager(apiClient: client)
        let initiatingURL = try #require(
            URL(string: "https://old-romm.example/api/screenshots/4/content")
        )
        let scope = try #require(
            RommImageAuthScope(
                url: initiatingURL,
                authorizationHeader: "OldAuthorization"
            )
        )
        let session = manager.session(for: scope)
        let handler = RommImageRedirectHandler(
            origin: try #require(RommImageRequestOrigin(url: initiatingURL)),
            authorizationHeader: "OldAuthorization",
            session: session
        )
        let oldOriginRedirect = URLRequest(
            url: try #require(URL(string: "https://old-romm.example/redirected"))
        )
        let newOriginRedirect = URLRequest(
            url: try #require(URL(string: "https://new-romm.example/redirected"))
        )

        #expect(handler.redirectedRequest(oldOriginRedirect) != nil)
        #expect(handler.redirectedRequest(newOriginRedirect) == nil)

        tokenProvider.mockServerURL = "https://new-romm.example"
        manager.authenticationScopeDidChange()

        #expect(handler.redirectedRequest(oldOriginRedirect) == nil)
        #expect(handler.redirectedRequest(newOriginRedirect) == nil)
    }

    @Test func unsafeImageURLsAreRejected() {
        let policy = authenticatedImagePolicy()

        for reference in [
            "file:///private/cover.jpg",
            "data:image/png;base64,AAAA",
            "ftp://artwork.example/cover.jpg",
            "//artwork.example/cover.jpg",
            "https://user" + "@artwork.example/cover.jpg",
            "https://"
        ] {
            #expect(throws: APIClientError.self) {
                try policy.resolve(reference)
            }
        }
    }

    @Test func romMImageOptionsCannotReuseSharedAccountCache() throws {
        let request = try authenticatedImagePolicy().resolve(
            "/api/screenshots/4/content"
        )
        let sessionManager = imageSessionManager()
        let options = KingfisherParsedOptionsInfo(
            request.kingfisherOptions(
                sessionManager: sessionManager
            )
        )
        let reusedOptions = KingfisherParsedOptionsInfo(
            request.kingfisherOptions(
                sessionManager: sessionManager
            )
        )
        let session = try #require(sessionManager.currentSession)

        #expect(options.downloader === session.downloader)
        #expect(options.targetCache === session.cache)
        #expect(reusedOptions.downloader === session.downloader)
        #expect(reusedOptions.targetCache === session.cache)
        #expect(options.targetCache !== ImageCache.default)
        #expect(options.cacheMemoryOnly)
        #expect(!options.forceRefresh)
        #expect(!options.cacheOriginalImage)
        #expect(options.requestModifier != nil)
    }

    @Test func privateImageSessionsArePartitionedByAuthenticationScope() {
        let manager = imageSessionManager()
        let firstScope = imageAuthScope("account-a")
        let secondScope = imageAuthScope("account-b")

        let firstSession = manager.session(for: firstScope)
        let reusedSession = manager.session(for: firstScope)
        let secondSession = manager.session(for: secondScope)

        #expect(firstSession === reusedSession)
        #expect(firstSession.downloader === reusedSession.downloader)
        #expect(firstSession.cache === reusedSession.cache)
        #expect(firstSession.downloader !== secondSession.downloader)
        #expect(firstSession.cache !== secondSession.cache)
        #expect(firstSession.isInvalidated)
        #expect(firstSession.downloader.isScopeInvalidated)
        #expect(!secondSession.isInvalidated)
    }

    @Test func stalePrivateImageUnauthorizedResponseCannotExpireNewScope() {
        let counter = NotificationCounter()
        let notificationCenter = NotificationCenter()
        let observer = notificationCenter.addObserver(
            forName: .sessionExpired,
            object: nil,
            queue: nil
        ) { _ in
            counter.increment()
        }
        defer { notificationCenter.removeObserver(observer) }

        let manager = imageSessionManager(notificationCenter: notificationCenter)
        let firstSession = manager.session(for: imageAuthScope("account-a"))
        let secondSession = manager.session(for: imageAuthScope("account-b"))

        _ = firstSession.responseDelegate.isValidStatusCode(
            401,
            for: firstSession.downloader
        )

        #expect(counter.value == 0)
        #expect(manager.currentSession === secondSession)
        #expect(!secondSession.isInvalidated)
    }

    @Test func publicArtworkDoesNotChangePrivateImageSession() throws {
        let manager = imageSessionManager()
        let privateRequest = try authenticatedImagePolicy().resolve(
            "/api/screenshots/4/content"
        )
        _ = privateRequest.kingfisherOptions(sessionManager: manager)
        let privateSession = try #require(manager.currentSession)

        let publicRequest = try authenticatedImagePolicy().resolve(
            "https://images.igdb.com/igdb/image/upload/example.jpg"
        )
        let publicOptions = KingfisherParsedOptionsInfo(
            publicRequest.kingfisherOptions(sessionManager: manager)
        )

        #expect(manager.currentSession === privateSession)
        #expect(!privateSession.isInvalidated)
        #expect(publicOptions.downloader == nil)
        #expect(!publicOptions.cacheMemoryOnly)
    }

    @Test @MainActor func globalKingfisherDefaultsDoNotPersistOriginalImages() {
        _ = KingfisherCacheManager.shared
        let options = KingfisherParsedOptionsInfo(
            KingfisherManager.shared.defaultOptions
        )

        #expect(!options.cacheOriginalImage)
    }

    @Test func authenticationScopeChangeInvalidatesPrivateImageSession() {
        let notificationCenter = NotificationCenter()
        let manager = imageSessionManager(notificationCenter: notificationCenter)
        let session = manager.session(
            for: imageAuthScope("account-a")
        )

        manager.authenticationScopeDidChange()

        #expect(manager.currentSession == nil)
        #expect(session.isInvalidated)
        #expect(session.downloader.isScopeInvalidated)

        let reopenedSession = manager.session(for: imageAuthScope("account-a"))
        #expect(!reopenedSession.isInvalidated)
    }

    @Test func authenticationInvalidationRejectsRetainedPrivateRequests() {
        let notificationCenter = NotificationCenter()
        let manager = imageSessionManager(notificationCenter: notificationCenter)
        let scope = imageAuthScope("account-a")
        let session = manager.session(for: scope)

        manager.reset()
        let rejectedSession = manager.session(for: scope)

        #expect(session.isInvalidated)
        #expect(rejectedSession.downloader.isScopeInvalidated)
        #expect(manager.currentSession == nil)
    }

    @Test func retainedRequestCannotUseChangedCredentials() throws {
        let notificationCenter = NotificationCenter()
        let tokenProvider = MockTokenProvider(
            serverURL: "https://romm.example",
            username: "user",
            password: "first-password"
        )
        let client = RommAPIClient(tokenProvider: tokenProvider)
        let policy = RommImageRequestPolicy(apiClient: client)
        let manager = RommImageSessionManager(
            apiClient: client,
            notificationCenter: notificationCenter
        )
        let retainedRequest = try policy.resolve("/api/screenshots/4/content")
        _ = retainedRequest.kingfisherOptions(sessionManager: manager)

        tokenProvider.mockPassword = "second-password"
        manager.authenticationScopeDidChange()
        let staleOptions = KingfisherParsedOptionsInfo(
            retainedRequest.kingfisherOptions(sessionManager: manager)
        )

        let staleDownloader = try #require(
            staleOptions.downloader as? RommScopedImageDownloader
        )
        #expect(staleDownloader.isScopeInvalidated)
        #expect(manager.currentSession == nil)

        let currentRequest = try policy.resolve("/api/screenshots/4/content")
        _ = currentRequest.kingfisherOptions(sessionManager: manager)
        let currentSession = try #require(manager.currentSession)
        #expect(!currentSession.isInvalidated)
    }

    @Test func privateImageUnauthorizedResponseExpiresAndInvalidatesOnce() {
        let counter = NotificationCounter()
        let notificationCenter = NotificationCenter()
        let observer = notificationCenter.addObserver(
            forName: .sessionExpired,
            object: nil,
            queue: nil
        ) { _ in
            counter.increment()
        }
        defer { notificationCenter.removeObserver(observer) }

        let manager = imageSessionManager(notificationCenter: notificationCenter)
        let session = manager.session(
            for: imageAuthScope("account-a")
        )

        let firstIsValid = session.responseDelegate.isValidStatusCode(
            401,
            for: session.downloader
        )
        let secondIsValid = session.responseDelegate.isValidStatusCode(
            401,
            for: session.downloader
        )

        #expect(!firstIsValid)
        #expect(!secondIsValid)
        #expect(counter.value == 1)
        #expect(manager.currentSession == nil)
        #expect(session.isInvalidated)
        #expect(session.downloader.isScopeInvalidated)

        let retriedSession = manager.session(for: imageAuthScope("account-a"))
        #expect(retriedSession.downloader.isScopeInvalidated)
    }

    @Test func privateImageForbiddenResponseDoesNotExpireSession() {
        let counter = NotificationCounter()
        let notificationCenter = NotificationCenter()
        let observer = notificationCenter.addObserver(
            forName: .sessionExpired,
            object: nil,
            queue: nil
        ) { _ in
            counter.increment()
        }
        defer { notificationCenter.removeObserver(observer) }

        let manager = imageSessionManager(notificationCenter: notificationCenter)
        let session = manager.session(
            for: imageAuthScope("account-a")
        )

        let isValid = session.responseDelegate.isValidStatusCode(
            403,
            for: session.downloader
        )

        #expect(!isValid)
        #expect(APIResponseStatusPolicy.classify(403) == .forbidden)
        #expect(counter.value == 0)
        #expect(manager.currentSession === session)
        #expect(!session.isInvalidated)
    }

    @Test func unauthorizedResponseExpiresSession() async throws {
        let counter = NotificationCounter()
        let notificationCenter = NotificationCenter()
        let observer = notificationCenter.addObserver(
            forName: .sessionExpired,
            object: nil,
            queue: nil
        ) { _ in
            counter.increment()
        }
        defer { notificationCenter.removeObserver(observer) }

        let client = statusResponseClient(notificationCenter: notificationCenter)
        do {
            _ = try await client.get("status/401")
            Issue.record("Expected authentication failure")
        } catch APIClientError.authenticationRequired {
        } catch {
            Issue.record("Expected authentication failure, got \(error)")
        }
        do {
            _ = try await client.get("status/401")
            Issue.record("Expected repeated authentication failure")
        } catch APIClientError.authenticationRequired {
        } catch {
            Issue.record("Expected repeated authentication failure, got \(error)")
        }

        #expect(counter.value == 1)
        #expect(APIResponseStatusPolicy.classify(401).shouldExpireSession)
    }

    @Test func concurrentSameScopeUnauthorizedResponsesExpireOnce() {
        let manager = imageSessionManager()
        let firstRequest = manager.captureRequestScope(isAuthenticated: true)
        let secondRequest = manager.captureRequestScope(isAuthenticated: true)
        let counter = NotificationCounter()

        let firstExpired = manager.expireSessionIfCurrent(firstRequest) { _ in
            counter.increment()
        }
        let secondExpired = manager.expireSessionIfCurrent(secondRequest) { _ in
            counter.increment()
        }

        #expect(firstExpired)
        #expect(!secondExpired)
        #expect(counter.value == 1)
    }

    @Test func logoutLoginInvalidatesInFlightRequestScope() {
        let manager = imageSessionManager()
        let oldRequest = manager.captureRequestScope(isAuthenticated: true)
        manager.reset()
        manager.authenticationScopeDidChange()
        var notified = false

        let expired = manager.expireSessionIfCurrent(oldRequest) { _ in
            notified = true
        }

        #expect(!expired)
        #expect(!notified)
    }

    @Test func tokenRotationInvalidatesInFlightRequestScope() {
        let manager = imageSessionManager()
        let oldRequest = manager.captureRequestScope(isAuthenticated: true)
        manager.authenticationScopeDidChange()
        var notified = false

        let expired = manager.expireSessionIfCurrent(oldRequest) { _ in
            notified = true
        }

        #expect(!expired)
        #expect(!notified)
    }

    @Test func authenticatedRequestAcquisitionIsBlockedDuringMutation() {
        let manager = imageSessionManager()
        manager.reset()
        let generation = manager.captureRequestGeneration()

        let requestScope = manager.captureRequestScope(
            ifCurrent: generation,
            isAuthenticated: true
        )
        let loginProbeScope = manager.captureRequestScope(
            ifCurrent: generation,
            isAuthenticated: false
        )

        #expect(requestScope == nil)
        #expect(loginProbeScope != nil)
        #expect(!manager.authenticationRequestsAreAvailable)
    }

    @Test func nestedAuthenticationMutationReactivatesOnlyAfterOuterCommit() {
        let manager = imageSessionManager()
        var innerMutationCompleted = false

        manager.performAuthenticationMutation {
            #expect(!manager.authenticationRequestsAreAvailable)
            manager.performAuthenticationMutation {
                #expect(!manager.authenticationRequestsAreAvailable)
                innerMutationCompleted = true
            }
            #expect(innerMutationCompleted)
            #expect(!manager.authenticationRequestsAreAvailable)
        }

        #expect(manager.authenticationRequestsAreAvailable)
    }

    @Test func failedAuthenticationMutationRemainsInvalidated() {
        enum ExpectedError: Error {
            case failed
        }
        let manager = imageSessionManager()

        #expect(throws: ExpectedError.self) {
            try manager.performAuthenticationMutation {
                throw ExpectedError.failed
            }
        }

        #expect(!manager.authenticationRequestsAreAvailable)
    }

    @Test func clientTokenSetupCommitIsAtomicForAuthenticatedRequests() throws {
        let suiteName = "RomMAPICompatibilityTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let manager = imageSessionManager()
        let keychain = BlockingKeychainService()
        let tokenService = ClientTokenAuthService(
            keychainService: keychain,
            sessionManager: manager
        )
        let repository = SetupRepository(
            sessionManager: manager,
            clientTokenAuthService: tokenService,
            userDefaults: userDefaults
        )
        try repository.saveSetupConfiguration(
            SetupConfiguration(
                serverURL: "https://old-romm.example",
                username: "old-user",
                password: "old-password",
                token: "old-token",
                refreshToken: nil,
                setupDate: Date(),
                version: "4.9.2"
            )
        )
        try repository.saveAuthMethod(.classic)
        keychain.blockNextTokenSave()

        let commit = ClientTokenSetupCommitAction(repository: repository)
        DispatchQueue.global().async {
            commit.run()
        }
        #expect(keychain.waitUntilTokenIsStored())

        let acquisition = AuthenticationAcquisitionAction(
            manager: manager,
            repository: repository,
            tokenService: tokenService
        )
        DispatchQueue.global().async {
            acquisition.run()
        }

        #expect(!acquisition.waitForCompletion(timeout: 0.05))
        #expect(
            repository.getSetupConfiguration()?.serverURL
                == "https://old-romm.example"
        )
        #expect(tokenService.getToken() == "new-client-token")

        keychain.resumeTokenSave()

        #expect(commit.waitForCompletion())
        #expect(commit.error == nil)
        #expect(acquisition.waitForCompletion())
        #expect(acquisition.snapshot?.serverURL == "https://new-romm.example")
        #expect(acquisition.snapshot?.authMethod == .clientToken)
        #expect(acquisition.snapshot?.clientToken == "new-client-token")
        #expect(acquisition.snapshot?.requestWasAcquired == true)
    }

    @Test func failedClientTokenSetupLeavesAuthenticationInvalidated() throws {
        let suiteName = "RomMAPICompatibilityTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let manager = imageSessionManager()
        let keychain = FailingClientTokenKeychainService()
        let tokenService = ClientTokenAuthService(
            keychainService: keychain,
            sessionManager: manager
        )
        let repository = SetupRepository(
            sessionManager: manager,
            clientTokenAuthService: tokenService,
            userDefaults: userDefaults
        )

        #expect(throws: ClientTokenError.self) {
            try repository.saveClientTokenSetup(
                serverURL: "https://new-romm.example",
                token: "new-client-token",
                tokenInfo: testClientTokenInfo(),
                version: "5.0.1",
                allowIncompatibleVersionLogin: false
            )
        }

        #expect(tokenService.getToken() == nil)
        #expect(repository.getSetupConfiguration() == nil)
        #expect(!manager.authenticationRequestsAreAvailable)
    }

    @Test func staleExpirationTokenCannotClearNewAuthentication() {
        let manager = imageSessionManager()
        let requestScope = manager.captureRequestScope(isAuthenticated: true)
        var staleExpirationWasRejected = false

        let expired = manager.expireSessionIfCurrent(requestScope) { expiration in
            manager.authenticationScopeDidChange()
            staleExpirationWasRejected = !manager.isCurrentExpiration(expiration)
        }

        #expect(expired)
        #expect(staleExpirationWasRejected)
    }

    @Test func staleSharedRequestUnauthorizedDoesNotExpireNewScope() async throws {
        let counter = NotificationCounter()
        let notificationCenter = NotificationCenter()
        let sessionObserver = notificationCenter.addObserver(
            forName: .sessionExpired,
            object: nil,
            queue: nil
        ) { _ in
            counter.increment()
        }
        defer { notificationCenter.removeObserver(sessionObserver) }

        let context = statusResponseContext(notificationCenter: notificationCenter)
        let switchAction = AuthenticationSwitchAction(context: context)
        let switchID = UUID().uuidString
        let switchObserver = NotificationCenter.default.addObserver(
            forName: .statusResponseWillSwitchAuthentication,
            object: nil,
            queue: nil
        ) { notification in
            guard notification.object as? String == switchID else { return }
            switchAction.switchAuthentication()
        }
        defer { NotificationCenter.default.removeObserver(switchObserver) }

        do {
            _ = try await context.client.get(
                "status/switch-auth/401?switch=\(switchID)"
            )
            Issue.record("Expected stale request authentication failure")
        } catch APIClientError.authenticationRequired {
        } catch {
            Issue.record("Expected stale authentication failure, got \(error)")
        }

        #expect(counter.value == 0)
        let currentRequest = try RommImageRequestPolicy(
            apiClient: context.client
        ).resolve("/api/screenshots/4/content")
        _ = currentRequest.kingfisherOptions(
            sessionManager: context.authenticationSessionManager
        )
        let currentSession = try #require(
            context.authenticationSessionManager.currentSession
        )
        #expect(!currentSession.isInvalidated)
    }

    @Test func authChangeDuringRequestConstructionRebuildsScope() async throws {
        let counter = NotificationCounter()
        let notificationCenter = NotificationCenter()
        let observer = notificationCenter.addObserver(
            forName: .sessionExpired,
            object: nil,
            queue: nil
        ) { _ in
            counter.increment()
        }
        defer { notificationCenter.removeObserver(observer) }

        let tokenProvider = GenerationSwitchingTokenProvider(
            serverURL: "https://romm.example"
        )
        let manager = RommImageSessionManager(
            apiClient: RommAPIClient(
                tokenProvider: tokenProvider,
                notificationCenter: notificationCenter
            ),
            notificationCenter: notificationCenter
        )
        tokenProvider.onFirstTokenRead = {
            manager.authenticationScopeDidChange()
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StatusResponseURLProtocol.self]
        let client = RommAPIClient(
            tokenProvider: tokenProvider,
            urlSession: URLSession(configuration: configuration),
            notificationCenter: notificationCenter,
            authenticationSessionManager: manager
        )

        do {
            _ = try await client.get("status/401")
            Issue.record("Expected authentication failure after request rebuild")
        } catch APIClientError.authenticationRequired {
        } catch {
            Issue.record("Expected rebuilt authentication failure, got \(error)")
        }

        #expect(tokenProvider.tokenReadCount >= 2)
        #expect(counter.value == 1)
    }

    @Test func forbiddenResponseRemainsPermissionFailure() async throws {
        let counter = NotificationCounter()
        let notificationCenter = NotificationCenter()
        let observer = notificationCenter.addObserver(
            forName: .sessionExpired,
            object: nil,
            queue: nil
        ) { _ in
            counter.increment()
        }
        defer { notificationCenter.removeObserver(observer) }

        let client = statusResponseClient(notificationCenter: notificationCenter)
        do {
            _ = try await client.get("status/403")
            Issue.record("Expected permission failure")
        } catch APIClientError.invalidResponse(let statusCode, _) {
            #expect(statusCode == 403)
        } catch {
            Issue.record("Expected permission failure, got \(error)")
        }

        #expect(counter.value == 0)
        #expect(APIResponseStatusPolicy.classify(403) == .forbidden)
        #expect(!APIResponseStatusPolicy.classify(403).shouldExpireSession)
    }

    @Test func manualDownloadUnauthorizedResponseExpiresSession() async throws {
        let counter = NotificationCounter()
        let notificationCenter = NotificationCenter()
        let observer = notificationCenter.addObserver(
            forName: .sessionExpired,
            object: nil,
            queue: nil
        ) { _ in
            counter.increment()
        }
        defer { notificationCenter.removeObserver(observer) }

        let client = statusResponseClient(notificationCenter: notificationCenter)
        do {
            _ = try await client.getManualPDFData(
                manualURL: "https://romm.example/status/401"
            )
            Issue.record("Expected manual authentication failure")
        } catch APIClientError.authenticationRequired {
        } catch {
            Issue.record("Expected manual authentication failure, got \(error)")
        }

        #expect(counter.value == 1)
    }

    @Test func staleManualUnauthorizedDoesNotExpireNewScope() async throws {
        let counter = NotificationCounter()
        let notificationCenter = NotificationCenter()
        let sessionObserver = notificationCenter.addObserver(
            forName: .sessionExpired,
            object: nil,
            queue: nil
        ) { _ in
            counter.increment()
        }
        defer { notificationCenter.removeObserver(sessionObserver) }

        let context = statusResponseContext(notificationCenter: notificationCenter)
        let switchAction = AuthenticationSwitchAction(context: context)
        let switchID = UUID().uuidString
        let switchObserver = NotificationCenter.default.addObserver(
            forName: .statusResponseWillSwitchAuthentication,
            object: nil,
            queue: nil
        ) { notification in
            guard notification.object as? String == switchID else { return }
            switchAction.switchAuthentication()
        }
        defer { NotificationCenter.default.removeObserver(switchObserver) }

        do {
            _ = try await context.client.getManualPDFData(
                manualURL: "https://romm.example/status/switch-auth/401?switch=\(switchID)"
            )
            Issue.record("Expected stale manual authentication failure")
        } catch APIClientError.authenticationRequired {
        } catch {
            Issue.record("Expected stale manual authentication failure, got \(error)")
        }

        #expect(counter.value == 0)
        let currentRequest = try RommImageRequestPolicy(
            apiClient: context.client
        ).resolve("/api/screenshots/4/content")
        _ = currentRequest.kingfisherOptions(
            sessionManager: context.authenticationSessionManager
        )
        let currentSession = try #require(
            context.authenticationSessionManager.currentSession
        )
        #expect(!currentSession.isInvalidated)
    }

    @Test func externalManualUnauthorizedDoesNotExpireRomMSession() async throws {
        let counter = NotificationCounter()
        let notificationCenter = NotificationCenter()
        let observer = notificationCenter.addObserver(
            forName: .sessionExpired,
            object: nil,
            queue: nil
        ) { _ in
            counter.increment()
        }
        defer { notificationCenter.removeObserver(observer) }

        let client = statusResponseClient(notificationCenter: notificationCenter)
        do {
            _ = try await client.getManualPDFData(
                manualURL: "https://manuals.example/status/401"
            )
            Issue.record("Expected external manual authentication failure")
        } catch APIClientError.authenticationRequired {
        } catch {
            Issue.record("Expected external manual authentication failure, got \(error)")
        }

        #expect(counter.value == 0)
    }

    @Test func loginProbeUnauthorizedDoesNotExpireSession() async throws {
        let counter = NotificationCounter()
        let notificationCenter = NotificationCenter()
        let observer = notificationCenter.addObserver(
            forName: .sessionExpired,
            object: nil,
            queue: nil
        ) { _ in
            counter.increment()
        }
        defer { notificationCenter.removeObserver(observer) }

        let client = statusResponseClient(notificationCenter: notificationCenter)
        do {
            _ = try await client.login()
            Issue.record("Expected login authentication failure")
        } catch APIClientError.authenticationRequired {
        } catch {
            Issue.record("Expected login authentication failure, got \(error)")
        }

        #expect(counter.value == 0)
    }

    @Test func manualDownloadForbiddenResponseRemainsPermissionFailure() async throws {
        let counter = NotificationCounter()
        let notificationCenter = NotificationCenter()
        let observer = notificationCenter.addObserver(
            forName: .sessionExpired,
            object: nil,
            queue: nil
        ) { _ in
            counter.increment()
        }
        defer { notificationCenter.removeObserver(observer) }

        let client = statusResponseClient(notificationCenter: notificationCenter)
        do {
            _ = try await client.getManualPDFData(
                manualURL: "https://romm.example/status/403"
            )
            Issue.record("Expected manual permission failure")
        } catch APIClientError.invalidResponse(let statusCode, _) {
            #expect(statusCode == 403)
        } catch {
            Issue.record("Expected manual permission failure, got \(error)")
        }

        #expect(counter.value == 0)
    }

    @Test func romMFourSaveDeleteResponseDecodes() throws {
        let response = try decodeBulkDeleteResponse("[4, 7]")

        guard case .deletedIDs(let ids) = response else {
            Issue.record("Expected RomM 4 save deletion ID array")
            return
        }
        #expect(ids == [4, 7])
    }

    @Test func newerSaveDeleteResponseDecodes() throws {
        let response = try decodeBulkDeleteResponse(#"{"msg":"Saves deleted"}"#)

        guard case .acknowledgement(let acknowledgement) = response else {
            Issue.record("Expected newer save deletion acknowledgement")
            return
        }
        #expect(acknowledgement.msg == "Saves deleted")
    }

    @Test func romMFourStateDeleteResponseDecodes() throws {
        let response = try decodeBulkDeleteResponse("[9]")

        guard case .deletedIDs(let ids) = response else {
            Issue.record("Expected RomM 4 state deletion ID array")
            return
        }
        #expect(ids == [9])
    }

    @Test func newerStateDeleteResponseDecodes() throws {
        let response = try decodeBulkDeleteResponse(#"{"msg":"States deleted"}"#)

        guard case .acknowledgement(let acknowledgement) = response else {
            Issue.record("Expected newer state deletion acknowledgement")
            return
        }
        #expect(acknowledgement.msg == "States deleted")
    }

    @Test func malformedDeleteResponseFails() {
        #expect(throws: DecodingError.self) {
            try decodeBulkDeleteResponse(#"{"unexpected":true}"#)
        }
    }

    @Test func privateNetworkTrustPolicyRemainsNarrow() {
        #expect(PrivateNetworkTrustPolicy.allowsSelfSignedCertificate(for: "192.168.1.20"))
        #expect(PrivateNetworkTrustPolicy.allowsSelfSignedCertificate(for: "100.64.0.10"))
        #expect(!PrivateNetworkTrustPolicy.allowsSelfSignedCertificate(for: "romm.example"))
        #expect(!PrivateNetworkTrustPolicy.allowsSelfSignedCertificate(for: "8.8.8.8"))
    }

    @Test func romMImageDownloaderUsesPrivateNetworkTrustResponder() {
        let manager = RommImageSessionManager(
            apiClient: RommAPIClient(
                tokenProvider: MockTokenProvider(serverURL: "https://192.168.1.20")
            )
        )
        let session = manager.session(
            for: imageAuthScope("private-server")
        )

        #expect(session.isPrivateNetworkTrustConfigured)
    }

    @Test func imageTrustRequiresPrivateSameOriginHost() {
        let client = RommAPIClient(
            tokenProvider: MockTokenProvider(serverURL: "https://192.168.1.20")
        )
        let responder = RommImageAuthenticationChallengeResponder(apiClient: client)

        #expect(
            responder.allowsSelfSignedCertificate(
                for: protectionSpace(host: "192.168.1.20", port: 443, protocol: "https")
            )
        )
        #expect(
            !responder.allowsSelfSignedCertificate(
                for: protectionSpace(host: "192.168.1.21", port: 443, protocol: "https")
            )
        )
        #expect(
            !responder.allowsSelfSignedCertificate(
                for: protectionSpace(host: "192.168.1.20", port: 80, protocol: "http")
            )
        )
    }

    @Test func saveDownloadUsesServerProvidedPath() async throws {
        let repository = SaveDownloadRepositoryStub()
        let useCase = DownloadSaveUseCase(repository: repository)

        _ = try await useCase.execute(downloadPath: "/api/raw/assets/legacy/save.sav")

        #expect(repository.requestedPath == "/api/raw/assets/legacy/save.sav")
    }

    @Test func stateDownloadUsesServerProvidedPath() async throws {
        let repository = StateDownloadRepositoryStub()
        let useCase = DownloadStateUseCase(repository: repository)

        _ = try await useCase.execute(downloadPath: "/api/states/9/content")

        #expect(repository.requestedPath == "/api/states/9/content")
    }

    private func decodePlatform(aspectRatio: String?) throws -> PlatformSchema {
        let aspectRatioField = aspectRatio.map { ", \"aspect_ratio\": \($0)" } ?? ""
        let json = """
        {
          "id": 1,
          "slug": "gba",
          "fs_slug": "gba",
          "rom_count": 12,
          "name": "Game Boy Advance",
          "created_at": "2026-01-01T00:00:00Z",
          "updated_at": "2026-01-02T00:00:00Z",
          "fs_size_bytes": 1024,
          "is_unidentified": false,
          "is_identified": true,
          "missing_from_fs": false,
          "display_name": "Game Boy Advance",
          "is_public": true
          \(aspectRatioField)
        }
        """

        return try JSONDecoder().decode(PlatformSchema.self, from: Data(json.utf8))
    }

    private func decodeBulkDeleteResponse(_ json: String) throws -> BulkDeleteResponse {
        try JSONDecoder().decode(BulkDeleteResponse.self, from: Data(json.utf8))
    }

    private func authenticatedImagePolicy() -> RommImageRequestPolicy {
        let tokenProvider = MockTokenProvider(
            serverURL: "https://romm.example",
            username: "user",
            password: "pass"
        )
        return RommImageRequestPolicy(
            apiClient: RommAPIClient(tokenProvider: tokenProvider)
        )
    }

    private func imageSessionManager(
        notificationCenter: NotificationCenter = NotificationCenter()
    ) -> RommImageSessionManager {
        RommImageSessionManager(
            apiClient: RommAPIClient(
                tokenProvider: MockTokenProvider(
                    serverURL: "https://romm.example",
                    username: "user",
                    password: "pass"
                )
            ),
            notificationCenter: notificationCenter
        )
    }

    private func imageAuthScope(_ identity: String) -> RommImageAuthScope {
        guard let url = URL(string: "https://romm.example"),
              let scope = RommImageAuthScope(
                url: url,
                authorizationHeader: "AccountScope-\(identity)"
              ) else {
            preconditionFailure("Test image authentication scope must be valid")
        }
        return scope
    }

    private func testClientTokenInfo() -> ClientTokenInfo {
        ClientTokenInfo(
            tokenId: 42,
            name: "New Token",
            scopes: ["roms.read"],
            expiresAt: nil
        )
    }

    private func statusResponseClient(
        notificationCenter: NotificationCenter
    ) -> RommAPIClient {
        statusResponseContext(notificationCenter: notificationCenter).client
    }

    private func statusResponseContext(
        notificationCenter: NotificationCenter
    ) -> StatusResponseContext {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StatusResponseURLProtocol.self]
        let tokenProvider = MockTokenProvider(serverURL: "https://romm.example")
        tokenProvider.mockAuthMethod = .clientToken
        tokenProvider.mockClientToken = "rmm_test"
        let authenticationSessionManager = RommImageSessionManager(
            apiClient: RommAPIClient(
                tokenProvider: tokenProvider,
                notificationCenter: notificationCenter
            ),
            notificationCenter: notificationCenter
        )
        let client = RommAPIClient(
            tokenProvider: tokenProvider,
            urlSession: URLSession(configuration: configuration),
            notificationCenter: notificationCenter,
            authenticationSessionManager: authenticationSessionManager
        )
        return StatusResponseContext(
            client: client,
            authenticationSessionManager: authenticationSessionManager,
            tokenProvider: tokenProvider
        )
    }

    private func protectionSpace(
        host: String,
        port: Int,
        protocol networkProtocol: String
    ) -> URLProtectionSpace {
        URLProtectionSpace(
            host: host,
            port: port,
            protocol: networkProtocol,
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodServerTrust
        )
    }

    private func expectDisallowedURL(_ operation: () throws -> URL) {
        do {
            _ = try operation()
            Issue.record("Expected a disallowed URL error")
        } catch APIClientError.disallowedURL {
        } catch {
            Issue.record("Expected a disallowed URL error, got \(error)")
        }
    }

    private func expectInvalidURL(_ operation: () throws -> URL) {
        do {
            _ = try operation()
            Issue.record("Expected an invalid URL error")
        } catch APIClientError.invalidURL {
        } catch {
            Issue.record("Expected an invalid URL error, got \(error)")
        }
    }

    private func expectNoConfiguration(_ operation: () throws -> URL) {
        do {
            _ = try operation()
            Issue.record("Expected a missing configuration error")
        } catch APIClientError.noConfiguration {
        } catch {
            Issue.record("Expected a missing configuration error, got \(error)")
        }
    }
}

private struct StatusResponseContext {
    let client: RommAPIClient
    let authenticationSessionManager: RommImageSessionManager
    let tokenProvider: MockTokenProvider
}

private final class NotificationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

private final class BlockingKeychainService: PKeychainService, @unchecked Sendable {
    private let lock = NSLock()
    private let tokenStored = DispatchSemaphore(value: 0)
    private let resumeSave = DispatchSemaphore(value: 0)
    private var values: [String: String] = [:]
    private var shouldBlockTokenSave = false

    func blockNextTokenSave() {
        lock.lock()
        shouldBlockTokenSave = true
        lock.unlock()
    }

    func save(key: String, value: String) throws {
        lock.lock()
        values[key] = value
        let shouldBlock = shouldBlockTokenSave
            && key == ClientTokenAuthService.tokenKeychainKey
        if shouldBlock {
            shouldBlockTokenSave = false
        }
        lock.unlock()

        if shouldBlock {
            tokenStored.signal()
            resumeSave.wait()
        }
    }

    func get(key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func delete(key: String) throws {
        lock.lock()
        values.removeValue(forKey: key)
        lock.unlock()
    }

    func waitUntilTokenIsStored() -> Bool {
        tokenStored.wait(timeout: .now() + 1) == .success
    }

    func resumeTokenSave() {
        resumeSave.signal()
    }
}

private final class FailingClientTokenKeychainService: PKeychainService {
    private var values: [String: String] = [:]

    func save(key: String, value: String) throws {
        if key == ClientTokenAuthService.tokenInfoKeychainKey {
            throw ClientTokenError.tokenSaveFailed
        }
        values[key] = value
    }

    func get(key: String) -> String? {
        values[key]
    }

    func delete(key: String) throws {
        values.removeValue(forKey: key)
    }
}

private final class ClientTokenSetupCommitAction: @unchecked Sendable {
    private let repository: SetupRepository
    private let completion = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var storedError: Error?

    init(repository: SetupRepository) {
        self.repository = repository
    }

    var error: Error? {
        lock.lock()
        defer { lock.unlock() }
        return storedError
    }

    func run() {
        defer { completion.signal() }
        do {
            try repository.saveClientTokenSetup(
                serverURL: "https://new-romm.example",
                token: "new-client-token",
                tokenInfo: ClientTokenInfo(
                    tokenId: 42,
                    name: "New Token",
                    scopes: ["roms.read"],
                    expiresAt: nil
                ),
                version: "5.0.1",
                allowIncompatibleVersionLogin: false
            )
        } catch {
            lock.lock()
            storedError = error
            lock.unlock()
        }
    }

    func waitForCompletion() -> Bool {
        completion.wait(timeout: .now() + 1) == .success
    }
}

private struct AuthenticationSnapshot {
    let serverURL: String?
    let authMethod: AuthMethod
    let clientToken: String?
    let requestWasAcquired: Bool
}

private final class AuthenticationAcquisitionAction: @unchecked Sendable {
    private let manager: RommImageSessionManager
    private let repository: SetupRepository
    private let tokenService: ClientTokenAuthService
    private let completion = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var storedSnapshot: AuthenticationSnapshot?

    init(
        manager: RommImageSessionManager,
        repository: SetupRepository,
        tokenService: ClientTokenAuthService
    ) {
        self.manager = manager
        self.repository = repository
        self.tokenService = tokenService
    }

    var snapshot: AuthenticationSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return storedSnapshot
    }

    func run() {
        while true {
            let generation = manager.captureRequestGeneration()
            let serverURL = repository.getSetupConfiguration()?.serverURL
            let authMethod = repository.getAuthMethod()
            let clientToken = tokenService.getToken()
            guard manager.captureRequestScope(
                ifCurrent: generation,
                isAuthenticated: true
            ) != nil else {
                continue
            }
            lock.lock()
            storedSnapshot = AuthenticationSnapshot(
                serverURL: serverURL,
                authMethod: authMethod,
                clientToken: clientToken,
                requestWasAcquired: true
            )
            lock.unlock()
            completion.signal()
            return
        }
    }

    func waitForCompletion(timeout: TimeInterval = 1) -> Bool {
        completion.wait(timeout: .now() + timeout) == .success
    }
}

private final class StatusResponseURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let statusCode = statusCode(for: url),
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "application/json"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        if url.path.contains("/switch-auth/"),
           let switchID = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
           )?.queryItems?.first(where: { $0.name == "switch" })?.value {
            NotificationCenter.default.post(
                name: .statusResponseWillSwitchAuthentication,
                object: switchID
            )
        }
        let data = Data(#"{"detail":"Permission denied"}"#.utf8)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func statusCode(for url: URL) -> Int? {
        if url.lastPathComponent == "login" {
            return 401
        }
        return Int(url.lastPathComponent)
    }
}

private extension Notification.Name {
    static let statusResponseWillSwitchAuthentication = Notification.Name(
        "StatusResponseWillSwitchAuthentication"
    )
}

private final class AuthenticationSwitchAction: @unchecked Sendable {
    private let tokenProvider: MockTokenProvider
    private let authenticationSessionManager: RommImageSessionManager

    init(context: StatusResponseContext) {
        tokenProvider = context.tokenProvider
        authenticationSessionManager = context.authenticationSessionManager
    }

    func switchAuthentication() {
        tokenProvider.mockClientToken = "rmm_switched"
        authenticationSessionManager.authenticationScopeDidChange()
    }
}

private final class GenerationSwitchingTokenProvider: MockTokenProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var reads = 0
    var onFirstTokenRead: (() -> Void)?

    var tokenReadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return reads
    }

    override init(
        token: String? = nil,
        serverURL: String? = nil,
        username: String? = nil,
        password: String? = nil,
        configured: Bool = false
    ) {
        super.init(
            token: token,
            serverURL: serverURL,
            username: username,
            password: password,
            configured: configured
        )
        mockAuthMethod = .clientToken
        mockClientToken = "rmm_initial"
    }

    override func getClientToken() -> String? {
        lock.lock()
        reads += 1
        let isFirstRead = reads == 1
        let token = mockClientToken
        if isFirstRead {
            mockClientToken = "rmm_rotated"
        }
        let action = isFirstRead ? onFirstTokenRead : nil
        lock.unlock()

        action?()
        return token
    }
}

private final class SaveDownloadRepositoryStub: PSavesRepository {
    private(set) var requestedPath: String?

    func listServerSaves(romId: Int) async throws -> [SaveSchema] { [] }
    func uploadSave(romId: Int, emulator: String?, slot: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> SaveSchema { fatalError() }
    func updateSave(id: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> SaveSchema { fatalError() }
    func downloadSave(path: String) async throws -> Data {
        requestedPath = path
        return Data()
    }
    func deleteSaves(ids: [Int]) async throws {}
}

private final class StateDownloadRepositoryStub: PStatesRepository {
    private(set) var requestedPath: String?

    func listServerStates(romId: Int) async throws -> [StateSchema] { [] }
    func uploadState(romId: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> StateSchema { fatalError() }
    func updateState(id: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> StateSchema { fatalError() }
    func downloadState(path: String) async throws -> Data {
        requestedPath = path
        return Data()
    }
    func deleteStates(ids: [Int]) async throws {}
}
