//
//  KeychainService.swift
//  romm
//
//  Created by Ilyas Hallak on 28.08.25.
//

import Foundation
import Security

protocol PKeychainService {
    func save(key: String, value: String) throws
    func get(key: String) -> String?
    func read(key: String) throws -> String?
    func delete(key: String) throws
}

extension PKeychainService {
    func read(key: String) throws -> String? {
        get(key: key)
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case retrievalFailed(OSStatus)
    case deletionFailed(OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save to keychain: \(status)"
        case .retrievalFailed(let status):
            return "Failed to retrieve from keychain: \(status)"
        case .deletionFailed(let status):
            return "Failed to delete from keychain: \(status)"
        }
    }
}

class KeychainService: PKeychainService {
    private let service: String
    private let logger = Logger.data
    
    init(service: String) {
        self.service = service
    }
    
    func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.saveFailed(-1)
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: service,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            logger.error("Keychain save error for service '\(service)': \(status)")
            throw KeychainError.saveFailed(status)
        }
        
        logger.debug("Saved to keychain - Service: \(service), Key: \(key)")
    }
    
    func get(key: String) -> String? {
        do {
            return try read(key: key)
        } catch {
            logger.error("Keychain retrieval failed for service '\(service)': \(error.localizedDescription)")
            return nil
        }
    }

    func read(key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.retrievalFailed(status)
        }
        guard let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.retrievalFailed(errSecDecode)
        }
        return value
    }
    
    func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: service
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Keychain delete error for service '\(service)': \(status)")
            throw KeychainError.deletionFailed(status)
        }
        
        logger.debug("Deleted from keychain - Service: \(service), Key: \(key)")
    }
}

// MARK: - Convenience Extensions

extension KeychainService {
    // Setup-specific convenience methods
    static let setup = KeychainService(service: "com.romm.app.setup")

    // SFTP-specific convenience methods
    static let sftp = KeychainService(service: "com.romm.sftp")
}
