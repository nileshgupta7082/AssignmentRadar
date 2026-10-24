//
//  CodingTask.swift
//  AssignementRadar
//
//  Created for Coding Radar Workspace & Task Management.
//

import Foundation
import SwiftData

// MARK: - Task Type

/// Distinct categories of competitive programming tasks and events.
enum CodingTaskType: String, Codable, CaseIterable, Identifiable {
    case dailyQuestion = "Daily Question"
    case practiceProblem = "Practice Problem"
    case contest = "Contest"
    case hackathon = "Hackathon"
    case workshop = "Workshop"
    case custom = "Custom"
    case registrationDeadline = "Registration Deadline"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .dailyQuestion: return "calendar.badge.clock"
        case .practiceProblem: return "chevron.left.forwardslash.chevron.right"
        case .contest: return "trophy"
        case .hackathon: return "laptopcomputer.and.arrow.down"
        case .workshop: return "person.3.sequence"
        case .registrationDeadline: return "hourglass"
        case .custom: return "checklist"
        }
    }
}

// MARK: - Event Type for Manual Events

/// Distinct categories for manual coding events and hackathons.
enum CodingEventType: String, Codable, CaseIterable, Identifiable {
    case hackathon = "Hackathon"
    case codingContest = "Coding Contest"
    case workshop = "Workshop"
    case custom = "Custom"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .hackathon: return "laptopcomputer.and.arrow.down"
        case .codingContest: return "trophy"
        case .workshop: return "person.3.sequence"
        case .custom: return "calendar"
        }
    }

    var matchingTaskType: CodingTaskType {
        switch self {
        case .hackathon: return .hackathon
        case .codingContest: return .contest
        case .workshop: return .workshop
        case .custom: return .custom
        }
    }
}

// MARK: - Contest Registration Status

/// Explicit registration status for a competitive programming contest or event.
/// Only the `.registered` state qualifies for contest-day and 15-minute reminders.
enum ContestRegistrationStatus: String, Codable, CaseIterable, Identifiable {
    case interested = "Interested"
    case registered = "Registered"
    case notParticipating = "Not Participating"
    case completed = "Completed"
    case cancelled = "Cancelled"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .interested: return "star"
        case .registered: return "checkmark.seal.fill"
        case .notParticipating: return "slash.circle"
        case .completed: return "flag.checkered"
        case .cancelled: return "xmark.circle"
        }
    }
}

// MARK: - Coding Task Model

/// SwiftData persistent model representing a competitive programming problem, contest, or goal.
/// Completely decoupled from academic assignments and Moodle sessions.
@Model
final class CodingTask {
    var id: UUID = UUID()
    var title: String = ""
    var platformId: String = "custom"
    var platformName: String = "Custom"
    var taskTypeRaw: String = CodingTaskType.practiceProblem.rawValue
    var registrationStatusRaw: String = ContestRegistrationStatus.interested.rawValue
    var difficulty: String? = nil
    var topicTags: String? = nil
    var startDate: Date? = nil
    var dueDate: Date? = nil
    var officialUrl: String? = nil
    var notes: String = ""
    var isCompleted: Bool = false
    var completedAt: Date? = nil
    var createdAt: Date = Date()

    // MARK: - Event & Integration Fields
    var endDate: Date? = nil
    var registrationDeadline: Date? = nil
    var submissionDeadline: Date? = nil
    var calendarEventId: String? = nil
    var isManualEvent: Bool = false
    var providerEventId: String? = nil

    var taskType: CodingTaskType {
        get { CodingTaskType(rawValue: taskTypeRaw) ?? .practiceProblem }
        set { taskTypeRaw = newValue.rawValue }
    }

    var registrationStatus: ContestRegistrationStatus {
        get { ContestRegistrationStatus(rawValue: registrationStatusRaw) ?? .interested }
        set { registrationStatusRaw = newValue.rawValue }
    }

    var isContest: Bool {
        taskType == .contest
    }

    var isRegisteredForContest: Bool {
        isContest && registrationStatus == .registered
    }

    var isDailyQuestion: Bool {
        taskType == .dailyQuestion
    }

    var isEvent: Bool {
        isManualEvent || taskType == .hackathon || taskType == .workshop || (taskType == .custom && (startDate != nil || endDate != nil))
    }

    /// Next relevant chronological date for sorting upcoming events
    var nextRelevantDate: Date {
        let now = Date()
        let futureMilestones = [startDate, registrationDeadline, submissionDeadline, dueDate]
            .compactMap { $0 }
            .filter { $0 > now }
        if let earliest = futureMilestones.min() {
            return earliest
        }
        return startDate ?? dueDate ?? createdAt
    }

    var isOverdue: Bool {
        guard !isCompleted else { return false }
        if let d = dueDate {
            return d < Date()
        }
        return false
    }

    /// Formatted concise deadline or event time string.
    var formattedTimeline: String? {
        if isContest || isEvent, let start = startDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "d MMM · h:mm a"
            let now = Date()
            if start > now {
                let interval = start.timeIntervalSince(now)
                let hours = Int(interval) / 3600
                let days = hours / 24
                if days > 0 {
                    return "Starts in \(days)d \(hours % 24)h · \(formatter.string(from: start))"
                } else if hours > 0 {
                    return "Starts in \(hours)h · \(formatter.string(from: start))"
                } else {
                    let mins = max(1, Int(interval) / 60)
                    return "Starts in \(mins)m · \(formatter.string(from: start))"
                }
            } else {
                return "Started · \(formatter.string(from: start))"
            }
        }

        if let due = dueDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "d MMM · h:mm a"
            if due < Date() {
                return "Overdue · \(formatter.string(from: due))"
            }
            return "Due \(formatter.string(from: due))"
        }

        return nil
    }

    init(
        title: String = "",
        platformId: String = "custom",
        platformName: String = "Custom",
        taskType: CodingTaskType = .practiceProblem,
        registrationStatus: ContestRegistrationStatus = .interested,
        difficulty: String? = nil,
        topicTags: String? = nil,
        startDate: Date? = nil,
        dueDate: Date? = nil,
        endDate: Date? = nil,
        registrationDeadline: Date? = nil,
        submissionDeadline: Date? = nil,
        officialUrl: String? = nil,
        notes: String = "",
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        calendarEventId: String? = nil,
        isManualEvent: Bool = false,
        providerEventId: String? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.platformId = platformId
        self.platformName = platformName
        self.taskTypeRaw = taskType.rawValue
        self.registrationStatusRaw = registrationStatus.rawValue
        self.difficulty = difficulty
        self.topicTags = topicTags
        self.startDate = startDate
        self.dueDate = dueDate
        self.endDate = endDate
        self.registrationDeadline = registrationDeadline
        self.submissionDeadline = submissionDeadline
        self.officialUrl = officialUrl
        self.notes = notes
        self.isCompleted = isCompleted
        self.completedAt = completedAt ?? (isCompleted ? Date() : nil)
        self.createdAt = Date()
        self.calendarEventId = calendarEventId
        self.isManualEvent = isManualEvent
        self.providerEventId = providerEventId
    }

    convenience init(
        title: String = "",
        platformId: String = "custom",
        platformName: String = "Custom",
        taskType: CodingTaskType = .practiceProblem,
        registrationStatus: ContestRegistrationStatus = .interested,
        difficulty: String? = nil,
        topicTags: String? = nil,
        startDate: Date? = nil,
        dueDate: Date? = nil,
        officialUrl: String? = nil,
        notes: String = "",
        isCompleted: Bool = false
    ) {
        self.init(
            title: title,
            platformId: platformId,
            platformName: platformName,
            taskType: taskType,
            registrationStatus: registrationStatus,
            difficulty: difficulty,
            topicTags: topicTags,
            startDate: startDate,
            dueDate: dueDate,
            endDate: nil,
            registrationDeadline: nil,
            submissionDeadline: nil,
            officialUrl: officialUrl,
            notes: notes,
            isCompleted: isCompleted,
            calendarEventId: nil,
            isManualEvent: false,
            providerEventId: nil
        )
    }
}
