import Foundation
import Kingfisher

final class RommImageDownloader {
    static let shared = RommImageDownloader()

    let downloader: ImageDownloader
    let challengeResponder: RommImageAuthenticationChallengeResponder

    init(apiClient: RommAPIClient = .shared) {
        challengeResponder = RommImageAuthenticationChallengeResponder(apiClient: apiClient)
        downloader = ImageDownloader(name: "romm-private-network")
        downloader.downloadTimeout = 30
        downloader.authenticationChallengeResponder = challengeResponder
    }

    var isPrivateNetworkTrustConfigured: Bool {
        downloader !== ImageDownloader.default
            && downloader.authenticationChallengeResponder === challengeResponder
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
