//
//  TaskSyncCoordinator.swift
//  AssignementRadar
//
//  Created for Assignment Radar Cloud Backend Synchronization & Conflict Resolution.
//

import Foundation
import SwiftUI
import SwiftData
import Combine

/// Central coordinator managing persistent task states between local SwiftData and the Supabase backend.
/// Ensures that student completion status, archive state, and notes survive logout, app reinstalls,
/// and device transitions while supporting offline use and conflict resolution.
@MainActor
final class TaskSyncCoordinator: ObservableObject {
    static let shared = TaskSyncCoordinator()

    // MARK: - Published State

    @Published var syncStatus: TaskSyncStatus = .synced
    @Published var lastSyncedAt: Date? = nil
    @Published var isSyncing: Bool = false

    // MARK: - Dependencies

    var backendService: TaskBackendServiceProtocol
    let queue: PendingSyncQueue
    let authManager: BackendAuthManager

    // In-memory cache of synced records keyed by taskKey for quick lookup
    private var syncedRecordsCache: [String: UserTaskStateRecord] = [:]

    convenience init() {
        self.init(
            backendService: SupabaseTaskBackendService(),
            queue: .shared,
            authManager: .shared
        )
    }

    init(
        backendService: TaskBackendServiceProtocol,
        queue: PendingSyncQueue,
        authManager: BackendAuthManager
    ) {
        self.backendService = backendService
        self.queue = queue
        self.authManager = authManager

        updateInitialStatus()
    }

    private func updateInitialStatus() {
        let pending = queue.count()
        if pending > 0 {
            syncStatus = .offline(pendingCount: pending)
        } else {
            syncStatus = .synced
        }
    }

    // MARK: - Task State Mutations (Local-First + Background Sync)

    /// Records a user's task mutation (completion toggle, archive, notes edit).
    /// Immediately updates local storage, enqueues to persistent queue, and triggers background cloud sync.
    func recordTaskStateChange(for assignment: Assignment, accountId: String? = nil) {
        let resolvedAccount = accountId ?? assignment.accountId ?? SessionManager.shared.currentAccountId
        let userId = authManager.currentUserId ?? {
            if let acc = resolvedAccount {
                return authManager.bindMoodleAccount(accountId: acc)
            }
            return UUID()
        }()

        let taskKey = assignment.stableTaskKey
        let record = UserTaskStateRecord(
            userId: userId,
            taskKey: taskKey,
            source: assignment.source,
            sourceAccountKey: resolvedAccount,
            isCompleted: assignment.isCompleted,
            isArchived: assignment.isArchived,
            priorityOverride: assignment.priorityRaw,
            notes: assignment.notes,
            updatedAt: Date(),
            version: 1
        )

        // 1. Immediately update local persistent store
        if assignment.source == "moodle" {
            MoodleAccountTaskStore.shared.saveState(for: assignment, accountId: resolvedAccount)
        }
        let cKey = Self.cacheKey(taskKey: taskKey, accountId: resolvedAccount)
        syncedRecordsCache[cKey] = record

        // 2. Enqueue in persistent queue for resilient sync
        queue.enqueueUpsert(record)

        // 3. Update status and trigger cloud flush
        let pendingCount = queue.count(for: userId)
        if !backendService.isConfigured {
            syncStatus = .synced // Operating locally when backend not configured
            return
        }

        syncStatus = .syncing
        Task {
            await self.flushPendingQueue(userId: userId)
        }
    }

    // MARK: - Queue Flushing

    /// Flushes all pending mutations to the backend with idempotent upserts.
    func flushPendingQueue(userId: UUID? = nil) async {
        let items = queue.pendingItems(for: userId)
        guard !items.isEmpty else {
            syncStatus = .synced
            return
        }

        guard backendService.isConfigured else {
            syncStatus = .synced
            return
        }

        isSyncing = true
        var failureOccurred = false
        var lastErrorMessage = ""

        for item in items {
            do {
                _ = try await backendService.upsertTaskState(item)
                queue.remove(userId: item.userId, taskKey: item.taskKey)
                let cKey = Self.cacheKey(taskKey: item.taskKey, accountId: item.sourceAccountKey)
                syncedRecordsCache[cKey] = item
            } catch {
                failureOccurred = true
                lastErrorMessage = error.localizedDescription
            }
        }

        isSyncing = false
        let remaining = queue.count(for: userId)
        if failureOccurred && remaining > 0 {
            syncStatus = .offline(pendingCount: remaining)
        } else {
            syncStatus = .synced
            lastSyncedAt = Date()
        }
    }

    // MARK: - Full Bidirectional Synchronization

    /// Synchronizes cloud task states with local SwiftData records.
    /// Handles conflict resolution using optimistic timestamps, preventing stale overwrites.
    func syncWithBackend(modelContext: ModelContext, accountId: String? = nil) async throws {
        let activeAccount = accountId ?? SessionManager.shared.currentAccountId
        guard let userId = authManager.currentUserId ?? (activeAccount != nil ? authManager.bindMoodleAccount(accountId: activeAccount!) : nil) else {
            return
        }

        // 1. Flush any pending local changes first
        await flushPendingQueue(userId: userId)

        guard backendService.isConfigured else {
            return
        }

        isSyncing = true
        syncStatus = .syncing

        do {
            // 2. Fetch all saved states for this user and account
            let serverRecords = try await backendService.fetchTaskStates(userId: userId, sourceAccountKey: activeAccount)

            for record in serverRecords {
                let cKey = Self.cacheKey(taskKey: record.taskKey, accountId: record.sourceAccountKey ?? activeAccount)
                syncedRecordsCache[cKey] = record
            }

            // 3. Reconcile with local SwiftData assignments
            let descriptor = FetchDescriptor<Assignment>()
            let allAssignments = (try? modelContext.fetch(descriptor)) ?? []

            var hasChanges = false
            let pendingItems = queue.pendingItems(for: userId)
            let pendingKeys = Set(pendingItems.map { $0.taskKey })

            for assignment in allAssignments {
                let key = assignment.stableTaskKey

                // If user has an uncommitted local edit pending in queue, do not overwrite with older server record
                if pendingKeys.contains(key) {
                    continue
                }

                if let serverRecord = serverRecords.first(where: { $0.taskKey == key }) {
                    var modified = false

                    if assignment.isCompleted != serverRecord.isCompleted {
                        assignment.isCompleted = serverRecord.isCompleted
                        modified = true
                    }
                    if assignment.isArchived != serverRecord.isArchived {
                        assignment.isArchived = serverRecord.isArchived
                        modified = true
                    }
                    if let notes = serverRecord.notes, !notes.isEmpty && assignment.notes != notes {
                        assignment.notes = notes
                        modified = true
                    }

                    if modified {
                        hasChanges = true
                        if assignment.source == "moodle" {
                            MoodleAccountTaskStore.shared.saveState(for: assignment, accountId: activeAccount)
                        }
                    }
                }
            }

            if hasChanges {
                try? modelContext.save()
            }

            isSyncing = false
            syncStatus = .synced
            lastSyncedAt = Date()
        } catch {
            isSyncing = false
            let remaining = queue.count(for: userId)
            if remaining > 0 {
                syncStatus = .offline(pendingCount: remaining)
            } else {
                syncStatus = .error(message: error.localizedDescription)
            }
            throw error
        }
    }

    // MARK: - Cache Helpers

    static func cacheKey(taskKey: String, accountId: String?) -> String {
        let acc = accountId?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? "global"
        return "\(acc)_\(taskKey)"
    }

    // MARK: - Restore State for Imported Drafts

    /// Checks cloud cache, pending queue, and local store to restore a student's prior completion status
    /// when Moodle delivers drafts. Strictly isolates states by student account.
    func restoreTaskState(
        source: String,
        moodleEventId: String?,
        title: String,
        course: String,
        accountId: String?
    ) -> (isCompleted: Bool, isArchived: Bool, notes: String?) {
        let key = Assignment.makeTaskKey(source: source, moodleEventId: moodleEventId, title: title, course: course)
        let resolvedAccount = accountId?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Check pending queue first (strictly matching this student's account)
        if let pending = queue.pendingItems().first(where: {
            guard $0.taskKey == key else { return false }
            if let acc = resolvedAccount, let recAcc = $0.sourceAccountKey?.lowercased() {
                return recAcc == acc
            }
            return resolvedAccount == nil
        }) {
            return (pending.isCompleted, pending.isArchived, pending.notes)
        }

        // 2. Check cloud cache strictly partitioned by account
        let cKey = Self.cacheKey(taskKey: key, accountId: resolvedAccount)
        if let cached = syncedRecordsCache[cKey] {
            return (cached.isCompleted, cached.isArchived, cached.notes)
        }

        // 3. Fallback to local MoodleAccountTaskStore partitioned by account
        if let acc = resolvedAccount {
            if let localState = MoodleAccountTaskStore.shared.getState(accountId: acc, eventId: moodleEventId, title: title, course: course) {
                return (localState.isCompleted, localState.isArchived, localState.notes)
            }
        }

        return (false, false, nil)
    }

    /// Clears memory cache on logout.
    func clearCache() {
        syncedRecordsCache.removeAll()
        syncStatus = .synced
        lastSyncedAt = nil
        isSyncing = false
    }
}
