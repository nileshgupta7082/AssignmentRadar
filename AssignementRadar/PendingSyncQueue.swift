//
//  PendingSyncQueue.swift
//  AssignementRadar
//
//  Created for Offline Queue & Resilient Synchronization.
//

import Foundation

/// Persistent offline queue for unsynchronized task state mutations.
/// Guarantees that student completion updates survive app termination, offline usage, and temporary network dropouts.
final class PendingSyncQueue: @unchecked Sendable {
    static let shared = PendingSyncQueue()

    private let defaults = UserDefaults.standard
    private let queueKey = "pending_task_sync_queue_v1"
    private let lock = NSLock()

    private init() {}

    /// Enqueues an upsert mutation idempotently.
    /// If an item with the same (userId, taskKey) is already pending, it is replaced with the newer record.
    func enqueueUpsert(_ record: UserTaskStateRecord) {
        lock.lock()
        defer { lock.unlock() }

        var items = loadQueueItemsUnsafe()
        if let index = items.firstIndex(where: { $0.userId == record.userId && $0.taskKey == record.taskKey }) {
            // Retain the newer version or timestamp
            if record.updatedAt >= items[index].updatedAt {
                items[index] = record
            }
        } else {
            items.append(record)
        }
        saveQueueItemsUnsafe(items)
    }

    /// Removes an item once confirmed by the backend.
    func remove(userId: UUID, taskKey: String) {
        lock.lock()
        defer { lock.unlock() }

        var items = loadQueueItemsUnsafe()
        items.removeAll(where: { $0.userId == userId && $0.taskKey == taskKey })
        saveQueueItemsUnsafe(items)
    }

    /// Retrieves all pending items, optionally filtered by user ID.
    func pendingItems(for userId: UUID? = nil) -> [UserTaskStateRecord] {
        lock.lock()
        defer { lock.unlock() }

        let items = loadQueueItemsUnsafe()
        if let uid = userId {
            return items.filter { $0.userId == uid }
        }
        return items
    }

    /// Number of items pending synchronization.
    func count(for userId: UUID? = nil) -> Int {
        pendingItems(for: userId).count
    }

    /// Clears the queue, optionally for a specific user.
    func clear(for userId: UUID? = nil) {
        lock.lock()
        defer { lock.unlock() }

        if let uid = userId {
            var items = loadQueueItemsUnsafe()
            items.removeAll(where: { $0.userId == uid })
            saveQueueItemsUnsafe(items)
        } else {
            saveQueueItemsUnsafe([])
        }
    }

    // MARK: - Private Helpers (Must be called while holding lock)

    private func loadQueueItemsUnsafe() -> [UserTaskStateRecord] {
        guard let data = defaults.data(forKey: queueKey),
              let list = try? JSONDecoder().decode([UserTaskStateRecord].self, from: data) else {
            return []
        }
        return list
    }

    private func saveQueueItemsUnsafe(_ items: [UserTaskStateRecord]) {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: queueKey)
        }
    }
}
