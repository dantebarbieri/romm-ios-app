import Foundation

final class SavesRepository: PSavesRepository {
    private let logger = Logger.data
    private let apiClient: PRommAPIClient

    init(apiClient: PRommAPIClient = RommAPIClient.shared) {
        self.apiClient = apiClient
    }

    func listServerSaves(romId: Int) async throws -> [SaveSchema] {
        try await apiClient.getSaves(romId: romId)
    }

    func uploadSave(romId: Int, emulator: String?, slot: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> SaveSchema {
        logger.info("☁️ Uploading save romId=\(romId) emulator=\(emulator ?? "-") slot=\(slot ?? "-") size=\(fileData.count)")
        return try await apiClient.uploadSave(
            romId: romId,
            emulator: emulator,
            slot: slot,
            deviceId: nil,
            fileName: fileName,
            fileData: fileData,
            screenshotData: screenshotData
        )
    }

    func updateSave(id: Int, emulator: String?, fileName: String, fileData: Data, screenshotData: Data?) async throws -> SaveSchema {
        logger.info("☁️ Updating save id=\(id) size=\(fileData.count)")
        return try await apiClient.updateSave(
            id: id,
            emulator: emulator,
            fileName: fileName,
            fileData: fileData,
            screenshotData: screenshotData
        )
    }

    func downloadSave(path: String) async throws -> Data {
        logger.info("☁️ Downloading save from server-provided path")
        return try await apiClient.downloadSave(path: path)
    }

    func deleteSaves(ids: [Int]) async throws {
        logger.info("☁️ Deleting saves \(ids)")
        try await apiClient.deleteSaves(ids: ids)
    }
}
