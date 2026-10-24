//
//  CalendarSettingsView.swift
//  AssignementRadar
//
//  Created for Assignment Radar Apple Calendar Integration Settings.
//

import SwiftUI
import EventKit
import SwiftData

struct CalendarSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var assignments: [Assignment]

    @ObservedObject private var syncService = CalendarSyncService.shared
    @State private var isRequestingAccess: Bool = false
    @State private var syncStatusMessage: String? = nil

    private var authStatus: CalendarAuthStatus {
        syncService.checkAuthorizationStatus()
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Permission & Status Section
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "calendar.badge.clock")
                                .font(.title2)
                                .foregroundStyle(Color.theme.primaryAccent)
                            Text("Apple Calendar Sync")
                                .font(.headline)
                                .foregroundStyle(Color.theme.primaryText)
                        }

                        Text("Automatically sync your assignment deadlines and examination schedules with your iOS Calendar.")
                            .font(.caption)
                            .foregroundStyle(Color.theme.secondaryText)
                    }
                    .padding(.vertical, 4)

                    HStack {
                        Text("Permission Status")
                        Spacer()
                        Text(authStatus.rawValue)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(authStatus.isPermitted ? Color.theme.success : Color.theme.warning)
                    }

                    if authStatus == .denied || authStatus == .restricted {
                        Button {
                            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(settingsUrl)
                            }
                        } label: {
                            Label("Open iOS Settings to Allow Access", systemImage: "gearshape")
                                .font(.subheadline)
                        }
                    } else if !authStatus.isPermitted {
                        Button {
                            Task {
                                isRequestingAccess = true
                                let granted = await syncService.requestAccess()
                                isRequestingAccess = false
                                if granted {
                                    let summary = await syncService.syncAssignmentsWithReport(assignments)
                                    syncStatusMessage = summary.resultMessage
                                }
                            }
                        } label: {
                            Label("Request Calendar Permission", systemImage: "checkmark.circle")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(Color.theme.primaryAccent)
                    }
                }
                .listRowBackground(Color.theme.cardBackground)

                // MARK: - Destination Calendar Section
                if authStatus.isPermitted {
                    Section("Destination Calendar") {
                        let calendars = syncService.availableCalendars()
                        if calendars.isEmpty {
                            Text("No writable calendar found on device.")
                                .font(.caption)
                                .foregroundStyle(Color.theme.secondaryText)
                        } else {
                            Picker("Target Calendar", selection: Binding(
                                get: { syncService.destinationCalendar()?.calendarIdentifier ?? "" },
                                set: { newId in
                                    syncService.selectedCalendarIdentifier = newId
                                }
                            )) {
                                ForEach(calendars, id: \.calendarIdentifier) { cal in
                                    HStack {
                                        Circle()
                                            .fill(Color(cgColor: cal.cgColor))
                                            .frame(width: 8, height: 8)
                                        Text(cal.title).tag(cal.calendarIdentifier)
                                    }
                                }
                            }
                        }
                    }
                    .listRowBackground(Color.theme.cardBackground)
                }

                // MARK: - Sync Controls Section
                Section("Sync Configuration") {
                    Toggle("Enable Automatic Sync", isOn: Binding(
                        get: { syncService.isCalendarSyncEnabled },
                        set: { enabled in
                            if enabled && !authStatus.isPermitted {
                                Task {
                                    isRequestingAccess = true
                                    let granted = await syncService.requestAccess()
                                    isRequestingAccess = false
                                    if granted {
                                        syncService.isCalendarSyncEnabled = true
                                        let summary = await syncService.syncAssignmentsWithReport(assignments)
                                        syncStatusMessage = summary.resultMessage
                                    }
                                }
                            } else {
                                syncService.isCalendarSyncEnabled = enabled
                                if enabled {
                                    Task {
                                        let summary = await syncService.syncAssignmentsWithReport(assignments)
                                        syncStatusMessage = summary.resultMessage
                                    }
                                }
                            }
                        }
                    ))
                    .tint(Color.theme.primaryAccent)

                    Toggle("Calendar Deadline Alerts", isOn: $syncService.calendarAlertsEnabled)
                        .tint(Color.theme.primaryAccent)
                        .disabled(!syncService.isCalendarSyncEnabled)

                    if let lastSync = syncService.lastSyncDate {
                        HStack {
                            Text("Last Synced")
                            Spacer()
                            Text(lastSync.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(Color.theme.secondaryText)
                        }
                    }
                }
                .listRowBackground(Color.theme.cardBackground)

                // MARK: - Completed Deadlines Section
                if syncService.isCalendarSyncEnabled && authStatus.isPermitted {
                    Section {
                        Picker("When Marked Complete", selection: $syncService.completedEventBehavior) {
                            ForEach(CalendarCompletedBehavior.allCases) { behavior in
                                Text(behavior.displayName).tag(behavior)
                            }
                        }
                        .pickerStyle(.menu)

                        Text(syncService.completedEventBehavior.explanation)
                            .font(.caption2)
                            .foregroundStyle(Color.theme.secondaryText)
                    } header: {
                        Text("Completed Deadlines")
                    } footer: {
                        Text("Choose whether completed items stay in Apple Calendar marked with \"✓ Completed\" (and alarms silenced) or are cleanly deleted so your calendar only holds pending deadlines.")
                    }
                    .listRowBackground(Color.theme.cardBackground)
                }

                // MARK: - Manual Trigger Section
                if syncService.isCalendarSyncEnabled && authStatus.isPermitted {
                    Section {
                        Button {
                            Task {
                                let summary = await syncService.syncAssignmentsWithReport(assignments)
                                syncStatusMessage = summary.resultMessage
                            }
                        } label: {
                            HStack {
                                Spacer()
                                Label("Sync to Apple Calendar Now", systemImage: "arrow.triangle.2.circlepath")
                                    .fontWeight(.medium)
                                Spacer()
                            }
                        }
                        .foregroundStyle(Color.theme.primaryAccent)

                        if let message = syncStatusMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(message.contains("issues") ? Color.theme.warning : Color.theme.success)
                        }
                    }
                    .listRowBackground(Color.theme.cardBackground)
                }

                // MARK: - Safety & Ownership Policy
                Section("Privacy & Safety Policy") {
                    Text("Assignment Radar only manages calendar events it creates. Your personal calendar events are never modified or deleted. When an assignment is deleted in the app, its linked calendar event is safely removed.")
                        .font(.caption2)
                        .foregroundStyle(Color.theme.secondaryText)
                }
                .listRowBackground(Color.theme.cardBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Color.theme.mainBackground)
            .navigationTitle("Calendar Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Color.theme.primaryAccent)
                }
            }
        }
    }
}
