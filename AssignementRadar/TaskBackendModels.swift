//
//  TaskBackendModels.swift
//  AssignementRadar
//
//  Created for Assignment Radar Cloud Backend & Task State Synchronization.
//

import Foundation
import SwiftUI

// MARK: - Task Sync Status

/// User-facing and internal status of cloud synchronization.
enum TaskSyncStatus: Equatable {
    case synced
    case syncing
    case offline(pendingCount: Int)
    case error(message: String)

    var displayText: String {
        switch self {
        case .synced:
            return "Cloud Synced"
        case .syncing:
            return "Syncing..."
        case .offline(let count):
            return count > 0 ? "Offline (\(count) pending)" : "Offline"
        case .error(let msg):
            return "Sync Issue: \(msg)"
        }
    }

    var iconName: String {
        switch self {
        case .synced:
            return "icloud.fill"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .offline:
            return "icloud.slash"
        case .error:
            return "exclamationmark.icloud"
        }
    }

    var iconColor: Color {
        switch self {
        case .synced:
            return Color.green
        case .syncing:
            return Color.blue
        case .offline:
            return Color.orange
        case .error:
            return Color.red
        }
    }
}

// MARK: - User Task State Record (PostgreSQL / Supabase Schema)

/// Persistent data record corresponding to `public.user_task_states` in Supabase PostgreSQL.
/// Encapsulates personal task completion, archive state, notes, and priority overrides
/// without duplicating server-owned course/assignment metadata.
struct UserTaskStateRecord: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var userId: UUID
    var taskKey: String
    var source: String
    var sourceAccountKey: String?
    var isCompleted: Bool
    var isArchived: Bool
    var priorityOverride: String?
    var notes: String?
    var updatedAt: Date
    var version: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case taskKey = "task_key"
        case source
        case sourceAccountKey = "source_account_key"
        case isCompleted = "is_completed"
        case isArchived = "is_archived"
        case priorityOverride = "priority_override"
        case notes
        case updatedAt = "updated_at"
        case version
    }

    init(
        id: UUID = UUID(),
        userId: UUID,
        taskKey: String,
        source: String = "moodle",
        sourceAccountKey: String? = nil,
        isCompleted: Bool = false,
        isArchived: Bool = false,
        priorityOverride: String? = nil,
        notes: String? = nil,
        updatedAt: Date = Date(),
        version: Int = 1
    ) {
        self.id = id
        self.userId = userId
        self.taskKey = taskKey
        self.source = source
        self.sourceAccountKey = sourceAccountKey
        self.isCompleted = isCompleted
        self.isArchived = isArchived
        self.priorityOverride = priorityOverride
        self.notes = notes
        self.updatedAt = updatedAt
        self.version = version
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.userId = try container.decode(UUID.self, forKey: .userId)
        self.taskKey = try container.decode(String.self, forKey: .taskKey)
        self.source = try container.decodeIfPresent(String.self, forKey: .source) ?? "moodle"
        self.sourceAccountKey = try container.decodeIfPresent(String.self, forKey: .sourceAccountKey)
        self.isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        self.isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        self.priorityOverride = try container.decodeIfPresent(String.self, forKey: .priorityOverride)
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes)
        self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1

        if let dateString = try? container.decode(String.self, forKey: .updatedAt) {
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFormatter.date(from: dateString) {
                self.updatedAt = date
            } else {
                let standardFormatter = ISO8601DateFormatter()
                self.updatedAt = standardFormatter.date(from: dateString) ?? Date()
            }
        } else if let date = try? container.decode(Date.self, forKey: .updatedAt) {
            self.updatedAt = date
        } else {
            self.updatedAt = Date()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(taskKey, forKey: .taskKey)
        try container.encode(source, forKey: .source)
        try container.encode(sourceAccountKey, forKey: .sourceAccountKey)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encode(isArchived, forKey: .isArchived)
        try container.encode(priorityOverride, forKey: .priorityOverride)
        try container.encode(notes, forKey: .notes)
        try container.encode(version, forKey: .version)

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let dateString = isoFormatter.string(from: updatedAt)
        try container.encode(dateString, forKey: .updatedAt)
    }
}
