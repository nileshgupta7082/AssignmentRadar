//
//  MarkProblemSolvedSheetView.swift
//  AssignementRadar
//
//  Created for Coding Radar Smart Streak Manual Problem Completion Flow.
//

import SwiftUI
import SwiftData

struct MarkProblemSolvedSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \CodingTask.createdAt, order: .reverse) private var allCodingTasks: [CodingTask]
    @Query(sort: \CodingActivityRecord.completedAt, order: .reverse) private var allActivities: [CodingActivityRecord]

    @State private var selectedPlatformId: String = "leetcode"
    @State private var problemTitle: String = ""
    @State private var problemUrl: String = ""
    @State private var difficulty: String = "Medium"
    @State private var topicTags: String = ""
    @State private var completionDate: Date = Date()
    @State private var notes: String = ""
    @State private var showingValidationAlert: Bool = false
    @State private var validationMessage: String = ""

    private let difficulties = ["Easy", "Medium", "Hard", "Unspecified"]

    private var selectedPlatform: CatalogPlatform? {
        PlatformCatalog.platforms.first { $0.id == selectedPlatformId }
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Verification Info Header
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(Color(hex: "#22C55E"))
                                .font(.title3)

                            Text("Log Solved Problem")
                                .font(.headline)
                                .foregroundStyle(Color.theme.primaryText)
                        }

                        Text("Every solved problem counts toward your daily coding streak. Record completed problems here whenever automatic provider verification is unavailable.")
                            .font(.caption)
                            .foregroundStyle(Color.theme.secondaryText)
                    }
                    .padding(.vertical, 4)
                }

                // MARK: - Platform Picker
                Section("Coding Platform") {
                    Picker("Platform", selection: $selectedPlatformId) {
                        ForEach(PlatformCatalog.platforms) { platform in
                            HStack {
                                Image(systemName: platform.iconName)
                                Text(platform.name)
                            }
                            .tag(platform.id)
                        }
                        Text("Other / Custom").tag("custom")
                    }
                    .pickerStyle(.menu)
                }

                // MARK: - Problem Details
                Section("Problem Information") {
                    TextField("Problem Title (e.g., Two Sum)", text: $problemTitle)
                        .autocorrectionDisabled()

                    TextField("Problem URL (Optional)", text: $problemUrl)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Picker("Difficulty", selection: $difficulty) {
                        ForEach(difficulties, id: \.self) { diff in
                            Text(diff).tag(diff)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Topics / Tags (Optional, comma-separated)", text: $topicTags)
                }

                // MARK: - Date & Time
                Section("Completion Time") {
                    DatePicker(
                        "Solved On",
                        selection: $completionDate,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                // MARK: - Notes
                Section("Notes (Optional)") {
                    TextField("What did you learn or practice?", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                // MARK: - Verification Source Info
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .foregroundStyle(Color.theme.secondaryText)
                        Text("Status: User Confirmed (Eligible for Streak)")
                            .font(.caption)
                            .foregroundStyle(Color.theme.secondaryText)
                    }
                }
            }
            .navigationTitle("Mark Solved")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm Solved") {
                        confirmAndSave()
                    }
                    .fontWeight(.bold)
                    .foregroundStyle(Color(hex: "#22C55E"))
                }
            }
            .alert("Missing Information", isPresented: $showingValidationAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(validationMessage)
            }
        }
    }

    private func confirmAndSave() {
        let trimmedTitle = problemTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            validationMessage = "Please enter a problem title."
            showingValidationAlert = true
            return
        }

        let platformName = selectedPlatform?.name ?? (selectedPlatformId == "custom" ? "Custom Platform" : selectedPlatformId.capitalized)
        let trimmedUrl = problemUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let problemIdentifier = trimmedTitle.lowercased().replacingOccurrences(of: " ", with: "-")

        // 1. Insert new CodingActivityRecord
        let newRecord = CodingActivityRecord(
            platformId: selectedPlatformId,
            platformName: platformName,
            problemTitle: trimmedTitle,
            problemId: problemIdentifier,
            completedAt: completionDate,
            verificationSource: .userConfirmed,
            problemUrl: trimmedUrl.isEmpty ? nil : trimmedUrl,
            difficulty: difficulty == "Unspecified" ? nil : difficulty,
            topicTags: topicTags.isEmpty ? nil : topicTags,
            notes: notes
        )
        modelContext.insert(newRecord)

        // 2. Check if this matches any uncompleted daily question or task in coding tasks
        let calendar = Calendar.current
        for task in allCodingTasks where !task.isCompleted {
            let samePlatform = task.platformId == selectedPlatformId
            let sameDay = calendar.isDate(task.dueDate ?? task.createdAt, inSameDayAs: completionDate)
            let titleMatch = task.title.localizedCaseInsensitiveContains(trimmedTitle) ||
                             trimmedTitle.localizedCaseInsensitiveContains(task.title)

            if samePlatform && (titleMatch || (task.isDailyQuestion && sameDay)) {
                task.isCompleted = true
                task.completedAt = completionDate
            }
        }

        try? modelContext.save()

        // 3. Cancel any pending streak reminder and follow-up for this day
        CodingNotificationManager.shared.cancelTodayStreakReminders(calendar: calendar, now: completionDate)

        // 4. Reconcile notifications
        Task {
            let updatedTasks = (try? modelContext.fetch(FetchDescriptor<CodingTask>())) ?? []
            let updatedActivities = (try? modelContext.fetch(FetchDescriptor<CodingActivityRecord>())) ?? []
            await CodingNotificationManager.shared.reconcile(tasks: updatedTasks, activities: updatedActivities)
        }

        RefreshCoordinator.shared.postStatusMessage("Solved problem recorded! Daily streak active.", isError: false)
        dismiss()
    }
}
