import Foundation

struct RommServerURLResolver {
    private let serverComponents: URLComponents

    init(serverURL: String?) throws {
        guard let serverURL else {
            throw APIClientError.noConfiguration
        }
        guard let components = URLComponents(string: serverURL),
              Self.isSupportedScheme(components.scheme),
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.url != nil else {
            throw APIClientError.invalidURL(serverURL)
        }
        serverComponents = components
    }

    func resolve(_ reference: String) throws -> URL {
        guard !reference.isEmpty else {
            throw APIClientError.invalidURL(reference)
        }
        guard !reference.hasPrefix("//") else {
            throw APIClientError.disallowedURL(reference)
        }

        let referenceParts: ReferenceParts
        if let scheme = Self.detectedScheme(in: reference) {
            guard Self.isSupportedScheme(scheme) else {
                throw APIClientError.disallowedURL(reference)
            }
            referenceParts = try parseAbsoluteReference(reference)
        } else {
            referenceParts = Self.parseRelativeReference(reference)
        }

        var resolved = serverComponents
        resolved.percentEncodedPath = referenceParts.isAbsolute
            ? Self.encodedPath(referenceParts.path)
            : Self.joinedPath(
                base: serverComponents.percentEncodedPath,
                relative: Self.encodedPath(referenceParts.path)
            )
        resolved.percentEncodedQuery = referenceParts.query.map(Self.encodedQuery)
        resolved.fragment = nil

        guard let url = resolved.url, isSameOrigin(url) else {
            throw APIClientError.invalidURL(reference)
        }
        return url
    }

    func isSameOrigin(_ url: URL) -> Bool {
        guard Self.isSupportedScheme(url.scheme),
              let serverURL = serverComponents.url else {
            return false
        }
        return url.scheme?.lowercased() == serverURL.scheme?.lowercased()
            && url.host?.lowercased() == serverURL.host?.lowercased()
            && Self.effectivePort(for: url) == Self.effectivePort(for: serverURL)
    }

    static func effectivePort(for url: URL) -> Int? {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "http": return 80
        case "https": return 443
        default: return nil
        }
    }

    private func parseAbsoluteReference(_ reference: String) throws -> ReferenceParts {
        guard let schemeSeparator = reference.range(of: "://") else {
            throw APIClientError.invalidURL(reference)
        }

        let authorityStart = schemeSeparator.upperBound
        let remainderStart = reference[authorityStart...].firstIndex { character in
            character == "/" || character == "?" || character == "#"
        } ?? reference.endIndex
        let authority = String(reference[authorityStart..<remainderStart])
        let originString = "\(reference[..<schemeSeparator.lowerBound])://\(authority)"

        guard let absoluteOrigin = URLComponents(string: originString),
              Self.isSupportedScheme(absoluteOrigin.scheme),
              let host = absoluteOrigin.host,
              !host.isEmpty,
              absoluteOrigin.user == nil,
              absoluteOrigin.password == nil,
              absoluteOrigin.path.isEmpty,
              absoluteOrigin.query == nil,
              absoluteOrigin.fragment == nil,
              let originURL = absoluteOrigin.url else {
            throw APIClientError.invalidURL(reference)
        }
        guard isSameOrigin(originURL) else {
            throw APIClientError.disallowedURL(reference)
        }

        let remainder = String(reference[remainderStart...])
        guard remainder.isEmpty || remainder.hasPrefix("/") || remainder.hasPrefix("?") else {
            throw APIClientError.invalidURL(reference)
        }
        let parts = Self.splitPathAndQuery(remainder)
        return ReferenceParts(path: parts.path, query: parts.query, isAbsolute: true)
    }

    private static func parseRelativeReference(_ reference: String) -> ReferenceParts {
        let parts = splitPathAndQuery(reference)
        return ReferenceParts(path: parts.path, query: parts.query, isAbsolute: false)
    }

    private static func splitPathAndQuery(_ reference: String) -> (path: String, query: String?) {
        guard let querySeparator = reference.firstIndex(of: "?") else {
            return (reference, nil)
        }
        return (
            String(reference[..<querySeparator]),
            String(reference[reference.index(after: querySeparator)...])
        )
    }

    private static func joinedPath(base: String, relative: String) -> String {
        let basePath = base.isEmpty ? "/" : base
        let trimmedBase = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath
        let trimmedRelative = relative.drop(while: { $0 == "/" })
        guard !trimmedRelative.isEmpty else {
            return trimmedBase.isEmpty ? "/" : trimmedBase
        }
        return "\(trimmedBase)/\(trimmedRelative)"
    }

    private static func encodedPath(_ path: String) -> String {
        percentEncode(path, allowedASCII: pathAllowedASCII)
    }

    private static func encodedQuery(_ query: String) -> String {
        percentEncode(query, allowedASCII: queryAllowedASCII)
    }

    private static func percentEncode(_ value: String, allowedASCII: Set<UInt8>) -> String {
        let bytes = Array(value.utf8)
        var result = ""
        var index = 0

        while index < bytes.count {
            let byte = bytes[index]
            if byte == 37,
               index + 2 < bytes.count,
               isHexDigit(bytes[index + 1]),
               isHexDigit(bytes[index + 2]) {
                result.append(Character(UnicodeScalar(byte)))
                result.append(Character(UnicodeScalar(bytes[index + 1])))
                result.append(Character(UnicodeScalar(bytes[index + 2])))
                index += 3
            } else if allowedASCII.contains(byte) {
                result.append(Character(UnicodeScalar(byte)))
                index += 1
            } else {
                result.append(String(format: "%%%02X", byte))
                index += 1
            }
        }
        return result
    }

    private static func detectedScheme(in reference: String) -> String? {
        guard let colon = reference.firstIndex(of: ":") else { return nil }
        let candidate = reference[..<colon]
        guard let first = candidate.utf8.first,
              isASCIIAlpha(first),
              candidate.utf8.dropFirst().allSatisfy({
                  isASCIIAlpha($0) || isASCIIDigit($0) || $0 == 43 || $0 == 45 || $0 == 46
              }) else {
            return nil
        }
        return String(candidate)
    }

    private static func isSupportedScheme(_ scheme: String?) -> Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private static func isHexDigit(_ byte: UInt8) -> Bool {
        isASCIIDigit(byte)
            || (65...70).contains(byte)
            || (97...102).contains(byte)
    }

    private static func isASCIIAlpha(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte)
    }

    private static func isASCIIDigit(_ byte: UInt8) -> Bool {
        (48...57).contains(byte)
    }

    private static let pathAllowedASCII = Set(
        Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/".utf8)
    )
    private static let queryAllowedASCII = Set(
        Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~!$&'()*+,/:;=?@".utf8)
    )

    private struct ReferenceParts {
        let path: String
        let query: String?
        let isAbsolute: Bool
    }
}
