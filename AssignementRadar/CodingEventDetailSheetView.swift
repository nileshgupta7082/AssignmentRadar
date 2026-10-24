//
//  CodingEventDetailSheetView.swift
//  AssignementRadar
//
//  Created for Coding Radar Event & Hackathon Details.
//

import SwiftUI
import SwiftData

struct CodingEventDetailSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    @Bindable var event: CodingTask

    @State private var isShowingEditSheet: Bool = false
    @State private var isShowingDeleteAlert: Bool = false

    private var platformColor: Color {
        PlatformCatalog.color(for: event.platformId.isEmpty ? event.platformName : event.platformId)
    }

    var body: some View {
        NavigationStack {
            List {
                // Section 1: Header & Key Metrics
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(platformColor)
                                .frame(width: 8, height: 8)

                            Text(event.platformName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.theme.secondaryText)

                            Spacer()

                            Text(event.taskType.rawValue)
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.theme.secondarySurface)
                                .foregroundStyle(Color.theme.primaryAccent)
                                .clipShape(Capsule())
                        }

                        Text(event.title)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.theme.primaryText)

                        HStack(spacing: 8) {
                            // Registration status pill
                            HStack(spacing: 4) {
                                Image(systemName: event.registrationStatus.iconName)
                                    .font(.system(size: 11))
                                Text(event.registrationStatus.rawValue)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(event.registrationStatus == .registered ? Color.theme.successSurface : Color.theme.secondarySurface)
                            .foregroundStyle(event.registrationStatus == .registered ? Color.theme.success : Color.theme.secondaryText)
                            .clipShape(Capsule())

                            // Calendar badge
                            if event.calendarEventId != nil {
                                HStack(spacing: 4) {
                                    Image(systemName: "calendar.badge.checkmark")
                                        .font(.system(size: 11))
                                    Text("Apple Calendar")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.theme.primaryAccent.opacity(0.12))
                                .foregroundStyle(Color.theme.primaryAccent)
                                .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Section 2: Timeline & Milestones
                Section("Schedule") {
                    if let start = event.startDate {
                        timelineRow(title: "Starts", date: start, icon: "play.circle")
                    }

                    if let end = event.endDate {
                        timelineRow(title: "Ends", date: end, icon: "stop.circle")
                    }

                    if let reg = event.registrationDeadline {
                        timelineRow(title: "Registration Closes", date: reg, icon: "hourglass")
                    }

                    if let sub = event.submissionDeadline {
                        timelineRow(title: "Submission Closes", date: sub, icon: "tray.and.arrow.up")
                    }
                }

                // Section 3: Official Link
                if let urlStr = event.officialUrl, let url = URL(string: urlStr) {
                    Section("Links") {
                        Button {
                            openURL(url)
                        } label: {
                            HStack {
                                Label("Open Official Website", systemImage: "arrow.up.right.square")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                            }
                        }
                    }
                }

                // Section 4: Notes
                if !event.notes.isEmpty {
                    Section("Notes & Description") {
                        Text(event.notes)
                            .font(.subheadline)
                            .foregroundStyle(Color.theme.primaryText)
                    }
                }

                // Section 5: Status Management
                Section("Update Status") {
                    Picker("Registration Status", selection: $event.registrationStatus) {
                        ForEach(ContestRegistrationStatus.allCases) { status in
                            Label(status.rawValue, systemImage: status.iconName).tag(status)
                        }
                    }
                    .onChange(of: event.registrationStatus) { _, newStatus in
                        if newStatus == .completed {
                            event.isCompleted = true
                            event.completedAt = Date()
                        } else if event.isCompleted && newStatus != .completed {
                            event.isCompleted = false
                            event.completedAt = nil
                        }
                        try? modelContext.save()
                        Task {
                            await CalendarSyncService.shared.handleCodingTaskCompletionChanged(event)
                        }
                    }

                    Toggle("Mark as Completed", isOn: $event.isCompleted)
                        .onChange(of: event.isCompleted) { _, completed in
                            event.completedAt = completed ? Date() : nil
                            if completed {
                                event.registrationStatus = .completed
                            }
                            try? modelContext.save()
                            Task {
                                await CalendarSyncService.shared.handleCodingTaskCompletionChanged(event)
                            }
                        }
                }

                // Section 6: Danger Zone
                Section {
                    Button(role: .destructive) {
                        isShowingDeleteAlert = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Delete Event", systemImage: "trash")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Event Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") {
                        isShowingEditSheet = true
                    }
                    .fontWeight(.medium)
                }
            }
            .sheet(isPresented: $isShowingEditSheet) {
                CodingEventEditorView(eventToEdit: event)
            }
            .alert("Delete Event?", isPresented: $isShowingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    deleteEvent()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This event will be permanently removed. If synced with Apple Calendar, the calendar entry will also be cleanly removed.")
            }
        }
    }

    private func timelineRow(title: String, date: Date, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundStyle(Color.theme.primaryAccent)
                .frame(width: 20)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color.theme.secondaryText)

            Spacer()

            Text(date.formatted(date: .abbreviated, time: .shortened))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Color.theme.primaryText)
        }
    }

    private func deleteEvent() {
        if let calId = event.calendarEventId {
            CalendarSyncService.shared.removeLinkedEvent(withIdentifier: calId)
        }
        let taskId = event.id
        modelContext.delete(event)
        try? modelContext.save()
        CodingNotificationManager.shared.cancelReminders(for: taskId)
        dismiss()
    }
}
