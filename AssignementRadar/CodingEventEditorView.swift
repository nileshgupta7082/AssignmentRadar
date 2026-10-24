//
//  CodingEventEditorView.swift
//  AssignementRadar
//
//  Created for Coding Radar Manual Events & Hackathons.
//

import SwiftUI
import SwiftData

struct CodingEventEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var eventToEdit: CodingTask?

    // Form fields
    @State private var title: String = ""
    @State private var organizer: String = ""
    @State private var eventType: CodingEventType = .hackathon
    @State private var startDate: Date = Date().addingTimeInterval(3600)
    @State private var hasEndDate: Bool = false
    @State private var endDate: Date = Date().addingTimeInterval(7200)
    @State private var hasRegistrationDeadline: Bool = false
    @State private var registrationDeadline: Date = Date().addingTimeInterval(1800)
    @State private var hasSubmissionDeadline: Bool = false
    @State private var submissionDeadline: Date = Date().addingTimeInterval(5400)
    @State private var officialUrl: String = ""
    @State private var notes: String = ""
    @State private var registrationStatus: ContestRegistrationStatus = .interested
    @State private var addToCalendar: Bool = false
    @State private var calendarAlertMinutes: Int = 15

    // State & Validation
    @State private var validationErrorMessage: String? = nil
    @State private var calendarNoticeMessage: String? = nil
    @State private var isShowingCalendarAlertNotice: Bool = false

    private var isEditing: Bool {
        eventToEdit != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                // Section 1: Event Details
                Section("Event Overview") {
                    TextField("Event Title (e.g. HackMIT, Autumn Round)", text: $title)
                        .font(.body)

                    TextField("Organizer or Platform (e.g. MIT, Codeforces, IEEE)", text: $organizer)
                        .font(.subheadline)

                    Picker("Event Type", selection: $eventType) {
                        ForEach(CodingEventType.allCases) { type in
                            Label(type.rawValue, systemImage: type.iconName).tag(type)
                        }
                    }

                    Picker("Registration Status", selection: $registrationStatus) {
                        ForEach(ContestRegistrationStatus.allCases) { status in
                            Label(status.rawValue, systemImage: status.iconName).tag(status)
                        }
                    }
                }

                // Section 2: Date & Milestones
                Section("Schedule & Deadlines") {
                    DatePicker("Starts", selection: $startDate)

                    Toggle("Specify End Date & Time", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("Ends", selection: $endDate)
                    }

                    Toggle("Has Registration Deadline", isOn: $hasRegistrationDeadline)
                    if hasRegistrationDeadline {
                        DatePicker("Registration Closes", selection: $registrationDeadline)
                    }

                    Toggle("Has Submission Deadline", isOn: $hasSubmissionDeadline)
                    if hasSubmissionDeadline {
                        DatePicker("Project Submission Closes", selection: $submissionDeadline)
                    }
                }

                // Section 3: Links & Notes
                Section("Links & Details (Optional)") {
                    TextField("Official Event URL (optional)", text: $officialUrl)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .font(.subheadline)

                    TextField("Description, tracks, team notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.subheadline)
                }

                // Section 4: Apple Calendar Integration
                Section {
                    Toggle("Add to Apple Calendar", isOn: $addToCalendar)

                    if addToCalendar {
                        Picker("Calendar Reminder", selection: $calendarAlertMinutes) {
                            Text("15 minutes before").tag(15)
                            Text("30 minutes before").tag(30)
                            Text("1 hour before").tag(60)
                            Text("1 day before").tag(1440)
                            Text("None").tag(0)
                        }

                        Text("Events synced with Apple Calendar will automatically notify you through your native iOS calendar alarms.")
                            .font(.caption2)
                            .foregroundStyle(Color.theme.secondaryText)
                    }
                } header: {
                    Text("Apple Calendar")
                } footer: {
                    if let notice = calendarNoticeMessage {
                        Text(notice)
                            .font(.caption2)
                            .foregroundStyle(Color.theme.warning)
                    }
                }

                // Validation Error display
                if let error = validationErrorMessage {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.theme.overdue)
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(Color.theme.overdue)
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Event" : "Add Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        saveEvent()
                    }
                    .fontWeight(.bold)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                loadExistingEvent()
            }
            .alert("Calendar Notice", isPresented: $isShowingCalendarAlertNotice) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text(calendarNoticeMessage ?? "")
            }
        }
    }

    // MARK: - Validation & Persistence

    private func loadExistingEvent() {
        guard let item = eventToEdit else { return }
        title = item.title
        organizer = item.platformName == "Custom" ? "" : item.platformName
        if let matchedType = CodingEventType.allCases.first(where: { $0.rawValue.lowercased() == item.taskType.rawValue.lowercased() }) {
            eventType = matchedType
        } else if item.isContest {
            eventType = .codingContest
        }
        registrationStatus = item.registrationStatus
        if let start = item.startDate {
            startDate = start
        }
        if let end = item.endDate {
            hasEndDate = true
            endDate = end
        }
        if let reg = item.registrationDeadline {
            hasRegistrationDeadline = true
            registrationDeadline = reg
        }
        if let sub = item.submissionDeadline {
            hasSubmissionDeadline = true
            submissionDeadline = sub
        }
        officialUrl = item.officialUrl ?? ""
        notes = item.notes
        addToCalendar = item.calendarEventId != nil
    }

    private func validate() -> Bool {
        validationErrorMessage = nil

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            validationErrorMessage = "Event title is required."
            return false
        }

        if hasEndDate && endDate < startDate {
            validationErrorMessage = "End date and time must be after the start date."
            return false
        }

        if hasRegistrationDeadline && registrationDeadline > startDate {
            validationErrorMessage = "Registration deadline must be on or before the event start date."
            return false
        }

        if hasSubmissionDeadline && hasEndDate && submissionDeadline > endDate {
            validationErrorMessage = "Submission deadline cannot be after the event end date."
            return false
        }

        return true
    }

    private func saveEvent() {
        guard validate() else { return }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOrganizer = organizer.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPlatform = trimmedOrganizer.isEmpty ? "Custom" : trimmedOrganizer
        let trimmedUrl = officialUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedUrl = trimmedUrl.isEmpty ? nil : (trimmedUrl.lowercased().hasPrefix("http") ? trimmedUrl : "https://\(trimmedUrl)")

        let task: CodingTask
        if let existing = eventToEdit {
            task = existing
            task.title = trimmedTitle
            task.platformName = resolvedPlatform
            task.taskType = eventType.matchingTaskType
            task.registrationStatus = registrationStatus
            task.startDate = startDate
            task.endDate = hasEndDate ? endDate : nil
            task.registrationDeadline = hasRegistrationDeadline ? registrationDeadline : nil
            task.submissionDeadline = hasSubmissionDeadline ? submissionDeadline : nil
            task.officialUrl = resolvedUrl
            task.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            task.isManualEvent = true
        } else {
            task = CodingTask(
                title: trimmedTitle,
                platformId: "custom",
                platformName: resolvedPlatform,
                taskType: eventType.matchingTaskType,
                registrationStatus: registrationStatus,
                startDate: startDate,
                dueDate: hasEndDate ? endDate : startDate.addingTimeInterval(3600),
                endDate: hasEndDate ? endDate : nil,
                registrationDeadline: hasRegistrationDeadline ? registrationDeadline : nil,
                submissionDeadline: hasSubmissionDeadline ? submissionDeadline : nil,
                officialUrl: resolvedUrl,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                isCompleted: registrationStatus == .completed,
                isManualEvent: true
            )
            modelContext.insert(task)
        }

        try? modelContext.save()

        // Handle Calendar Sync
        Task {
            if addToCalendar {
                let (eventId, error) = await CalendarSyncService.shared.syncCodingTask(task, alertMinutesBefore: calendarAlertMinutes)
                if let error = error {
                    await MainActor.run {
                        self.calendarNoticeMessage = "Event saved locally, but Apple Calendar could not be updated: \(error)"
                        self.isShowingCalendarAlertNotice = true
                    }
                    return
                } else {
                    task.calendarEventId = eventId
                    try? modelContext.save()
                }
            } else if let existingCalId = task.calendarEventId {
                // User deselected calendar sync: remove from Calendar
                CalendarSyncService.shared.removeLinkedEvent(withIdentifier: existingCalId)
                task.calendarEventId = nil
                try? modelContext.save()
            }

            let descriptor = FetchDescriptor<CodingTask>()
            let all = (try? modelContext.fetch(descriptor)) ?? [task]
            await CodingNotificationManager.shared.reconcile(tasks: all)

            await MainActor.run {
                dismiss()
            }
        }
    }
}
