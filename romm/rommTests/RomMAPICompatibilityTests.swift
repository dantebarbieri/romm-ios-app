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

        let url = try client.buildURL(path: "/api/saves/42/content")

        #expect(url.absoluteString == "https://romm.example/base/api/saves/42/content")
    }

    @Test func absoluteAssetURLIsPreserved() throws {
        let client = RommAPIClient(tokenProvider: MockTokenProvider())

        let url = try client.buildURL(path: "https://cdn.example/api/states/7/content?token=value")

        #expect(url.absoluteString == "https://cdn.example/api/states/7/content?token=value")
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
        let url = try client.buildURL(path: "https://cdn.example/signed/asset")

        #expect(try client.authorizationHeader(for: url) == nil)
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
