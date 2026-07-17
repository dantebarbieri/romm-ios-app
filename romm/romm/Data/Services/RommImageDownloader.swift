import Foundation
import CryptoKit
import Kingfisher

struct RommImageAuthScope: Hashable {
    private let fingerprint: [UInt8]

    init?(url: URL, authorizationHeader: String?) {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              let port = RommServerURLResolver.effectivePort(for: url) else {
            return nil
        }

        let identity = "\(scheme)://\(host):\(port)\u{0}\(authorizationHeader ?? "anonymous")"
        fingerprint = Array(SHA256.hash(data: Data(identity.utf8)))
    }
}

struct RommAuthenticationRequestScope: Equatable, Sendable {
    fileprivate let generation: Int
    fileprivate let isAuthenticated: Bool
}

struct RommSessionExpiration: Equatable, Sendable {
    fileprivate let generation: Int
}

final class RommImageSessionManager: @unchecked Sendable {
    static let shared = RommImageSessionManager()

    private let lock = NSRecursiveLock()
    private let apiClient: RommAPIClient
    private let notificationCenter: NotificationCenter
    private var activeScope: RommImageAuthScope?
    private var activeSession: RommImageDownloadSession?
    private var blockedSession: RommImageDownloadSession?
    private var authenticationInvalidated = false
    private var expirationNotificationPending = false
    private var scopeGeneration = 0

    init(
        apiClient: RommAPIClient = .shared,
        notificationCenter: NotificationCenter = .default
    ) {
        self.apiClient = apiClient
        self.notificationCenter = notificationCenter
    }

    func session(
        for scope: RommImageAuthScope,
        url: URL? = nil
    ) -> RommImageDownloadSession {
        var validatedGeneration: Int?
        if let url {
            lock.lock()
            validatedGeneration = scopeGeneration
            lock.unlock()
            guard currentScope(for: url) == scope else {
                return rejectedSession()
            }
        }

        lock.lock()
        if let validatedGeneration, validatedGeneration != scopeGeneration {
            lock.unlock()
            return session(for: scope, url: url)
        }
        if authenticationInvalidated || expirationNotificationPending {
            let session = blockedSessionLocked()
            lock.unlock()
            return session
        }
        if activeScope == scope, let activeSession {
            lock.unlock()
            return activeSession
        }

        let previousSession = activeSession
        let sessionID = UUID()
        let session = RommImageDownloadSession(
            id: sessionID,
            apiClient: apiClient,
            onUnauthorized: { [weak self] in
                self?.handleUnauthorized(sessionID: sessionID)
            }
        )
        activeScope = scope
        activeSession = session
        previousSession?.invalidate()
        lock.unlock()

        return session
    }

    func reset() {
        lock.lock()
        authenticationInvalidated = true
        scopeGeneration &+= 1
        let previousSession = activeSession
        activeScope = nil
        activeSession = nil
        previousSession?.invalidate()
        lock.unlock()
    }

    func authenticationScopeDidChange() {
        lock.lock()
        let previousSession = activeSession
        activeScope = nil
        activeSession = nil
        authenticationInvalidated = false
        scopeGeneration &+= 1
        previousSession?.invalidate()
        lock.unlock()
    }

    func captureRequestScope(
        isAuthenticated: Bool
    ) -> RommAuthenticationRequestScope {
        lock.lock()
        defer { lock.unlock() }
        return RommAuthenticationRequestScope(
            generation: scopeGeneration,
            isAuthenticated: isAuthenticated
        )
    }

    func redirectHandler(
        authorizationHeader: String?
    ) -> RommImageRedirectHandler {
        RommImageRedirectHandler(
            apiClient: apiClient,
            authorizationHeader: authorizationHeader
        )
    }

    func captureRequestGeneration() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return scopeGeneration
    }

    func captureRequestScope(
        ifCurrent generation: Int,
        isAuthenticated: Bool
    ) -> RommAuthenticationRequestScope? {
        lock.lock()
        defer { lock.unlock() }
        guard generation == scopeGeneration,
              !isAuthenticated
                || (!authenticationInvalidated
                    && !expirationNotificationPending) else {
            return nil
        }
        return RommAuthenticationRequestScope(
            generation: generation,
            isAuthenticated: isAuthenticated
        )
    }

    @discardableResult
    func expireSessionIfCurrent(
        _ requestScope: RommAuthenticationRequestScope,
        notify: (RommSessionExpiration) -> Void
    ) -> Bool {
        lock.lock()
        guard requestScope.isAuthenticated,
              requestScope.generation == scopeGeneration,
              !authenticationInvalidated else {
            lock.unlock()
            return false
        }
        let expiration = beginExpirationLocked()
        lock.unlock()

        notify(expiration)
        finishExpirationNotification()
        return true
    }

    var authenticationRequestsAreAvailable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !authenticationInvalidated
            && !expirationNotificationPending
    }

    func isCurrentExpiration(_ expiration: RommSessionExpiration) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return authenticationInvalidated
            && expiration.generation == scopeGeneration
    }

    @discardableResult
    func performIfCurrentExpiration(
        _ expiration: RommSessionExpiration,
        action: () -> Void
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard authenticationInvalidated,
              expiration.generation == scopeGeneration else {
            return false
        }
        action()
        return true
    }

    private func handleUnauthorized(sessionID: UUID) {
        lock.lock()
        guard activeSession?.id == sessionID else {
            lock.unlock()
            return
        }
        let expiration = beginExpirationLocked()
        lock.unlock()

        notificationCenter.post(name: .sessionExpired, object: expiration)
        finishExpirationNotification()
    }

    private func beginExpirationLocked() -> RommSessionExpiration {
        authenticationInvalidated = true
        expirationNotificationPending = true
        scopeGeneration &+= 1
        let expiredSession = activeSession
        activeScope = nil
        activeSession = nil
        expiredSession?.invalidate()
        return RommSessionExpiration(generation: scopeGeneration)
    }

    private func finishExpirationNotification() {
        lock.lock()
        expirationNotificationPending = false
        lock.unlock()
    }

    private func currentScope(for url: URL) -> RommImageAuthScope? {
        let authorizationHeader: String?
        do {
            authorizationHeader = try apiClient.authorizationHeader(for: url)
        } catch APIClientError.noCredentials {
            authorizationHeader = nil
        } catch {
            return nil
        }
        return RommImageAuthScope(
            url: url,
            authorizationHeader: authorizationHeader
        )
    }

    private func rejectedSession() -> RommImageDownloadSession {
        lock.lock()
        let session = blockedSessionLocked()
        lock.unlock()
        return session
    }

    private func blockedSessionLocked() -> RommImageDownloadSession {
        if let blockedSession {
            return blockedSession
        }
        let session = RommImageDownloadSession(
            id: UUID(),
            apiClient: apiClient,
            onUnauthorized: {}
        )
        session.invalidate()
        blockedSession = session
        return session
    }

    var currentSession: RommImageDownloadSession? {
        lock.lock()
        defer { lock.unlock() }
        return activeSession
    }
}

final class RommImageRedirectHandler: ImageDownloadRedirectHandler, @unchecked Sendable {
    private let apiClient: RommAPIClient
    private let authorizationHeader: String?

    init(apiClient: RommAPIClient, authorizationHeader: String?) {
        self.apiClient = apiClient
        self.authorizationHeader = authorizationHeader
    }

    func handleHTTPRedirection(
        for task: SessionDataTask,
        response: HTTPURLResponse,
        newRequest: URLRequest
    ) async -> URLRequest? {
        redirectedRequest(newRequest)
    }

    func redirectedRequest(_ request: URLRequest) -> URLRequest? {
        guard let url = request.url,
              apiClient.isSameOriginAsServer(url) else {
            return nil
        }
        var authenticatedRequest = request
        if let authorizationHeader {
            authenticatedRequest.setValue(
                authorizationHeader,
                forHTTPHeaderField: "Authorization"
            )
        }
        return authenticatedRequest
    }
}

final class RommScopedImageDownloader: ImageDownloader {
    private let scopeLock = NSLock()
    private var scopeInvalidated = false

    override func downloadImage(
        with url: URL,
        options: KingfisherParsedOptionsInfo,
        completionHandler: (@Sendable (Result<ImageLoadingResult, KingfisherError>) -> Void)? = nil
    ) -> DownloadTask {
        scopeLock.lock()
        defer { scopeLock.unlock() }

        guard !scopeInvalidated else {
            var blockedOptions = options
            blockedOptions.requestModifier = AnyModifier { _ in nil }
            return super.downloadImage(
                with: url,
                options: blockedOptions,
                completionHandler: completionHandler
            )
        }
        return super.downloadImage(
            with: url,
            options: options,
            completionHandler: completionHandler
        )
    }

    func invalidateScope() {
        scopeLock.lock()
        scopeInvalidated = true
        scopeLock.unlock()
        cancelAll()
    }

    var isScopeInvalidated: Bool {
        scopeLock.lock()
        defer { scopeLock.unlock() }
        return scopeInvalidated
    }
}

final class RommImageDownloadSession: @unchecked Sendable {
    let id: UUID
    let downloader: RommScopedImageDownloader
    let cache: ImageCache
    let responseDelegate: RommImageDownloadResponseDelegate

    private let lock = NSLock()
    private let challengeResponder: RommImageAuthenticationChallengeResponder
    private var invalidated = false

    init(
        id: UUID,
        apiClient: RommAPIClient,
        onUnauthorized: @escaping @Sendable () -> Void
    ) {
        self.id = id
        let name = "romm-private-\(UUID().uuidString)"
        challengeResponder = RommImageAuthenticationChallengeResponder(apiClient: apiClient)
        responseDelegate = RommImageDownloadResponseDelegate(
            onUnauthorized: onUnauthorized
        )
        downloader = RommScopedImageDownloader(name: name)
        cache = ImageCache(name: name)
        downloader.downloadTimeout = 30
        downloader.authenticationChallengeResponder = challengeResponder
        downloader.delegate = responseDelegate
    }

    func invalidate() {
        lock.lock()
        guard !invalidated else {
            lock.unlock()
            return
        }
        invalidated = true
        lock.unlock()

        downloader.invalidateScope()
        cache.clearMemoryCache()
    }

    var isInvalidated: Bool {
        lock.lock()
        defer { lock.unlock() }
        return invalidated
    }

    var isPrivateNetworkTrustConfigured: Bool {
        downloader !== ImageDownloader.default
            && downloader.authenticationChallengeResponder === challengeResponder
            && downloader.delegate === responseDelegate
    }
}

final class RommImageDownloadResponseDelegate: ImageDownloaderDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let onUnauthorized: @Sendable () -> Void
    private var didExpireSession = false

    init(onUnauthorized: @escaping @Sendable () -> Void) {
        self.onUnauthorized = onUnauthorized
    }

    func isValidStatusCode(_ code: Int, for downloader: ImageDownloader) -> Bool {
        _ = handle(statusCode: code)
        return (200..<400).contains(code)
    }

    @discardableResult
    func handle(statusCode: Int) -> APIResponseStatusClassification {
        let classification = APIResponseStatusPolicy.classify(statusCode)
        guard classification.shouldExpireSession else {
            return classification
        }

        lock.lock()
        let shouldNotify = !didExpireSession
        didExpireSession = true
        lock.unlock()

        if shouldNotify {
            onUnauthorized()
        }
        return classification
    }
}

final class RommImageAuthenticationChallengeResponder: AuthenticationChallengeResponsible {
    private let apiClient: RommAPIClient

    init(apiClient: RommAPIClient) {
        self.apiClient = apiClient
    }

    func downloader(
        _ downloader: ImageDownloader,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let protectionSpace = challenge.protectionSpace
        guard protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              allowsSelfSignedCertificate(for: protectionSpace),
              let serverTrust = protectionSpace.serverTrust else {
            return (.performDefaultHandling, nil)
        }
        return (.useCredential, URLCredential(trust: serverTrust))
    }

    func downloader(
        _ downloader: ImageDownloader,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        (.performDefaultHandling, nil)
    }

    func allowsSelfSignedCertificate(for protectionSpace: URLProtectionSpace) -> Bool {
        guard PrivateNetworkTrustPolicy.allowsSelfSignedCertificate(for: protectionSpace.host),
              let originURL = originURL(for: protectionSpace) else {
            return false
        }
        return apiClient.isSameOriginAsServer(originURL)
    }

    private func originURL(for protectionSpace: URLProtectionSpace) -> URL? {
        var components = URLComponents()
        components.scheme = protectionSpace.protocol
        components.host = protectionSpace.host
        components.port = protectionSpace.port > 0 ? protectionSpace.port : nil
        return components.url
    }
}
