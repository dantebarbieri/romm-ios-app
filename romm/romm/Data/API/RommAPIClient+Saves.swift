//
//  RommAPIClient+Saves.swift
//  romm
//

import Foundation

// MARK: - Saves API
extension RommAPIClient {

    func uploadSave(
        romId: Int,
        emulator: String?,
        slot: String?,
        deviceId: String?,
        fileName: String,
        fileData: Data,
        screenshotData: Data?
    ) async throws -> SaveSchema {
        let path = withQuery("api/saves", [
            ("rom_id", String(romId)),
            ("emulator", emulator),
            ("slot", slot),
            ("device_id", deviceId)
        ])
        let boundary = "RommSavesBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var formData = Data()
        formData.appendFileField(
            boundary: boundary,
            name: "saveFile",
            fileName: fileName,
            mimeType: "application/octet-stream",
            data: fileData
        )
        if let screenshotData {
            formData.appendFileField(
                boundary: boundary,
                name: "screenshotFile",
                fileName: "screenshot.png",
                mimeType: "image/png",
                data: screenshotData
            )
        }
        formData.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let data = try await multipartRequest(
            path: path,
            method: .post,
            boundary: boundary,
            formData: formData,
            additionalHeaders: nil
        )
        do {
            return try JSONDecoder().decode(SaveSchema.self, from: data)
        } catch {
            throw APIClientError.decodingError(error)
        }
    }

    func updateSave(
        id: Int,
        emulator: String?,
        fileName: String,
        fileData: Data,
        screenshotData: Data?
    ) async throws -> SaveSchema {
        let path = withQuery("api/saves/\(id)", [("emulator", emulator)])
        let boundary = "RommSavesBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        var formData = Data()
        formData.appendFileField(
            boundary: boundary,
            name: "saveFile",
            fileName: fileName,
            mimeType: "application/octet-stream",
            data: fileData
        )
        if let screenshotData {
            formData.appendFileField(
                boundary: boundary,
                name: "screenshotFile",
                fileName: "screenshot.png",
                mimeType: "image/png",
                data: screenshotData
            )
        }
        formData.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let data = try await multipartRequest(
            path: path,
            method: .put,
            boundary: boundary,
            formData: formData,
            additionalHeaders: nil
        )
        do {
            return try JSONDecoder().decode(SaveSchema.self, from: data)
        } catch {
            throw APIClientError.decodingError(error)
        }
    }

    func downloadSave(path: String) async throws -> Data {
        return try await getBinary(path)
    }

    func deleteSaves(ids: [Int]) async throws {
        struct Body: Codable { let saves: [Int] }
        _ = try await post(
            "api/saves/delete",
            body: Body(saves: ids),
            responseType: BulkDeleteResponse.self
        )
    }
}

struct BulkDeleteAck: Decodable {
    let msg: String
}

enum BulkDeleteResponse: Decodable {
    case deletedIDs([Int])
    case acknowledgement(BulkDeleteAck)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let ids = try? container.decode([Int].self) {
            self = .deletedIDs(ids)
            return
        }
        if let acknowledgement = try? container.decode(BulkDeleteAck.self) {
            self = .acknowledgement(acknowledgement)
            return
        }
        throw DecodingError.typeMismatch(
            BulkDeleteResponse.self,
            .init(
                codingPath: decoder.codingPath,
                debugDescription: "Expected deleted ID array or acknowledgement object"
            )
        )
    }

}

// MARK: - Multipart File Helper

extension Data {
    mutating func appendFileField(
        boundary: String,
        name: String,
        fileName: String,
        mimeType: String,
        data: Data
    ) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
