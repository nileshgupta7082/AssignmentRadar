//
//  BackendAuthManager.swift
//  AssignementRadar
//
//  Created for Supabase Auth & Secure User Identity Management.
//

import Foundation
import Security
import CryptoKit

// MARK: - Backend Keychain Helper

enum BackendKeychainHelper {
    private static let serviceName = "edu.kiet.AssignementRadar.backend"
    private static let tokenAccount = "supabase_access_token"
    private static let userIdAccount = "supabase_user_id"

    static func saveToken(_ token: String) {
        save(string: token, forAccount: tokenAccount)
    }

    static func getToken() -> String? {
        load(forAccount: tokenAccount)
    }

    static func deleteToken() {
        delete(forAccount: tokenAccount)
    }

    static func saveUserId(_ userId: UUID) {
        save(string: userId.uuidString, forAccount: userIdAccount)
    }

    static func getUserId() -> UUID? {
        guard let str = load(forAccount: userIdAccount) else { return nil }
        return UUID(uuidString: str)
    }

    static func deleteUserId() {
        delete(forAccount: userIdAccount)
    }

    private static func save(string: String, forAccount account: String) {
        guard let data = string.data(using: .utf8) else { return }
        delete(forAccount: account)

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func load(forAccount account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(forAccount account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Backend Auth Manager

/// Manages Supabase authenticated identity, secure JWT storage, and student account isolation.
///
/// Security constraints:
/// - Moodle passwords and tokens are NEVER sent to or stored in Supabase.
/// - Authenticated user identity (UUID) governs RLS permissions in PostgreSQL.
final class BackendAuthManager: @unchecked Sendable {
    static let shared = BackendAuthManager()

    private let lock = NSLock()
    private var cachedUserId: UUID?
    private var cachedToken: String?

    var currentUserId: UUID? {
        lock.lock()
        defer { lock.unlock() }
        if let id = cachedUserId { return id }
        if let id = BackendKeychainHelper.getUserId() {
            cachedUserId = id
            return id
        }
        return nil
    }

    var currentAccessToken: String? {
        lock.lock()
        defer { lock.unlock() }
        if let token = cachedToken { return token }
        if let token = BackendKeychainHelper.getToken() {
            cachedToken = token
            return token
        }
        return nil
    }

    var isAuthenticated: Bool {
        currentUserId != nil
    }

    private init() {
        cachedUserId = BackendKeychainHelper.getUserId()
        cachedToken = BackendKeychainHelper.getToken()
    }

    /// Associates an authenticated backend session with an explicit user identity and access token.
    func setSession(userId: UUID, accessToken: String) {
        lock.lock()
        defer { lock.unlock() }

        cachedUserId = userId
        cachedToken = accessToken
        BackendKeychainHelper.saveUserId(userId)
        BackendKeychainHelper.saveToken(accessToken)
    }

    /// Derives a cryptographically stable, isolated UUID for a student Moodle account.
    /// This provides strong user isolation on device and maps predictably to the user's personal cloud partition.
    static func deterministicUserId(forAccount accountId: String) -> UUID {
        let clean = accountId.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let namespace = "edu.kiet.assignementradar.user."
        let combined = namespace + clean

        let hash = SHA256.hash(data: Data(combined.utf8))
        var bytes = Array(hash.prefix(16))

        // Set UUID version 5 (or 4 variant) bits for RFC 4122 compliance
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // version 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // variant RFC 4122

        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    /// Configures identity when a student signs into Moodle.
    /// Uses deterministic RFC 4122 derivation to isolate student completion states.
    func bindMoodleAccount(accountId: String) -> UUID {
        let derived = Self.deterministicUserId(forAccount: accountId)
        lock.lock()
        defer { lock.unlock() }

        cachedUserId = derived
        BackendKeychainHelper.saveUserId(derived)
        return derived
    }

    /// Clears the backend session on logout.
    func clearSession() {
        lock.lock()
        defer { lock.unlock() }

        cachedUserId = nil
        cachedToken = nil
        BackendKeychainHelper.deleteUserId()
        BackendKeychainHelper.deleteToken()
    }
}
