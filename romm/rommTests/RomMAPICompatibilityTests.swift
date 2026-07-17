import Foundation
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
        let imageDownloader = RommImageDownloader(
            apiClient: RommAPIClient(
                tokenProvider: MockTokenProvider(serverURL: "https://192.168.1.20")
            )
        )

        #expect(imageDownloader.isPrivateNetworkTrustConfigured)
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
