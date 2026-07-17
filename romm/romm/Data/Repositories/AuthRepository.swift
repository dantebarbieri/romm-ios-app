//
//  AuthRepository.swift
//  romm
//
//  Created by Ilyas Hallak on 06.08.25.
//

import Foundation

class AuthRepository: PAuthRepository {
    private let logger = Logger.data
    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var currentUser: User?
    
    private let apiClient: PRommAPIClient
    
    init(apiClient: PRommAPIClient = RommAPIClient.shared) {
        self.apiClient = apiClient
    }
    
    func login(username: String, password: String) async throws -> User {
        // Login is now handled by ConfigurationService during setup
        // This method is kept for compatibility but delegates to getCurrentUser
        logger.info("Login called - checking authentication status...")
        
        if let user = try await getCurrentUser() {
            return user
        } else {
            throw AuthError.unauthorized
        }
    }
    
    func logout() async throws {
        logger.info("Logging out...")
        
        do {
            // Try to call logout endpoint
            _ = try await apiClient.post("api/auth/logout", body: nil)
            logger.info("Logout API call successful")
        } catch {
            logger.warning("Logout API call failed, continuing with local cleanup: \(error)")
        }
        
        // Always clear local authentication state
        await MainActor.run {
            self.isAuthenticated = false
            self.currentUser = nil            
        }
        RommImageSessionManager.shared.reset()
        
        logger.info("Logout complete")
    }
    
    func getCurrentUser() async throws -> User? {
        logger.info("Getting current user with authenticated request...")
        
        do {
            let apiUser = try await apiClient.get("api/users/me", responseType: UserSchema.self)
            let domainUser = UserMapper.mapFromAPI(apiUser)
            
            await MainActor.run {
                self.currentUser = domainUser
                self.isAuthenticated = true
            }
            
            logger.info("Current user retrieved: \(domainUser.username)")
            return domainUser
        } catch let error as APIClientError {
            if case .authenticationRequired = error {
                await MainActor.run {
                    self.isAuthenticated = false
                    self.currentUser = nil
                }
            }
            logger.error("API error getting current user: \(error)")
            throw AuthError.networkError
        } catch {
            logger.error("Error getting current user: \(error)")
            throw AuthError.networkError
        }
    }
    
    private func getCurrentUserInternal(completion: @escaping (User?, Error?) -> Void) {
        Task {
            do {
                let user = try await getCurrentUser()
                completion(user, nil)
            } catch {
                completion(nil, error)
            }
        }
    }
}
