import Foundation
import Kingfisher

enum RommImageAccessPolicy: Equatable {
    case romm
    case publicExternal
}

struct RommImageRequest: Equatable {
    let url: URL
    let accessPolicy: RommImageAccessPolicy
    let authorizationHeader: String?
    let authScope: RommImageAuthScope?

    var usesRommAuthentication: Bool {
        authorizationHeader != nil
    }

    var usesPrivateNetworkTrust: Bool {
        accessPolicy == .romm
    }

    var usesSharedPersistentCache: Bool {
        accessPolicy == .publicExternal
    }

    func kingfisherOptions(
        sessionManager: RommImageSessionManager
    ) -> KingfisherOptionsInfo {
        switch accessPolicy {
        case .publicExternal:
            return [
                .diskCacheExpiration(.days(30)),
                .cacheOriginalImage
            ]
        case .romm:
            guard let authScope else {
                assertionFailure("RomM image requests require an authentication scope")
                return []
            }
            let session = sessionManager.session(for: authScope, url: url)
            var options: KingfisherOptionsInfo = [
                .downloader(session.downloader),
                .targetCache(session.cache),
                .cacheMemoryOnly,
                .redirectHandler(
                    sessionManager.redirectHandler(
                        authorizationHeader: authorizationHeader
                    )
                )
            ]
            if let authorizationHeader {
                options.append(.requestModifier(AnyModifier { request in
                    var authenticatedRequest = request
                    authenticatedRequest.setValue(
                        authorizationHeader,
                        forHTTPHeaderField: "Authorization"
                    )
                    return authenticatedRequest
                }))
            }
            return options
        }
    }
}

struct RommImageRequestPolicy {
    private let apiClient: RommAPIClient

    init(apiClient: RommAPIClient = .shared) {
        self.apiClient = apiClient
    }

    func resolve(_ reference: String) throws -> RommImageRequest {
        guard !reference.isEmpty else {
            throw APIClientError.invalidURL(reference)
        }
        guard !reference.hasPrefix("//") else {
            throw APIClientError.disallowedURL(reference)
        }

        let components = URLComponents(string: reference)
        if let scheme = components?.scheme {
            guard scheme.caseInsensitiveCompare("http") == .orderedSame
                    || scheme.caseInsensitiveCompare("https") == .orderedSame else {
                throw APIClientError.disallowedURL(reference)
            }
            guard let components,
                  let host = components.host,
                  !host.isEmpty,
                  components.user == nil,
                  components.password == nil,
                  let absoluteURL = components.url else {
                throw APIClientError.invalidURL(reference)
            }

            if apiClient.isSameOriginAsServer(absoluteURL) {
                return try rommRequest(for: reference)
            }
            return RommImageRequest(
                url: absoluteURL,
                accessPolicy: .publicExternal,
                authorizationHeader: nil,
                authScope: nil
            )
        }

        return try rommRequest(for: reference)
    }

    private func rommRequest(for reference: String) throws -> RommImageRequest {
        let url = try apiClient.buildURL(path: reference)
        let authorizationHeader: String?
        do {
            authorizationHeader = try apiClient.authorizationHeader(for: url)
        } catch APIClientError.noCredentials {
            authorizationHeader = nil
        }
        guard let authScope = RommImageAuthScope(
            url: url,
            authorizationHeader: authorizationHeader
        ) else {
            throw APIClientError.invalidURL(reference)
        }
        return RommImageRequest(
            url: url,
            accessPolicy: .romm,
            authorizationHeader: authorizationHeader,
            authScope: authScope
        )
    }
}
