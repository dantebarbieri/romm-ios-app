//
//  RommAPIClient+Auth.swift
//  romm
//
//  Created by Ilyas Hallak on 06.08.25.
//

import Foundation

// MARK: - Auth API Wrapper
extension RommAPIClient {
    func login() async throws -> String {
        let data = try await makeRequest(
            path: "api/login",
            method: .post,
            body: nil,
            expiresSessionOnUnauthorized: false
        )
        return String(data: data, encoding: .utf8) ?? ""
    }

    func logout() async throws -> String {
        let data = try await post("api/logout")
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - Users API Wrapper
extension RommAPIClient {
    func getCurrentUser() async throws -> UserSchema {
        return try await get("api/users/me", responseType: UserSchema.self)
    }

    func getUsers() async throws -> [UserSchema] {
        return try await get("api/users", responseType: [UserSchema].self)
    }
}