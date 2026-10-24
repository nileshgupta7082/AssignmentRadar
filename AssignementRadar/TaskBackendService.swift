//
//  TaskBackendService.swift
//  AssignementRadar
//
//  Created for Assignment Radar Cloud Backend (Supabase PostgREST Client).
//

import Foundation

// MARK: - Configuration

/// Encapsulates connection parameters for Supabase backend.
/// Only public anon keys are used client-side; service-role keys are strictly prohibited.
struct TaskBackendConfiguration: Sendable {
    let projectUrl: URL?
    let anonKey: String?

    var isConfigured: Bool {
        guard let url = projectUrl, let key = anonKey, !key.isEmpty else {
            return false
        }
        return url.host != nil && !url.absoluteString.contains("YOUR_PROJECT")
    }

    /// Loads configuration from Info.plist or UserDefaults
    static func load() -> TaskBackendConfiguration {
        let bundleDict = Bundle.main.infoDictionary
        let plistUrlStr = (bundleDict?["SUPABASE_URL"] as? String) ?? (bundleDict?["SupabaseURL"] as? String)
        let plistAnonKey = (bundleDict?["SUPABASE_ANON_KEY"] as? String) ?? (bundleDict?["SupabaseAnonKey"] as? String)

        let userUrlStr = UserDefaults.standard.string(forKey: "supabase_custom_url")
        let userAnonKey = UserDefaults.standard.string(forKey: "supabase_custom_anon_key")

        let effectiveUrlStr = userUrlStr ?? plistUrlStr
        let effectiveAnonKey = userAnonKey ?? plistAnonKey

        let url = effectiveUrlStr != nil ? URL(string: effectiveUrlStr!) : nil
        return TaskBackendConfiguration(projectUrl: url, anonKey: effectiveAnonKey)
    }
}

// MARK: - Backend Service Protocol

protocol TaskBackendServiceProtocol: Sendable {
    var isConfigured: Bool { get }
    func fetchTaskStates(userId: UUID, sourceAccountKey: String?) async throws -> [UserTaskStateRecord]
    func upsertTaskState(_ record: UserTaskStateRecord) async throws -> UserTaskStateRecord
    func deleteTaskState(userId: UUID, taskKey: String) async throws
}

// MARK: - Backend Errors

enum TaskBackendError: LocalizedError, Equatable {
    case unconfigured
    case unauthorized
    case networkError(String)
    case serverError(statusCode: Int, message: String)
    case decodingError(String)
    case conflict(String)

    var errorDescription: String? {
        switch self {
        case .unconfigured:
            return "Supabase backend is not configured with a valid project URL and anon key."
        case .unauthorized:
            return "Unauthorized access. A valid authentication session is required."
        case .networkError(let msg):
            return "Network connection error: \(msg)"
        case .serverError(let code, let msg):
            return "Backend server error (\(code)): \(msg)"
        case .decodingError(let msg):
            return "Failed to parse backend response: \(msg)"
        case .conflict(let msg):
            return "Conflict updating task state: \(msg)"
        }
    }
}

// MARK: - Supabase Live Implementation

final class SupabaseTaskBackendService: TaskBackendServiceProtocol, @unchecked Sendable {
    private let config: TaskBackendConfiguration
    private let session: URLSession

    var isConfigured: Bool {
        config.isConfigured
    }

    init(config: TaskBackendConfiguration = .load(), session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func fetchTaskStates(userId: UUID, sourceAccountKey: String?) async throws -> [UserTaskStateRecord] {
        guard let baseUrl = config.projectUrl, let anonKey = config.anonKey else {
            throw TaskBackendError.unconfigured
        }

        var endpointStr = "\(baseUrl.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/rest/v1/user_task_states?user_id=eq.\(userId.uuidString)&select=*"
        if let acc = sourceAccountKey, !acc.isEmpty {
            let encodedAcc = acc.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? acc
            endpointStr += "&source_account_key=eq.\(encodedAcc)"
        }

        guard let endpointUrl = URL(string: endpointStr) else {
            throw TaskBackendError.networkError("Invalid endpoint URL")
        }

        var request = URLRequest(url: endpointUrl)
        request.httpMethod = "GET"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        let token = BackendAuthManager.shared.currentAccessToken ?? anonKey
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TaskBackendError.networkError("Invalid HTTP response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown server error"
            if httpResponse.statusCode == 401 {
                throw TaskBackendError.unauthorized
            }
            throw TaskBackendError.serverError(statusCode: httpResponse.statusCode, message: errorMsg)
        }

        do {
            let records = try JSONDecoder().decode([UserTaskStateRecord].self, from: data)
            return records
        } catch {
            throw TaskBackendError.decodingError(error.localizedDescription)
        }
    }

    func upsertTaskState(_ record: UserTaskStateRecord) async throws -> UserTaskStateRecord {
        guard let baseUrl = config.projectUrl, let anonKey = config.anonKey else {
            throw TaskBackendError.unconfigured
        }

        let endpointStr = "\(baseUrl.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/rest/v1/user_task_states?on_conflict=user_id,task_key"
        guard let endpointUrl = URL(string: endpointStr) else {
            throw TaskBackendError.networkError("Invalid endpoint URL")
        }

        var request = URLRequest(url: endpointUrl)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        let token = BackendAuthManager.shared.currentAccessToken ?? anonKey
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=representation", forHTTPHeaderField: "Prefer")

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(record)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TaskBackendError.networkError("Invalid HTTP response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown server error"
            if httpResponse.statusCode == 401 {
                throw TaskBackendError.unauthorized
            }
            if httpResponse.statusCode == 409 {
                throw TaskBackendError.conflict(errorMsg)
            }
            throw TaskBackendError.serverError(statusCode: httpResponse.statusCode, message: errorMsg)
        }

        // PostgREST returns array of upserted rows with return=representation
        if let returnedList = try? JSONDecoder().decode([UserTaskStateRecord].self, from: data), let first = returnedList.first {
            return first
        }
        return record
    }

    func deleteTaskState(userId: UUID, taskKey: String) async throws {
        guard let baseUrl = config.projectUrl, let anonKey = config.anonKey else {
            throw TaskBackendError.unconfigured
        }

        let endpointStr = "\(baseUrl.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/rest/v1/user_task_states?user_id=eq.\(userId.uuidString)&task_key=eq.\(taskKey)"
        guard let endpointUrl = URL(string: endpointStr) else {
            throw TaskBackendError.networkError("Invalid endpoint URL")
        }

        var request = URLRequest(url: endpointUrl)
        request.httpMethod = "DELETE"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        let token = BackendAuthManager.shared.currentAccessToken ?? anonKey
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TaskBackendError.networkError("Invalid HTTP response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw TaskBackendError.serverError(statusCode: httpResponse.statusCode, message: errorMsg)
        }
    }
}

// MARK: - Mock Implementation for Unit & Regression Testing

final class MockTaskBackendService: TaskBackendServiceProtocol, @unchecked Sendable {
    var isConfigured: Bool = true
    var shouldSimulateNetworkFailure: Bool = false
    var simulatedDelayNanoseconds: UInt64 = 0

    private var storage: [String: UserTaskStateRecord] = [:]
    private let lock = NSLock()

    private func storageKey(userId: UUID, taskKey: String) -> String {
        "\(userId.uuidString)_\(taskKey)"
    }

    func fetchTaskStates(userId: UUID, sourceAccountKey: String?) async throws -> [UserTaskStateRecord] {
        if simulatedDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: simulatedDelayNanoseconds)
        }
        if shouldSimulateNetworkFailure {
            throw TaskBackendError.networkError("Simulated backend offline")
        }

        lock.lock()
        defer { lock.unlock() }

        var results = storage.values.filter { $0.userId == userId }
        if let acc = sourceAccountKey, !acc.isEmpty {
            results = results.filter { $0.sourceAccountKey?.lowercased() == acc.lowercased() }
        }
        return Array(results)
    }

    func upsertTaskState(_ record: UserTaskStateRecord) async throws -> UserTaskStateRecord {
        if simulatedDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: simulatedDelayNanoseconds)
        }
        if shouldSimulateNetworkFailure {
            throw TaskBackendError.networkError("Simulated backend offline")
        }

        lock.lock()
        defer { lock.unlock() }

        let key = storageKey(userId: record.userId, taskKey: record.taskKey)
        var updated = record
        if let existing = storage[key] {
            updated.version = existing.version + 1
        }
        updated.updatedAt = Date()
        storage[key] = updated
        return updated
    }

    func deleteTaskState(userId: UUID, taskKey: String) async throws {
        if simulatedDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: simulatedDelayNanoseconds)
        }
        if shouldSimulateNetworkFailure {
            throw TaskBackendError.networkError("Simulated backend offline")
        }

        lock.lock()
        defer { lock.unlock() }

        let key = storageKey(userId: userId, taskKey: taskKey)
        storage.removeValue(forKey: key)
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }
}
