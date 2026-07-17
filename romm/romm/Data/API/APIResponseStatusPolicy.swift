import Foundation

enum APIResponseStatusClassification: Equatable {
    case success
    case unauthenticated
    case forbidden
    case clientError
    case serverError
    case unexpected

    var shouldExpireSession: Bool {
        self == .unauthenticated
    }
}

struct APIResponseStatusPolicy {
    static func classify(_ statusCode: Int) -> APIResponseStatusClassification {
        switch statusCode {
        case 200...299:
            return .success
        case 401:
            return .unauthenticated
        case 403:
            return .forbidden
        case 400...499:
            return .clientError
        case 500...599:
            return .serverError
        default:
            return .unexpected
        }
    }
}
