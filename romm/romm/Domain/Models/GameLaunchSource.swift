import Foundation

enum GameLaunchSource: Codable, Equatable, Sendable {
    case save(serverID: Int?, fileName: String, updatedAt: Date?)
    case state(serverID: Int?, slot: Int, fileName: String, updatedAt: Date?, emulator: String?)

    var serverID: Int? {
        switch self {
        case .save(let serverID, _, _), .state(let serverID, _, _, _, _):
            return serverID
        }
    }

    var title: String {
        switch self {
        case .save(_, let fileName, _):
            return fileName
        case .state(_, let slot, let fileName, _, _):
            return slot > 0 ? "Slot \(slot)" : fileName
        }
    }

    var stateEmulator: String? {
        guard case .state(_, _, _, _, let emulator) = self else { return nil }
        return emulator
    }
}
