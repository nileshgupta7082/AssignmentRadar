//
//  CalendarSyncService.swift
//  AssignementRadar
//
//  Created for Assignment Radar Apple Calendar Integration via EventKit.
//

import Foundation
import EventKit
import SwiftData
import SwiftUI
import Combine

// MARK: - Calendar Authorization Status

enum CalendarAuthStatus: String {
    case notDetermined = "Not Determined"
    case authorized = "Authorized"
    case denied = "Denied"
    case restricted = "Restricted"
    case fullAccess = "Full Access"
    case writeOnly = "Write Only"
    case unknown = "Unknown"

    var isPermitted: Bool {
        self == .authorized || self == .fullAccess || self == .writeOnly
    }
}

// MARK: - Calendar Sync Protocol for Dependency Injection & Unit Testing

enum CalendarSyncActionStatus: String {
    case added = "Added"
    case updated = "Updated"
    case skipped = "Skipped"
    case failed = "Failed"
}

struct CalendarSyncSummary {
    var added: Int = 0
    var updated: Int = 0
    var skipped: Int = 0
    var failed: Int = 0
    var destinationCalendarName: String = "Apple Calendar"
    var firstErrorMessage: String? = nil

    var isSuccess: Bool {
        failed == 0
    }

    var resultMessage: String {
        if failed > 0 {
            let detail = firstErrorMessage != nil ? "\n\(firstErrorMessage!)" : ""
            return "Sync encountered issues: \(added) added, \(updated) updated, \(skipped) skipped, \(failed) failed.\(detail)"
        } else if added == 0 && updated == 0 {
            return "All \(skipped) active deadline\(skipped == 1 ? " is" : "s are") already up-to-date in \"\(destinationCalendarName)\"."
        } else {
            var parts: [String] = []
            if added > 0 { parts.append("\(added) added") }
            if updated > 0 { parts.append("\(updated) updated") }
            if skipped > 0 { parts.append("\(skipped) up to date") }
            return "Successfully synced to \"\(destinationCalendarName)\": \(parts.joined(separator: ", "))."
        }
    }
}

// MARK: - Completed Deadlines Behavior

enum CalendarCompletedBehavior: String, CaseIterable, Identifiable {
    case markCompleted = "mark_completed"
    case removeFromCalendar = "remove_from_calendar"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .markCompleted:
            return "Mark as Completed (✓)"
        case .removeFromCalendar:
            return "Remove from Calendar"
        }
    }

    var explanation: String {
        switch self {
        case .markCompleted:
            return "Updates calendar event title with \"✓ Completed\" and silences all reminder alarms."
        case .removeFromCalendar:
            return "Deletes the event from Apple Calendar so the calendar doesn't hold completed deadlines."
        }
    }
}

@MainActor
protocol CalendarSyncServiceProtocol: AnyObject {
    var isCalendarSyncEnabled: Bool { get set }
    var calendarAlertsEnabled: Bool { get set }
    var completedEventBehavior: CalendarCompletedBehavior { get set }
    var selectedCalendarIdentifier: String? { get set }
    var lastSyncDate: Date? { get }

    func checkAuthorizationStatus() -> CalendarAuthStatus
    func requestAccess() async -> Bool
    func syncAssignment(_ assignment: Assignment) async -> String?
    func syncAssignments(_ assignments: [Assignment]) async
    func syncAssignmentsWithReport(_ assignments: [Assignment]) async -> CalendarSyncSummary
    func handleAssignmentCompletionChanged(_ assignment: Assignment) async
    func handleCodingTaskCompletionChanged(_ task: CodingTask) async
    func syncCodingTask(_ task: CodingTask, alertMinutesBefore: Int?) async -> (eventId: String?, error: String?)
    func removeLinkedEvent(withIdentifier identifier: String)
    func removeAllAppManagedEvents()
}

// MARK: - Production EventKit Calendar Sync Service

@MainActor
final class CalendarSyncService: ObservableObject, CalendarSyncServiceProtocol {
    static let shared = CalendarSyncService()

    private let eventStore = EKEventStore()
    private let syncEnabledKey = "calendar_sync_enabled"
    private let alertsEnabledKey = "calendar_sync_alerts_enabled"
    private let calendarIdKey = "calendar_selected_identifier"
    private let lastSyncKey = "calendar_last_sync_date"
    private let completedBehaviorKey = "calendar_completed_behavior"

    static let appManagedTag = "[Managed by Assignment Radar"

    @Published var lastSyncDate: Date? {
        didSet {
            UserDefaults.standard.set(lastSyncDate, forKey: lastSyncKey)
        }
    }

    @Published var lastError: String? = nil

    var isCalendarSyncEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: syncEnabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: syncEnabledKey)
            objectWillChange.send()
        }
    }

    var calendarAlertsEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: alertsEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: alertsEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: alertsEnabledKey)
            objectWillChange.send()
        }
    }

    var completedEventBehavior: CalendarCompletedBehavior {
        get {
            if let saved = UserDefaults.standard.string(forKey: completedBehaviorKey),
               let behavior = CalendarCompletedBehavior(rawValue: saved) {
                return behavior
            }
            return .markCompleted
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: completedBehaviorKey)
            objectWillChange.send()
        }
    }

    var selectedCalendarIdentifier: String? {
        get { UserDefaults.standard.string(forKey: calendarIdKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: calendarIdKey)
            objectWillChange.send()
        }
    }

    init() {
        self.lastSyncDate = UserDefaults.standard.object(forKey: lastSyncKey) as? Date
    }

    // MARK: - Authorization

    func checkAuthorizationStatus() -> CalendarAuthStatus {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorized: return .authorized
        case .fullAccess: return .fullAccess
        case .writeOnly: return .writeOnly
        @unknown default: return .unknown
        }
    }

    func requestAccess() async -> Bool {
        let status = checkAuthorizationStatus()
        if status.isPermitted {
            isCalendarSyncEnabled = true
            return true
        }

        do {
            if #available(iOS 17.0, *) {
                var granted = false
                do {
                    granted = try await eventStore.requestFullAccessToEvents()
                } catch {
                    granted = try await eventStore.requestWriteOnlyAccessToEvents()
                }
                if granted {
                    isCalendarSyncEnabled = true
                }
                objectWillChange.send()
                return granted
            } else {
                let granted = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                    eventStore.requestAccess(to: .event) { granted, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: granted)
                        }
                    }
                }
                if granted {
                    isCalendarSyncEnabled = true
                }
                objectWillChange.send()
                return granted
            }
        } catch {
            print("EventKit authorization error: \(error.localizedDescription)")
            self.lastError = error.localizedDescription
            objectWillChange.send()
            return false
        }
    }

    // MARK: - Destination Calendar Selection

    func destinationCalendar() -> EKCalendar? {
        if let id = selectedCalendarIdentifier,
           let cal = eventStore.calendar(withIdentifier: id),
           cal.allowsContentModifications {
            return cal
        }
        if let def = eventStore.defaultCalendarForNewEvents, def.allowsContentModifications {
            return def
        }
        return availableCalendars().first
    }

    func currentDestinationCalendarName() -> String {
        destinationCalendar()?.title ?? "Apple Calendar"
    }

    func availableCalendars() -> [EKCalendar] {
        eventStore.calendars(for: .event).filter { $0.allowsContentModifications }
    }

    // MARK: - Event Synchronization

    /// Searches for an existing event created by Assignment Radar for the given assignment.
    private func findExistingManagedEvent(for assignment: Assignment) -> EKEvent? {
        let cal = Calendar.current
        let searchStart = cal.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        let searchEnd = cal.date(byAdding: .year, value: 2, to: Date()) ?? Date()

        let predicate = eventStore.predicateForEvents(withStart: searchStart, end: searchEnd, calendars: nil)
        let candidates = eventStore.events(matching: predicate)

        let targetUuidString = assignment.id.uuidString
        return candidates.first { event in
            guard isEventManagedByApp(event), let notes = event.notes else { return false }
            return notes.contains(targetUuidString)
        }
    }

    /// Synchronizes a single assignment or exam with Apple Calendar with detailed status reporting.
    @discardableResult
    func syncAssignmentWithDetail(_ assignment: Assignment, force: Bool = false) async -> (eventId: String?, status: CalendarSyncActionStatus, error: String?) {
        guard assignment.hasValidDeadline else {
            return (nil, .skipped, nil)
        }

        // 1. If completed and configured to remove completed data from Apple Calendar
        if assignment.isCompleted && completedEventBehavior == .removeFromCalendar {
            if let existingId = assignment.calendarEventId {
                removeLinkedEvent(withIdentifier: existingId)
                assignment.calendarEventId = nil
                try? assignment.modelContext?.save()
                return (nil, .updated, nil)
            } else if let found = findExistingManagedEvent(for: assignment), let id = found.eventIdentifier {
                removeLinkedEvent(withIdentifier: id)
                assignment.calendarEventId = nil
                try? assignment.modelContext?.save()
                return (nil, .updated, nil)
            }
            return (nil, .skipped, nil)
        }

        // Request access automatically if not yet determined
        let currentStatus = checkAuthorizationStatus()
        if currentStatus == .notDetermined {
            let granted = await requestAccess()
            if !granted {
                return (nil, .failed, "Calendar permission denied. Enable Calendars in iOS Settings > Privacy & Security > Calendars.")
            }
        } else if !currentStatus.isPermitted {
            return (nil, .failed, "Calendar permission denied. Enable Calendars in iOS Settings > Privacy & Security > Calendars.")
        }

        guard let targetCalendar = destinationCalendar() else {
            return (nil, .failed, "No writable Apple Calendar available. Please check that a calendar account is configured in iOS Settings.")
        }

        // Resolve existing linked event or find by unique assignment UUID in notes to prevent duplicates
        var isExisting = false
        let event: EKEvent

        if let existingId = assignment.calendarEventId,
           let fetched = eventStore.event(withIdentifier: existingId),
           isEventManagedByApp(fetched) {
            event = fetched
            isExisting = true
        } else if let found = findExistingManagedEvent(for: assignment) {
            event = found
            assignment.calendarEventId = found.eventIdentifier
            isExisting = true
        } else {
            event = EKEvent(eventStore: eventStore)
        }

        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute, .second], from: assignment.dueDate)
        let isMidnightOnly = (comps.hour == 0 && comps.minute == 0 && comps.second == 0)

        // 2. Configure Titles and Dates according to completion state
        if assignment.isExam {
            let examPrefix = assignment.isCompleted ? "✓ [Completed Exam] " : "[Exam] "

            if let session = assignment.sessionTime, !session.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let (startHour, startMinute) = NotificationService.parseSessionStartTime(from: session) {
                var startComps = cal.dateComponents([.year, .month, .day], from: assignment.dueDate)
                startComps.hour = startHour
                startComps.minute = startMinute
                startComps.second = 0
                let examStart = cal.date(from: startComps) ?? assignment.effectiveDate
                event.startDate = examStart
                event.isAllDay = false

                if let (endHour, endMinute) = NotificationService.parseSessionEndTime(from: session) {
                    var endComps = cal.dateComponents([.year, .month, .day], from: assignment.dueDate)
                    endComps.hour = endHour
                    endComps.minute = endMinute
                    endComps.second = 0
                    if let examEnd = cal.date(from: endComps), examEnd > examStart {
                        event.endDate = examEnd
                    } else {
                        event.endDate = examStart.addingTimeInterval(3 * 3600)
                    }
                } else {
                    event.endDate = examStart.addingTimeInterval(3 * 3600)
                }
                event.title = "\(examPrefix)\(assignment.title)"
            } else if isMidnightOnly {
                // Unknown time: do not invent a confirmed time; label as all-day
                event.isAllDay = true
                event.startDate = cal.startOfDay(for: assignment.dueDate)
                event.endDate = cal.startOfDay(for: assignment.dueDate)
                event.title = "\(examPrefix)\(assignment.title) (Time TBD)"
            } else {
                event.isAllDay = false
                event.startDate = assignment.effectiveDate
                event.endDate = assignment.effectiveDate.addingTimeInterval(2 * 3600)
                event.title = "\(examPrefix)\(assignment.title)"
            }
        } else {
            // Assignment deadline handling:
            let titlePrefix = assignment.isCompleted ? "✓ Completed: " : "Due: "
            if isMidnightOnly {
                // Midnight-only date: treat as all-day deadline
                event.isAllDay = true
                event.startDate = cal.startOfDay(for: assignment.dueDate)
                event.endDate = cal.startOfDay(for: assignment.dueDate)
                event.title = "\(titlePrefix)\(assignment.title)"
            } else {
                // Explicit due date and time: short event ending at deadline with 30-min duration
                event.isAllDay = false
                event.endDate = assignment.dueDate
                event.startDate = assignment.dueDate.addingTimeInterval(-1800)
                event.title = "\(titlePrefix)\(assignment.title)"
            }
        }

        event.calendar = targetCalendar

        if !assignment.room.isEmpty {
            event.location = assignment.room
        }

        // Structured notes with app ownership tag & completion state
        var notesLines: [String] = []
        if assignment.isCompleted {
            notesLines.append("Status: Completed (Finished)")
        }
        if !assignment.course.isEmpty {
            notesLines.append("Course: \(assignment.course)")
        }
        if !assignment.room.isEmpty {
            notesLines.append("Room / Venue: \(assignment.room)")
        }
        notesLines.append("Source: \(assignment.source.capitalized)")
        if let session = assignment.sessionTime, !session.isEmpty {
            notesLines.append("Session Time: \(session)")
        }
        if !assignment.notes.isEmpty {
            notesLines.append("\nNotes:\n\(assignment.notes)")
        }
        notesLines.append("\n\(Self.appManagedTag) · \(assignment.id.uuidString)]")
        let generatedNotes = notesLines.joined(separator: "\n")
        event.notes = generatedNotes

        // Alarms: If completed, silence all alarms so the user is never nagged for completed items
        if assignment.isCompleted {
            event.alarms = []
        } else if calendarAlertsEnabled {
            if event.isAllDay {
                event.alarms = [
                    EKAlarm(relativeOffset: -86400 + 32400), // 1 day before at 9:00 AM
                    EKAlarm(relativeOffset: 32400)          // Day of at 9:00 AM
                ]
            } else {
                event.alarms = [
                    EKAlarm(relativeOffset: -86400), // 24 hours before
                    EKAlarm(relativeOffset: -7200)   // 2 hours before
                ]
            }
        } else {
            event.alarms = []
        }

        // Skip saving if the existing event is already identical
        if isExisting && !force,
           event.eventIdentifier != nil,
           let current = eventStore.event(withIdentifier: event.eventIdentifier),
           current.title == event.title,
           current.startDate == event.startDate,
           current.endDate == event.endDate,
           current.isAllDay == event.isAllDay,
           current.location == event.location,
           current.notes == generatedNotes,
           (current.alarms?.count ?? 0) == (event.alarms?.count ?? 0) {
            return (event.eventIdentifier, .skipped, nil)
        }

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            assignment.calendarEventId = event.eventIdentifier
            try? assignment.modelContext?.save()
            self.lastSyncDate = Date()
            return (event.eventIdentifier, isExisting ? .updated : .added, nil)
        } catch {
            print("Failed to save event to Apple Calendar: \(error.localizedDescription)")
            self.lastError = error.localizedDescription
            return (nil, .failed, error.localizedDescription)
        }
    }

    /// Automatically syncs state changes when an assignment is marked completed or uncompleted.
    func handleAssignmentCompletionChanged(_ assignment: Assignment) async {
        guard isCalendarSyncEnabled else { return }
        guard assignment.hasValidDeadline else { return }

        let status = checkAuthorizationStatus()
        guard status.isPermitted else { return }

        if assignment.isCompleted {
            switch completedEventBehavior {
            case .removeFromCalendar:
                if let eventId = assignment.calendarEventId {
                    removeLinkedEvent(withIdentifier: eventId)
                    assignment.calendarEventId = nil
                    try? assignment.modelContext?.save()
                } else if let found = findExistingManagedEvent(for: assignment), let id = found.eventIdentifier {
                    removeLinkedEvent(withIdentifier: id)
                    assignment.calendarEventId = nil
                    try? assignment.modelContext?.save()
                }
            case .markCompleted:
                _ = await syncAssignmentWithDetail(assignment, force: true)
            }
        } else {
            // Assignment was unmarked: restore active deadline event on Apple Calendar with alarms
            _ = await syncAssignmentWithDetail(assignment, force: true)
        }
    }

    /// Synchronizes a single assignment (backward compatible).
    @discardableResult
    func syncAssignment(_ assignment: Assignment) async -> String? {
        guard assignment.hasValidDeadline else { return nil }
        let (id, _, _) = await syncAssignmentWithDetail(assignment)
        return id
    }

    /// Batch synchronizes assignments with detailed report.
    func syncAssignmentsWithReport(_ assignments: [Assignment]) async -> CalendarSyncSummary {
        let authorized = await requestAccess()
        var summary = CalendarSyncSummary(destinationCalendarName: currentDestinationCalendarName())

        guard authorized else {
            summary.failed = assignments.filter { !$0.isArchived && $0.hasValidDeadline }.count
            summary.firstErrorMessage = "Calendar permission denied. Enable access in iOS Settings > Privacy & Security > Calendars."
            return summary
        }

        for assignment in assignments where !assignment.isArchived && assignment.hasValidDeadline {
            let (_, status, error) = await syncAssignmentWithDetail(assignment)
            switch status {
            case .added:
                summary.added += 1
            case .updated:
                summary.updated += 1
            case .skipped:
                summary.skipped += 1
            case .failed:
                summary.failed += 1
                if summary.firstErrorMessage == nil {
                    summary.firstErrorMessage = error
                }
            }
        }

        self.lastSyncDate = Date()
        return summary
    }

    /// Batch synchronizes eligible assignments (backward compatible).
    func syncAssignments(_ assignments: [Assignment]) async {
        _ = await syncAssignmentsWithReport(assignments)
    }

    /// Automatically syncs state changes when a coding task/event is marked completed or uncompleted.
    func handleCodingTaskCompletionChanged(_ task: CodingTask) async {
        guard isCalendarSyncEnabled else { return }
        let status = checkAuthorizationStatus()
        guard status.isPermitted else { return }

        if task.isCompleted {
            switch completedEventBehavior {
            case .removeFromCalendar:
                if let calId = task.calendarEventId {
                    removeLinkedEvent(withIdentifier: calId)
                    task.calendarEventId = nil
                    try? task.modelContext?.save()
                }
            case .markCompleted:
                _ = await syncCodingTask(task, alertMinutesBefore: nil)
            }
        } else {
            _ = await syncCodingTask(task, alertMinutesBefore: 15)
        }
    }

    /// Synchronizes a Coding Radar manual event, hackathon, or contest with Apple Calendar.
    @discardableResult
    func syncCodingTask(_ task: CodingTask, alertMinutesBefore: Int? = 15) async -> (eventId: String?, error: String?) {
        if task.isCompleted && completedEventBehavior == .removeFromCalendar {
            if let existingId = task.calendarEventId {
                removeLinkedEvent(withIdentifier: existingId)
                task.calendarEventId = nil
                try? task.modelContext?.save()
            }
            return (nil, nil)
        }

        let authorized = await requestAccess()
        guard authorized else {
            return (nil, "Calendar permission denied. To add events to Apple Calendar, enable Calendars in iOS Settings > Privacy & Security > Calendars.")
        }

        guard let targetCalendar = destinationCalendar() else {
            return (nil, "No writable Apple Calendar found.")
        }

        let event: EKEvent
        if let existingId = task.calendarEventId,
           let fetched = eventStore.event(withIdentifier: existingId),
           isEventManagedByApp(fetched) {
            event = fetched
        } else {
            event = EKEvent(eventStore: eventStore)
        }

        if task.isCompleted {
            event.title = "✓ Completed: \(task.title)"
        } else {
            event.title = task.title
        }
        event.calendar = targetCalendar

        let startDate = task.startDate ?? task.dueDate ?? Date()
        event.startDate = startDate

        if let explicitEnd = task.endDate, explicitEnd > startDate {
            event.endDate = explicitEnd
        } else if let due = task.dueDate, due > startDate {
            event.endDate = due
        } else {
            event.endDate = startDate.addingTimeInterval(3600)
        }
        event.isAllDay = false

        var notesLines: [String] = []
        if task.isCompleted {
            notesLines.append("Status: Completed (Finished)")
        }
        notesLines.append("Platform / Organizer: \(task.platformName)")
        notesLines.append("Event Type: \(task.taskType.rawValue)")
        notesLines.append("Registration Status: \(task.registrationStatus.rawValue)")

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        if let reg = task.registrationDeadline {
            notesLines.append("Registration Deadline: \(dateFormatter.string(from: reg))")
        }
        if let sub = task.submissionDeadline {
            notesLines.append("Submission Deadline: \(dateFormatter.string(from: sub))")
        }
        if let url = task.officialUrl, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notesLines.append("Official Link: \(url)")
            event.url = URL(string: url)
        }
        if !task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notesLines.append("\nNotes:\n\(task.notes)")
        }
        notesLines.append("\n\(Self.appManagedTag) · \(task.id.uuidString)]")
        event.notes = notesLines.joined(separator: "\n")

        if task.isCompleted {
            event.alarms = []
        } else if let mins = alertMinutesBefore, mins > 0 {
            event.alarms = [EKAlarm(relativeOffset: -Double(mins * 60))]
        } else {
            event.alarms = []
        }

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            task.calendarEventId = event.eventIdentifier
            self.lastSyncDate = Date()
            return (event.eventIdentifier, nil)
        } catch {
            print("Failed to save coding event to Apple Calendar: \(error.localizedDescription)")
            self.lastError = error.localizedDescription
            return (nil, error.localizedDescription)
        }
    }

    // MARK: - Deletion & Cleanup

    func removeLinkedEvent(withIdentifier identifier: String) {
        guard !identifier.isEmpty else { return }
        guard let event = eventStore.event(withIdentifier: identifier) else { return }

        guard isEventManagedByApp(event) else {
            print("Security check: Event \(identifier) is not managed by Assignment Radar. Deletion aborted.")
            return
        }

        do {
            try eventStore.remove(event, span: .thisEvent, commit: true)
        } catch {
            print("Failed to remove calendar event \(identifier): \(error.localizedDescription)")
        }
    }

    func removeAllAppManagedEvents() {
        guard checkAuthorizationStatus().isPermitted else { return }

        let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        let twoYearsLater = Calendar.current.date(byAdding: .year, value: 2, to: Date()) ?? Date()

        let predicate = eventStore.predicateForEvents(withStart: oneYearAgo, end: twoYearsLater, calendars: nil)
        let events = eventStore.events(matching: predicate)

        for event in events where isEventManagedByApp(event) {
            try? eventStore.remove(event, span: .thisEvent, commit: false)
        }
        try? eventStore.commit()
    }

    // MARK: - Private Helpers

    private func isEventManagedByApp(_ event: EKEvent) -> Bool {
        guard let notes = event.notes else { return false }
        return notes.contains(Self.appManagedTag)
    }
}

// MARK: - Mock Service for Unit Testing

final class MockCalendarSyncService: CalendarSyncServiceProtocol {
    var isCalendarSyncEnabled: Bool = false
    var calendarAlertsEnabled: Bool = true
    var completedEventBehavior: CalendarCompletedBehavior = .markCompleted
    var selectedCalendarIdentifier: String? = nil
    var lastSyncDate: Date? = nil

    var mockStatus: CalendarAuthStatus = .authorized
    var mockEvents: [String: (title: String, date: Date, notes: String)] = [:]

    func checkAuthorizationStatus() -> CalendarAuthStatus {
        mockStatus
    }

    func requestAccess() async -> Bool {
        mockStatus.isPermitted
    }

    func syncAssignment(_ assignment: Assignment) async -> String? {
        guard isCalendarSyncEnabled else { return nil }
        guard assignment.hasValidDeadline else { return nil }
        guard mockStatus.isPermitted else { return nil }

        if assignment.isCompleted && completedEventBehavior == .removeFromCalendar {
            if let id = assignment.calendarEventId {
                mockEvents.removeValue(forKey: id)
                assignment.calendarEventId = nil
            }
            return nil
        }

        let eventId = assignment.calendarEventId ?? "mock_evt_\(assignment.id.uuidString)"
        let title: String
        if assignment.isCompleted {
            title = assignment.isExam ? "✓ [Completed Exam] \(assignment.title)" : "✓ Completed: \(assignment.title)"
        } else {
            title = assignment.isExam ? "[Exam] \(assignment.title)" : assignment.title
        }

        let statusLine = assignment.isCompleted ? "Status: Completed (Finished)\n" : ""
        let notes = "\(statusLine)Course: \(assignment.course)\n\(CalendarSyncService.appManagedTag) · \(assignment.id.uuidString)]"

        mockEvents[eventId] = (title: title, date: assignment.effectiveDate, notes: notes)
        assignment.calendarEventId = eventId
        self.lastSyncDate = Date()
        return eventId
    }

    func handleAssignmentCompletionChanged(_ assignment: Assignment) async {
        guard isCalendarSyncEnabled && mockStatus.isPermitted else { return }
        guard assignment.hasValidDeadline else { return }

        if assignment.isCompleted {
            switch completedEventBehavior {
            case .removeFromCalendar:
                if let eventId = assignment.calendarEventId {
                    removeLinkedEvent(withIdentifier: eventId)
                    assignment.calendarEventId = nil
                }
            case .markCompleted:
                _ = await syncAssignment(assignment)
            }
        } else {
            _ = await syncAssignment(assignment)
        }
    }

    func syncAssignments(_ assignments: [Assignment]) async {
        guard isCalendarSyncEnabled && mockStatus.isPermitted else { return }
        for item in assignments where !item.isArchived && item.hasValidDeadline {
            _ = await syncAssignment(item)
        }
    }

    func syncAssignmentsWithReport(_ assignments: [Assignment]) async -> CalendarSyncSummary {
        var summary = CalendarSyncSummary(destinationCalendarName: "Mock Calendar")
        guard isCalendarSyncEnabled && mockStatus.isPermitted else {
            summary.failed = assignments.filter { !$0.isArchived && $0.hasValidDeadline }.count
            summary.firstErrorMessage = "Mock permission denied"
            return summary
        }
        for item in assignments where !item.isArchived && item.hasValidDeadline {
            let wasExisting = (item.calendarEventId != nil && mockEvents[item.calendarEventId!] != nil)
            if item.isCompleted && completedEventBehavior == .removeFromCalendar {
                if wasExisting, let id = item.calendarEventId {
                    mockEvents.removeValue(forKey: id)
                    item.calendarEventId = nil
                    summary.updated += 1
                } else {
                    summary.skipped += 1
                }
                continue
            }

            if let _ = await syncAssignment(item) {
                if wasExisting {
                    summary.updated += 1
                } else {
                    summary.added += 1
                }
            } else {
                summary.failed += 1
            }
        }
        return summary
    }

    func removeLinkedEvent(withIdentifier identifier: String) {
        if let event = mockEvents[identifier], event.notes.contains(CalendarSyncService.appManagedTag) {
            mockEvents.removeValue(forKey: identifier)
        }
    }

    func handleCodingTaskCompletionChanged(_ task: CodingTask) async {
        guard isCalendarSyncEnabled && mockStatus.isPermitted else { return }
        if task.isCompleted {
            switch completedEventBehavior {
            case .removeFromCalendar:
                if let calId = task.calendarEventId {
                    removeLinkedEvent(withIdentifier: calId)
                    task.calendarEventId = nil
                }
            case .markCompleted:
                _ = await syncCodingTask(task, alertMinutesBefore: nil)
            }
        } else {
            _ = await syncCodingTask(task, alertMinutesBefore: 15)
        }
    }

    func syncCodingTask(_ task: CodingTask, alertMinutesBefore: Int?) async -> (eventId: String?, error: String?) {
        guard mockStatus.isPermitted else {
            return (nil, "Calendar permission denied.")
        }
        if task.isCompleted && completedEventBehavior == .removeFromCalendar {
            if let existingId = task.calendarEventId {
                mockEvents.removeValue(forKey: existingId)
                task.calendarEventId = nil
            }
            return (nil, nil)
        }

        let eventId = task.calendarEventId ?? "mock_coding_evt_\(task.id.uuidString)"
        let title = task.isCompleted ? "✓ Completed: \(task.title)" : task.title
        let statusLine = task.isCompleted ? "Status: Completed (Finished)\n" : ""
        let notes = "\(statusLine)Platform: \(task.platformName)\n\(CalendarSyncService.appManagedTag) · \(task.id.uuidString)]"
        mockEvents[eventId] = (title: title, date: task.startDate ?? Date(), notes: notes)
        task.calendarEventId = eventId
        self.lastSyncDate = Date()
        return (eventId, nil)
    }

    func removeAllAppManagedEvents() {
        mockEvents.removeAll()
    }
}
