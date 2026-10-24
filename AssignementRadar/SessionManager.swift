//
//  SessionManager.swift
//  AssignementRadar
//
//  Created for Moodle Session and Authentication Lifecycle Management.
//

import SwiftUI
import SwiftData
import Combine

// MARK: - Moodle Account Task Store (Completion & Customization Persistence)

/// Persistent store that tracks local user task state (isCompleted, isArchived, user notes, completion timestamp)
/// per Moodle student account.
///
/// This ensures:
/// 1. If User A completes an assignment, logs out, and logs in again, their completion status is 100% restored upon sync.
/// 2. If User B logs into the device, User A's completion state NEVER leaks into User B's account.
/// 3. Repeated refreshes and relaunches preserve the user's local completion status.
final class MoodleAccountTaskStore {
    static let shared = MoodleAccountTaskStore()

    private let defaults = UserDefaults.standard
    private let storagePrefix = "moodle_task_state_v1_"

    struct TaskState: Codable, Equatable {
        var isCompleted: Bool
        var isArchived: Bool
        var notes: String?
        var completedAt: Date?
        var lastUpdatedAt: Date
    }

    private func storageKey(for accountId: String) -> String {
        return storagePrefix + accountId.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Loads all saved task states for a specific account.
    func loadStates(for accountId: String) -> [String: TaskState] {
        let key = storageKey(for: accountId)
        guard let data = defaults.data(forKey: key),
              let dict = try? JSONDecoder().decode([String: TaskState].self, from: data) else {
            return [:]
        }
        return dict
    }

    /// Saves task states for a specific account.
    private func saveStates(_ states: [String: TaskState], for accountId: String) {
        let key = storageKey(for: accountId)
        if let data = try? JSONEncoder().encode(states) {
            defaults.set(data, forKey: key)
        }
    }

    /// Saves or updates the state for an assignment belonging to an account.
    func saveState(for assignment: Assignment, accountId: String? = nil) {
        let resolvedAccount = (accountId ?? assignment.accountId ?? UserDefaults.standard.string(forKey: SessionManager.moodleAccountIdKey) ?? UserDefaults.standard.string(forKey: SessionManager.moodleUserKey))?
            .lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let acc = resolvedAccount, !acc.isEmpty else { return }

        var states = loadStates(for: acc)

        let state = TaskState(
            isCompleted: assignment.isCompleted,
            isArchived: assignment.isArchived,
            notes: assignment.notes,
            completedAt: assignment.isCompleted ? Date() : nil,
            lastUpdatedAt: Date()
        )

        // Key by stable moodleEventId if available
        if let eventId = assignment.moodleEventId, !eventId.isEmpty {
            states[eventId] = state
        }

        // Also key by composite (course + title) as safe fallback
        let compositeKey = Self.compositeKey(title: assignment.title, course: assignment.course)
        states[compositeKey] = state

        saveStates(states, for: acc)
    }

    /// Retrieves the saved state for a task belonging to an account.
    func getState(accountId: String, eventId: String?, title: String, course: String) -> TaskState? {
        let acc = accountId.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !acc.isEmpty else { return nil }

        let states = loadStates(for: acc)

        // Try primary stable eventId first
        if let eventId = eventId, !eventId.isEmpty, let state = states[eventId] {
            return state
        }

        // Try composite key fallback
        let compKey = Self.compositeKey(title: title, course: course)
        return states[compKey]
    }

    static func compositeKey(title: String, course: String) -> String {
        let cleanTitle = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCourse = course.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return "comp_\(cleanCourse)_\(cleanTitle)"
    }
}

// MARK: - Session Manager

@MainActor
final class SessionManager: ObservableObject {
    static let shared = SessionManager()

    @Published var isAuthenticated: Bool = false
    @Published var isGuestMode: Bool = false

    static let guestSessionKey = "local_guest_session"
    static let moodleUserKey = "moodle_connected_user"
    static let moodleSiteKey = "moodle_connected_site"
    static let moodleLastSyncKey = "moodle_last_sync"
    static let moodleAccountIdKey = "moodle_account_id"

    var currentAccountId: String? {
        let saved = UserDefaults.standard.string(forKey: Self.moodleAccountIdKey)
        if let s = saved, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let user = UserDefaults.standard.string(forKey: Self.moodleUserKey), !user.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return user.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    init() {
        checkSession()
    }

    /// Evaluates current session state based on stored credentials and preferences.
    func checkSession() {
        let token = MoodleKeychainHelper.getToken()
        let user = UserDefaults.standard.string(forKey: Self.moodleUserKey)
        let hasMoodleSession = (token != nil && !(token?.isEmpty ?? true) && user != nil && !(user?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true))
        let isGuest = UserDefaults.standard.bool(forKey: Self.guestSessionKey)

        self.isGuestMode = isGuest && !hasMoodleSession
        self.isAuthenticated = hasMoodleSession || isGuest
    }

    /// Transitions to authenticated state after a successful Moodle sign-in.
    func logInWithMoodle(user: String, site: String, accountId: String? = nil) {
        let resolvedAccount = accountId ?? user
        UserDefaults.standard.set(user, forKey: Self.moodleUserKey)
        UserDefaults.standard.set(site, forKey: Self.moodleSiteKey)
        UserDefaults.standard.set(resolvedAccount.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.moodleAccountIdKey)
        UserDefaults.standard.set(false, forKey: Self.guestSessionKey)
        _ = BackendAuthManager.shared.bindMoodleAccount(accountId: resolvedAccount)
        self.isGuestMode = false
        self.isAuthenticated = true
    }

    /// Continues into local workspace mode without Moodle credentials.
    func continueAsGuest() {
        UserDefaults.standard.set(true, forKey: Self.guestSessionKey)
        self.isGuestMode = true
        self.isAuthenticated = true
    }

    /// Performs safe logout adhering to data-safety rules:
    /// 1. Saves active Moodle assignment completion states to MoodleAccountTaskStore & cloud sync queue.
    /// 2. Removes only confirmed Moodle-owned assignments (source == "moodle") so old student data is not visible.
    /// 3. STRICTLY PRESERVES manually created assignments (source == "manual").
    /// 4. STRICTLY PRESERVES scanned notices and exams (source == "scan" or eventType == "exam").
    /// 5. STRICTLY PRESERVES all local Hackathons.
    /// 6. Clears Keychain token and Moodle user defaults.
    /// 7. Clears backend session and in-memory cache.
    /// 8. Transitions root navigation back to the dedicated login screen.
    func logOut(modelContext: ModelContext) {
        let activeAccountId = currentAccountId

        // Fetch all assignments to inspect ownership safely
        let descriptor = FetchDescriptor<Assignment>()
        if let allAssignments = try? modelContext.fetch(descriptor) {
            for assignment in allAssignments {
                // Delete ONLY items confirmed to originate exclusively from Moodle
                if assignment.source == "moodle" && !assignment.isExam {
                    // Preserve task completion & note state in persistent store before removal
                    if let acc = activeAccountId {
                        MoodleAccountTaskStore.shared.saveState(for: assignment, accountId: acc)
                        TaskSyncCoordinator.shared.recordTaskStateChange(for: assignment, accountId: acc)
                    }
                    NotificationService.shared.cancelReminders(for: assignment.id)
                    if let eventId = assignment.calendarEventId {
                        CalendarSyncService.shared.removeLinkedEvent(withIdentifier: eventId)
                    }
                    modelContext.delete(assignment)
                }
            }
            try? modelContext.save()
        }

        // Clear Keychain credentials securely
        MoodleKeychainHelper.deleteToken()

        // Clear Moodle session preferences
        UserDefaults.standard.removeObject(forKey: Self.moodleUserKey)
        UserDefaults.standard.removeObject(forKey: Self.moodleSiteKey)
        UserDefaults.standard.removeObject(forKey: Self.moodleLastSyncKey)
        UserDefaults.standard.removeObject(forKey: Self.moodleAccountIdKey)
        UserDefaults.standard.removeObject(forKey: Self.guestSessionKey)

        // Clear refresh coordinator state
        RefreshCoordinator.shared.lastRefreshedAt = nil
        RefreshCoordinator.shared.lastStatusMessage = nil

        // Clear backend authentication and sync cache
        TaskSyncCoordinator.shared.clearCache()
        BackendAuthManager.shared.clearSession()

        // Set session state to signed out
        self.isGuestMode = false
        self.isAuthenticated = false
    }
}
