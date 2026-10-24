//
//  AssignmentEditorView.swift
//  AssignementRadar
//
//  Created for Assignment Radar Milestone 1 & UI Refinement.
//

import SwiftUI
import SwiftData

/// A reusable form for creating a new assignment or editing an existing one.
struct AssignmentEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// If nil, the view creates a new assignment; otherwise, it edits this existing one.
    var assignmentToEdit: Assignment?

    @State private var title: String = ""
    @State private var course: String = ""
    @State private var dueDate: Date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var priority: Priority = .medium
    @State private var notes: String = ""
    @State private var isCompleted: Bool = false
    @State private var eventType: String = "assignment"
    @State private var sessionTime: String = ""
    @State private var syncToAppleCalendar: Bool = true

    private var isEditing: Bool {
        assignmentToEdit != nil
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(assignmentToEdit: Assignment? = nil, initialDueDate: Date? = nil) {
        self.assignmentToEdit = assignmentToEdit
        if let assignment = assignmentToEdit {
            _title = State(initialValue: assignment.title)
            _course = State(initialValue: assignment.course)
            _dueDate = State(initialValue: assignment.dueDate)
            _priority = State(initialValue: assignment.priority)
            _notes = State(initialValue: assignment.notes)
            _isCompleted = State(initialValue: assignment.isCompleted)
            _eventType = State(initialValue: assignment.eventType)
            _sessionTime = State(initialValue: assignment.sessionTime ?? "")
            _syncToAppleCalendar = State(initialValue: assignment.calendarEventId != nil || CalendarSyncService.shared.isCalendarSyncEnabled)
        } else if let initialDate = initialDueDate {
            _dueDate = State(initialValue: initialDate)
            _syncToAppleCalendar = State(initialValue: true)
        } else {
            _syncToAppleCalendar = State(initialValue: true)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Event Type") {
                    Picker("Type", selection: $eventType) {
                        Text("Assignment").tag("assignment")
                        Text("Exam").tag("exam")
                    }
                    .pickerStyle(.segmented)

                    if eventType == "exam" {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Session / Time (e.g. 10:00 AM - 01:00 PM)", text: $sessionTime)
                            if sessionTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("No session specified: Reminders will assume standard 10:00 AM morning slot.")
                                    .font(.caption2)
                                    .foregroundStyle(Color.theme.secondaryText)
                            }
                        }
                    }
                }

                Section(eventType == "exam" ? "Exam Info" : "Assignment Info") {
                    TextField(eventType == "exam" ? "Subject Title (e.g. Operating Systems)" : "Title (e.g., Problem Set 2)", text: $title)
                    TextField("Course Code (e.g., CS 101)", text: $course)
                }

                Section(eventType == "exam" ? "Exam Date & Priority" : "Deadline & Priority") {
                    DatePicker(eventType == "exam" ? "Exam Date" : "Due Date", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    
                    Picker("Priority", selection: $priority) {
                        ForEach(Priority.allCases) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Notes (Optional)") {
                    TextField("Instructions, room number, syllabus, etc.", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Apple Calendar") {
                    Toggle("Sync with Apple Calendar", isOn: $syncToAppleCalendar)
                        .tint(Color.theme.primaryAccent)

                    if syncToAppleCalendar {
                        HStack {
                            Text("Target Calendar")
                            Spacer()
                            Text(CalendarSyncService.shared.currentDestinationCalendarName())
                                .font(.caption)
                                .foregroundStyle(Color.theme.secondaryText)
                        }
                    }
                }

                if isEditing {
                    Section("Status") {
                        Toggle("Mark as Completed", isOn: $isCompleted)
                    }
                }
            }
            .navigationTitle(isEditing ? (eventType == "exam" ? "Edit Exam" : "Edit Assignment") : (eventType == "exam" ? "New Exam" : "New Assignment"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!isValid)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    /// Saves the new or updated assignment into the SwiftData ModelContext.
    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCourse = course.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSession = sessionTime.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalSession = cleanSession.isEmpty ? nil : cleanSession

        let shouldSync = syncToAppleCalendar

        if let assignment = assignmentToEdit {
            assignment.title = cleanTitle
            assignment.course = cleanCourse
            assignment.dueDate = dueDate
            assignment.priority = priority
            assignment.notes = cleanNotes
            assignment.isCompleted = isCompleted
            assignment.eventType = eventType
            assignment.sessionTime = finalSession

            if assignment.source == "moodle" {
                MoodleAccountTaskStore.shared.saveState(for: assignment)
            }
            TaskSyncCoordinator.shared.recordTaskStateChange(for: assignment)

            NotificationService.shared.cancelReminders(for: assignment.id)
            if !assignment.isCompleted {
                NotificationService.shared.scheduleReminders(for: assignment)
            }

            try? modelContext.save()

            Task {
                if shouldSync {
                    let (eventId, _, _) = await CalendarSyncService.shared.syncAssignmentWithDetail(assignment, force: true)
                    if eventId != nil {
                        assignment.calendarEventId = eventId
                        try? modelContext.save()
                    }
                } else if let existingCalId = assignment.calendarEventId {
                    CalendarSyncService.shared.removeLinkedEvent(withIdentifier: existingCalId)
                    assignment.calendarEventId = nil
                    try? modelContext.save()
                }
            }
        } else {
            let newAssignment = Assignment(
                title: cleanTitle,
                course: cleanCourse,
                dueDate: dueDate,
                priority: priority,
                notes: cleanNotes,
                isCompleted: isCompleted,
                eventType: eventType,
                sessionTime: finalSession
            )
            modelContext.insert(newAssignment)
            TaskSyncCoordinator.shared.recordTaskStateChange(for: newAssignment)

            if !newAssignment.isCompleted {
                NotificationService.shared.scheduleReminders(for: newAssignment)
            }

            try? modelContext.save()

            Task {
                if shouldSync {
                    let (eventId, _, _) = await CalendarSyncService.shared.syncAssignmentWithDetail(newAssignment, force: true)
                    if eventId != nil {
                        newAssignment.calendarEventId = eventId
                        try? modelContext.save()
                    }
                }
            }
        }

        dismiss()
    }
}
