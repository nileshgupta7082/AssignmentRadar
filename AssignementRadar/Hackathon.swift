//
//  Hackathon.swift
//  AssignementRadar
//
//  Created for Assignment Radar Hackathon & Competition Tracking.
//

import Foundation
import SwiftUI
import SwiftData

/// Event participation mode for hackathons and coding competitions.
enum HackathonMode: String, Codable, CaseIterable, Identifiable {
    case online = "Online"
    case offline = "Offline"
    case hybrid = "Hybrid"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .online: return "globe"
        case .offline: return "building.2.fill"
        case .hybrid: return "person.2.badge.gearshape.fill"
        }
    }
}

/// Dynamic event status derived from event dates and completion state.
enum HackathonStatus: String, CaseIterable, Identifiable {
    case upcoming = "Upcoming"
    case regClosingSoon = "Reg Closing Soon"
    case ongoing = "Ongoing"
    case completed = "Completed"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .upcoming: return .blue
        case .regClosingSoon: return .orange
        case .ongoing: return .green
        case .completed: return .purple
        }
    }

    var iconName: String {
        switch self {
        case .upcoming: return "calendar"
        case .regClosingSoon: return "flame.fill"
        case .ongoing: return "bolt.fill"
        case .completed: return "checkmark.seal.fill"
        }
    }
}

/// SwiftData persistent model for tracking hackathons and competitions.
@Model
final class Hackathon {
    var id: UUID = UUID()
    var title: String = ""
    var organizer: String = ""
    var startDate: Date? = nil
    var registrationDeadline: Date? = nil
    var endDate: Date? = nil
    var modeRaw: String = HackathonMode.online.rawValue
    var location: String = ""
    var websiteUrl: String = ""
    var eventDescription: String = ""
    var source: String = "local"
    var isAttendedOrCompleted: Bool = false
    var createdAt: Date = Date()

    /// Distinguishes project/round submission deadline from registration deadline and event start date
    var submissionDeadline: Date? = nil

    /// User's participation or registration status (e.g., "Registered", "Submitted", "Participated")
    var participationStatus: String? = nil

    /// Timestamp of last successful synchronization with remote platform
    var lastSyncedAt: Date? = nil

    /// Source of entry: "manual" or other local origin
    var importSource: String? = nil

    /// Timestamp when this event was created or imported
    var importedAt: Date? = nil

    /// True if user manually customized or edited fields
    var isManuallyEdited: Bool = false

    /// Snippet or raw text from which the event was extracted for user reference
    var rawImportSnippet: String? = nil

    var mode: HackathonMode {
        get { HackathonMode(rawValue: modeRaw) ?? .online }
        set { modeRaw = newValue.rawValue }
    }

    /// User-friendly label describing where this event originated
    var importSourceDisplayName: String {
        return "Manual Entry"
    }

    /// System SF Symbol icon matching the event's origin
    var importSourceIconName: String {
        return "pencil"
    }

    /// Evaluates dynamic status based on dates and user completion state.
    func status(at referenceDate: Date = Date()) -> HackathonStatus {
        if isAttendedOrCompleted {
            return .completed
        }

        // If end date has passed, it's completed
        if let end = endDate, end < referenceDate {
            return .completed
        }

        // If ongoing (between start and end date)
        if let start = startDate, let end = endDate, referenceDate >= start && referenceDate <= end {
            return .ongoing
        }

        // If registration deadline is closing soon (within 48 hours)
        if let reg = registrationDeadline, reg > referenceDate {
            let interval = reg.timeIntervalSince(referenceDate)
            if interval <= 48 * 3600 {
                return .regClosingSoon
            }
        }

        return .upcoming
    }

    var eventStartDate: Date {
        startDate ?? Date.distantFuture
    }

    var eventUrl: String? {
        websiteUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : websiteUrl
    }

    var formattedEventDate: String {
        guard let start = startDate else { return "Date TBD" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: start)
    }

    func countdownLabel(at referenceDate: Date = Date()) -> String {
        let currentStatus = status(at: referenceDate)
        if currentStatus == .completed { return "Completed" }
        if currentStatus == .ongoing { return "Live Now" }
        if currentStatus == .regClosingSoon { return "Reg Closing Soon" }

        guard let target = startDate ?? registrationDeadline else { return "Upcoming" }
        let interval = target.timeIntervalSince(referenceDate)
        guard interval > 0 else { return "Live Now" }
        let days = Int(interval) / 86400
        let hours = (Int(interval) % 86400) / 3600
        if days > 0 {
            return "Starts in \(days)d \(hours)h"
        } else {
            let minutes = max(1, Int(interval) / 60)
            return "Starts in \(minutes)m"
        }
    }

    init(
        title: String = "",
        organizer: String = "",
        startDate: Date? = nil,
        registrationDeadline: Date? = nil,
        submissionDeadline: Date? = nil,
        endDate: Date? = nil,
        mode: HackathonMode = .online,
        location: String = "",
        websiteUrl: String = "",
        eventDescription: String = "",
        source: String = "local",
        participationStatus: String? = nil,
        lastSyncedAt: Date? = nil,
        isAttendedOrCompleted: Bool = false,
        importSource: String? = nil,
        importedAt: Date? = nil,
        isManuallyEdited: Bool = false,
        rawImportSnippet: String? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.organizer = organizer
        self.startDate = startDate
        self.registrationDeadline = registrationDeadline
        self.submissionDeadline = submissionDeadline
        self.endDate = endDate
        self.modeRaw = mode.rawValue
        self.location = location
        self.websiteUrl = websiteUrl
        self.eventDescription = eventDescription
        self.source = source
        self.participationStatus = participationStatus
        self.lastSyncedAt = lastSyncedAt
        self.isAttendedOrCompleted = isAttendedOrCompleted
        self.importSource = importSource
        self.importedAt = importedAt
        self.isManuallyEdited = isManuallyEdited
        self.rawImportSnippet = rawImportSnippet
        self.createdAt = Date()
    }
}
