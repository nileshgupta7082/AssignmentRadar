//
//  CodingActivityRecord.swift
//  AssignementRadar
//
//  Created for Smart Coding Streak & Unified Activity Tracking.
//

import Foundation
import SwiftData

// MARK: - Verification Source

/// Distinguishes between automated provider-synced submissions and user-confirmed completions.
enum ActivityVerificationSource: String, Codable, CaseIterable {
    case providerSynced = "Provider Synced"
    case userConfirmed = "User Confirmed"
}

// MARK: - Unified Coding Activity SwiftData Model

/// Persistent model representing a completed coding challenge, practice problem, or contest task.
/// Any eligible record counts toward the user's daily coding streak.
@Model
final class CodingActivityRecord {
    var id: UUID = UUID()
    var platformId: String = "custom"
    var platformName: String = "Custom"
    var problemTitle: String = ""
    var problemId: String? = nil
    var completedAt: Date = Date()
    var verificationSourceRaw: String = ActivityVerificationSource.userConfirmed.rawValue
    var problemUrl: String? = nil
    var difficulty: String? = nil
    var topicTags: String? = nil
    var providerSubmissionId: String? = nil
    var notes: String = ""
    var createdAt: Date = Date()

    var verificationSource: ActivityVerificationSource {
        get { ActivityVerificationSource(rawValue: verificationSourceRaw) ?? .userConfirmed }
        set { verificationSourceRaw = newValue.rawValue }
    }

    init(
        platformId: String = "custom",
        platformName: String = "Custom",
        problemTitle: String,
        problemId: String? = nil,
        completedAt: Date = Date(),
        verificationSource: ActivityVerificationSource = .userConfirmed,
        problemUrl: String? = nil,
        difficulty: String? = nil,
        topicTags: String? = nil,
        providerSubmissionId: String? = nil,
        notes: String = ""
    ) {
        self.id = UUID()
        self.platformId = platformId
        self.platformName = platformName
        self.problemTitle = problemTitle
        self.problemId = problemId
        self.completedAt = completedAt
        self.verificationSourceRaw = verificationSource.rawValue
        self.problemUrl = problemUrl
        self.difficulty = difficulty
        self.topicTags = topicTags
        self.providerSubmissionId = providerSubmissionId
        self.notes = notes
        self.createdAt = Date()
    }
}
