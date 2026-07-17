import Foundation
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

        #expect(counter.value == 1)
        #expect(APIResponseStatusPolicy.classify(401).shouldExpireSession)
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

    private func statusResponseClient(
        notificationCenter: NotificationCenter
    ) -> RommAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StatusResponseURLProtocol.self]
        let tokenProvider = MockTokenProvider(serverURL: "https://romm.example")
        tokenProvider.mockAuthMethod = .clientToken
        tokenProvider.mockClientToken = "rmm_test"
        return RommAPIClient(
            tokenProvider: tokenProvider,
            urlSession: URLSession(configuration: configuration),
            notificationCenter: notificationCenter
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

private final class StatusResponseURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let statusCode = Int(url.lastPathComponent),
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "application/json"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let data = Data(#"{"detail":"Permission denied"}"#.utf8)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
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
