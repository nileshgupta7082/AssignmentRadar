//
//  ProfileMenuView.swift
//  AssignementRadar
//
//  Created for Assignment Radar Profile & Quick Navigation Menu.
//

import SwiftUI
import SwiftData

/// Dedicated user profile and navigation sheet presenting account details, completed tasks, platforms, and hackathons.
struct ProfileMenuView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var assignments: [Assignment]
    @Query private var hackathons: [Hackathon]

    @AppStorage("moodle_connected_user") private var moodleConnectedUser: String?
    @AppStorage("moodle_connected_site") private var moodleConnectedSite: String?
    @AppStorage("moodle_site_url") private var moodleSiteUrl: String?

    @State private var isShowingMoodleSheet: Bool = false
    @State private var isShowingDisconnectAlert: Bool = false

    private var isMoodleConnected: Bool {
        MoodleKeychainHelper.getToken() != nil &&
        moodleConnectedUser != nil &&
        !(moodleConnectedUser?.isEmpty ?? true)
    }

    private var completedTasksCount: Int {
        assignments.filter { $0.isCompleted && !$0.isArchived }.count
    }

    private var archivedTasksCount: Int {
        assignments.filter { $0.isArchived }.count
    }

    private var upcomingHackathonsCount: Int {
        let now = Date()
        return hackathons.filter { $0.status(at: now) != .completed }.count
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Profile Section
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(isMoodleConnected ? Color.theme.primaryAccent : Color.theme.secondaryText)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(profileDisplayName)
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.theme.primaryText)

                            if isMoodleConnected {
                                HStack(spacing: 4) {
                                    Image(systemName: "graduationcap.fill")
                                        .font(.caption2)
                                        .foregroundStyle(Color.theme.primaryAccent)
                                    Text(moodleConnectedSite ?? "Moodle Student Account")
                                        .font(.caption)
                                        .foregroundStyle(Color.theme.secondaryText)
                                }

                                if let host = moodleSiteUrl, !host.isEmpty {
                                    Text(host)
                                        .font(.caption2)
                                        .foregroundStyle(Color.theme.secondaryText)
                                        .lineLimit(1)
                                }
                            } else {
                                Text("No Moodle Account Connected")
                                    .font(.caption)
                                    .foregroundStyle(Color.theme.secondaryText)
                            }
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.theme.cardBackground)

                // MARK: - Primary Navigation Features
                Section("Activity & Workspaces") {
                    // Completed Tasks Archive
                    NavigationLink {
                        CompletedTasksView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.body)
                                .foregroundStyle(Color.theme.success)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Completed Tasks")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color.theme.primaryText)
                                Text("Archive of finished assignments and exams")
                                    .font(.caption2)
                                    .foregroundStyle(Color.theme.secondaryText)
                            }

                            Spacer()

                            Text("\(completedTasksCount)")
                                .font(.subheadline)
                                .foregroundStyle(Color.theme.secondaryText)
                        }
                        .padding(.vertical, 2)
                    }

                    // Archived Tasks Archive
                    NavigationLink {
                        ArchivedTasksView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "archivebox.fill")
                                .font(.body)
                                .foregroundStyle(Color.theme.warning)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Archived Tasks")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color.theme.primaryText)
                                Text("Hidden tasks preserved from dashboard")
                                    .font(.caption2)
                                    .foregroundStyle(Color.theme.secondaryText)
                            }

                            Spacer()

                            Text("\(archivedTasksCount)")
                                .font(.subheadline)
                                .foregroundStyle(Color.theme.secondaryText)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listRowBackground(Color.theme.cardBackground)

                // MARK: - Account & Connection Actions
                Section("Moodle Account") {
                    Button {
                        isShowingMoodleSheet = true
                    } label: {
                        HStack {
                            Label(isMoodleConnected ? "Manage Moodle Connection" : "Connect Moodle", systemImage: "graduationcap")
                                .foregroundStyle(Color.theme.primaryText)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(Color.theme.secondaryText)
                        }
                    }

                    if isMoodleConnected {
                        Button(role: .destructive) {
                            isShowingDisconnectAlert = true
                        } label: {
                            Label("Log Out of Moodle", systemImage: "rectangle.portrait.and.arrow.right")
                                .foregroundStyle(Color.theme.overdue)
                        }
                    }
                }
                .listRowBackground(Color.theme.cardBackground)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.theme.mainBackground)
            .navigationTitle("Profile & Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .sheet(isPresented: $isShowingMoodleSheet) {
                MoodleConnectView()
                    .environment(\.modelContext, modelContext)
            }
            .alert("Log Out of Moodle?", isPresented: $isShowingDisconnectAlert) {
                Button("Log Out", role: .destructive) {
                    dismiss()
                    SessionManager.shared.logOut(modelContext: modelContext)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Moodle-imported assignments will be removed. Your manually created assignments, scanned exams, and local hackathons will remain safely preserved.")
            }
        }
    }

    private var profileDisplayName: String {
        if let user = moodleConnectedUser, !user.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let words = user.components(separatedBy: .whitespaces)
            let nameParts = words.filter { word in
                !word.allSatisfy { $0.isNumber } && word.count > 1
            }
            if !nameParts.isEmpty {
                return nameParts.map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined(separator: " ")
            }
            return user.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "Student Account"
    }

    private func disconnectMoodle() {
        MoodleKeychainHelper.deleteToken()
        UserDefaults.standard.removeObject(forKey: "moodle_connected_user")
        UserDefaults.standard.removeObject(forKey: "moodle_connected_site")
        moodleConnectedUser = nil
        moodleConnectedSite = nil
    }
}
