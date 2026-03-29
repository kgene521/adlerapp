// AdlerCRM/Services/AuthManager.swift  28/03/2026 02:01:42
import Foundation
import SwiftUI
import Combine

@MainActor
final class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: UserInfo?
    @Published var passwordExpired = false

    private let api = APIClient.shared

    init() {
        // Restore session from keychain
        if let token = KeychainHelper.load(key: "adler_token"),
           let userData = KeychainHelper.load(key: "adler_user"),
           let data = userData.data(using: .utf8),
           let user = try? JSONDecoder().decode(UserInfo.self, from: data) {
            self.currentUser = user
            self.isAuthenticated = true
            self.passwordExpired = KeychainHelper.load(key: "adler_pwd_expired") == "true"
            _ = token
        }
    }

    // MARK: - Login Flow

    struct LoginResult {
        var success = false
        var totpRequired = false
        var totpSetupNeeded = false
        var tempToken: String?
        var userName: String?
        var error: String?
    }

    func login(username: String, password: String) async -> LoginResult {
        do {
            let response = try await api.login(username: username, password: password)

            if response.totp_required == true {
                return LoginResult(
                    totpRequired: true,
                    totpSetupNeeded: response.totp_setup_needed ?? false,
                    tempToken: response.temp_token,
                    userName: response.user?.name ?? username
                )
            }

            // Direct login (shouldn't happen with current backend but safe)
            if let token = response.token, let user = response.user {
                finalizeLogin(token: token, user: user, passwordExpired: false)
                return LoginResult(success: true)
            }

            return LoginResult(error: response.error ?? "Login failed")
        } catch {
            return LoginResult(error: error.localizedDescription)
        }
    }

    // MARK: - TOTP

    func setupTOTP(tempToken: String) async throws -> TOTPSetupResponse {
        return try await api.totpSetup(tempToken: tempToken)
    }

    func verifyTOTP(tempToken: String, code: String) async throws {
        let response = try await api.totpVerify(tempToken: tempToken, code: code)
        finalizeLogin(
            token: response.token,
            user: response.user,
            passwordExpired: response.password_expired ?? false
        )
    }

    // MARK: - Session Management

    func finalizeLogin(token: String, user: UserInfo, passwordExpired: Bool) {
        KeychainHelper.save(key: "adler_token", value: token)
        if let userData = try? JSONEncoder().encode(user),
           let userString = String(data: userData, encoding: .utf8) {
            KeychainHelper.save(key: "adler_user", value: userString)
        }
        if passwordExpired {
            KeychainHelper.save(key: "adler_pwd_expired", value: "true")
        } else {
            KeychainHelper.delete(key: "adler_pwd_expired")
        }

        self.currentUser = user
        self.passwordExpired = passwordExpired
        self.isAuthenticated = true
    }

    func clearPasswordExpired() {
        self.passwordExpired = false
        KeychainHelper.delete(key: "adler_pwd_expired")
    }

    func logout() {
        KeychainHelper.delete(key: "adler_token")
        KeychainHelper.delete(key: "adler_user")
        KeychainHelper.delete(key: "adler_pwd_expired")
        self.currentUser = nil
        self.isAuthenticated = false
        self.passwordExpired = false
    }
}
