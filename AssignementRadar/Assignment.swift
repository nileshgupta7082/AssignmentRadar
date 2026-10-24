//
//  Assignment.swift
//  AssignementRadar
//
//  Created for Assignment Radar Milestone 1.
//

import Foundation
import SwiftUI
import SwiftData

/// Represents the priority level of an academic assignment or exam.
enum Priority: String, Codable, CaseIterable, Identifiable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .low:
            return .green
        case .medium:
            return .orange
        case .high:
            return .red
        }
    }
}

/// Smart urgency categories for prioritizing assignments and visual indicators.
enum Urgency: String, CaseIterable, Comparable, Identifiable {
    case overdue = "Overdue"
    case dueSoon = "Due Soon"
    case upcoming = "Upcoming"
    case later = "Later"
    case completed = "Completed"

    var id: String { rawValue }

    /// Sort rank: 0 (Overdue) -> 1 (Due Soon) -> 2 (Upcoming) -> 3 (Later) -> 4 (Completed)
    var sortOrder: Int {
        switch self {
        case .overdue: return 0
        case .dueSoon: return 1
        case .upcoming: return 2
        case .later: return 3
        case .completed: return 4
        }
    }

    static func < (lhs: Urgency, rhs: Urgency) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    var color: Color {
        switch self {
        case .overdue: return Color.red
        case .dueSoon: return Color.orange
        case .upcoming: return Color.blue
        case .later: return Color.purple
        case .completed: return Color.green
        }
    }

    var iconName: String {
        switch self {
        case .overdue: return "exclamationmark.triangle.fill"
        case .dueSoon: return "flame.fill"
        case .upcoming: return "clock.badge.exclamationmark"
        case .later: return "calendar"
        case .completed: return "checkmark.circle.fill"
        }
    }
}

/// SwiftData persistent model representing a student's assignment or exam.
@Model
final class Assignment {
    var id: UUID = UUID()
    var title: String = ""
    var course: String = ""
    var dueDate: Date = Date()
    var priorityRaw: String = Priority.medium.rawValue
    var notes: String = ""
    var isCompleted: Bool = false
    var isArchived: Bool = false

    /// Origin of this deadline: "manual", "moodle", or "scan"
    var source: String = "manual"

    /// Unique identifier from Moodle for deduplication
    var moodleEventId: String? = nil

    /// Direct web link to the assignment or course on Moodle
    var sourceUrl: String? = nil

    /// Academic event type: "assignment" or "exam"
    var eventType: String = "assignment"

    /// Examination time slot or session (e.g. "10:00 AM - 01:00 PM")
    var sessionTime: String? = nil

    /// Examination or class venue/room (e.g. "Room 302", "Audi-1")
    var room: String = ""

    /// Preserved OCR snippet or text for audit/inspection
    var rawOcrText: String? = nil

    /// EventKit calendar event identifier for Apple Calendar sync
    var calendarEventId: String? = nil

    /// Account identifier associating Moodle-imported assignments with a specific student account (e.g. username/student ID)
    var accountId: String? = nil

    /// Stable unique task identifier used for persistent cloud backend synchronization (user_task_states).
    /// For Moodle assignments: Uses primary stable `moodleEventId` (e.g. "moodle_12345"), or fallback composite key.
    /// For manual assignments and scanned exams: Uses stable UUID (e.g. "local_<uuid>").
    var stableTaskKey: String {
        Self.makeTaskKey(source: source, moodleEventId: moodleEventId, title: title, course: course, id: id)
    }

    /// Generates a stable task key for any assignment or draft.
    static func makeTaskKey(source: String, moodleEventId: String?, title: String, course: String, id: UUID? = nil) -> String {
        if source == "moodle", let eventId = moodleEventId, !eventId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "moodle_\(eventId.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        if source == "moodle" {
            let cleanCourse = course.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanTitle = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return "moodle_comp_\(cleanCourse)_\(cleanTitle)"
        }
        let uuidStr = (id ?? UUID()).uuidString.lowercased()
        return "local_\(uuidStr)"
    }

    /// Convenient check if this deadline represents an examination
    var isExam: Bool {
        eventType.lowercased() == "exam"
    }

    /// Convenient wrapper to work with the typed `Priority` enum.
    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }

    /// Checks if the assignment has a realistic, valid deadline.
    var hasValidDeadline: Bool {
        dueDate != Date.distantFuture &&
        dueDate != Date.distantPast &&
        dueDate.timeIntervalSince1970 > 86400
    }

    /// Returns the effective date and time for an assignment deadline or examination start time.
    ///
    /// For standard assignments, returns `dueDate`.
    /// For examinations (`isExam == true`):
    /// - Parses the start time from `sessionTime` (e.g. "10:00 AM - 01:00 PM" -> 10:00 AM, NEVER the end time).
    /// - Combines the exam's calendar date (year, month, day from `dueDate`) with the parsed start time.
    /// - If `sessionTime` is missing or unparseable:
    ///     * If `dueDate` has an explicit non-midnight time, `dueDate` is used.
    ///     * Otherwise (e.g. 00:00 midnight / date-only import), falls back to 10:00 AM on the exam date (standard morning session).
    func effectiveEventDate(at calendar: Calendar = .current) -> Date {
        guard isExam else {
            return dueDate
        }

        let startComponents = NotificationService.parseSessionStartTime(from: sessionTime)
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: dueDate)

        if let (hour, minute) = startComponents {
            var combined = dayComponents
            combined.hour = hour
            combined.minute = minute
            combined.second = 0
            return calendar.date(from: combined) ?? dueDate
        }

        // Fallback when sessionTime is missing or unparseable:
        let timeComponents = calendar.dateComponents([.hour, .minute], from: dueDate)
        let isMidnight = (timeComponents.hour == 0 && timeComponents.minute == 0)
        if !isMidnight {
            return dueDate
        }

        // Documented fallback: Standard 10:00 AM academic examination session slot
        var fallbackComponents = dayComponents
        fallbackComponents.hour = 10
        fallbackComponents.minute = 0
        fallbackComponents.second = 0
        return calendar.date(from: fallbackComponents) ?? dueDate
    }

    /// Convenient shorthand for the effective deadline or exam start time in the current calendar.
    var effectiveDate: Date {
        effectiveEventDate()
    }

    /// Checks if the deadline or exam start time has passed and the item is still incomplete.
    var isOverdue: Bool {
        !isCompleted && hasValidDeadline && effectiveDate < Date()
    }

    /// Checks whether this incomplete item is overdue by at least the specified number of days (default 7).
    /// Accurately compares both the current reference date/time and the item's effective due date/time.
    func isOverdueBy(days: Int = 7, referenceDate: Date = Date(), in calendar: Calendar = .current) -> Bool {
        guard !isCompleted && hasValidDeadline else { return false }
        let targetDate = effectiveEventDate(at: calendar)
        guard targetDate < referenceDate else { return false }
        let interval = referenceDate.timeIntervalSince(targetDate)
        return interval >= Double(days) * 86400.0
    }

    /// Convenience wrapper checking if the item is overdue by more than the specified number of days.
    func isOverdueByMoreThan(days: Int = 7, referenceDate: Date = Date(), in calendar: Calendar = .current) -> Bool {
        isOverdueBy(days: days, referenceDate: referenceDate, in: calendar)
    }

    /// Evaluates smart urgency based on completion status, effective deadline/exam start, and reference time.
    func urgency(at referenceDate: Date = Date(), in calendar: Calendar = .current) -> Urgency {
        if isCompleted {
            return .completed
        }
        guard hasValidDeadline else {
            return .later
        }
        let targetDate = effectiveEventDate(at: calendar)
        if targetDate < referenceDate {
            return .overdue
        }
        let interval = targetDate.timeIntervalSince(referenceDate)
        if interval <= 24 * 3600 {
            return .dueSoon
        } else if interval <= 3 * 86400 {
            return .upcoming
        } else {
            return .later
        }
    }

    /// Sorting comparator prioritizing:
    /// 1. Overdue incomplete assignments/exams
    /// 2. Due soon (<24h)
    /// 3. Upcoming (<3d)
    /// 4. Later (>3d, including items without specific deadlines)
    /// 5. Completed assignments/exams
    /// Within each urgency level, items are sorted by effective event date ascending.
    static func urgencySortComparator(a: Assignment, b: Assignment, referenceDate: Date = Date(), calendar: Calendar = .current) -> Bool {
        let uA = a.urgency(at: referenceDate, in: calendar)
        let uB = b.urgency(at: referenceDate, in: calendar)
        if uA.sortOrder != uB.sortOrder {
            return uA.sortOrder < uB.sortOrder
        }
        // Place items with valid deadlines before items without deadlines
        if a.hasValidDeadline != b.hasValidDeadline {
            return a.hasValidDeadline && !b.hasValidDeadline
        }
        let dateA = a.effectiveEventDate(at: calendar)
        let dateB = b.effectiveEventDate(at: calendar)
        if dateA != dateB {
            return dateA < dateB
        }
        return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
    }

    init(
        title: String = "",
        course: String = "",
        dueDate: Date = Date(),
        priority: Priority = .medium,
        notes: String = "",
        isCompleted: Bool = false,
        isArchived: Bool = false,
        source: String = "manual",
        moodleEventId: String? = nil,
        sourceUrl: String? = nil,
        eventType: String = "assignment",
        sessionTime: String? = nil,
        room: String = "",
        rawOcrText: String? = nil,
        calendarEventId: String? = nil,
        accountId: String? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.course = course
        self.dueDate = dueDate
        self.priorityRaw = priority.rawValue
        self.notes = notes
        self.isCompleted = isCompleted
        self.isArchived = isArchived
        self.source = source
        self.moodleEventId = moodleEventId
        self.sourceUrl = sourceUrl
        self.eventType = eventType
        self.sessionTime = sessionTime
        self.room = room
        self.rawOcrText = rawOcrText
        self.calendarEventId = calendarEventId
        self.accountId = accountId
    }
}
