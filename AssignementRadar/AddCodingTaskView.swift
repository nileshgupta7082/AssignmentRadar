//
//  AddCodingTaskView.swift
//  AssignementRadar
//
//  Created for Coding Radar Manual Task Creation.
//

import SwiftUI
import SwiftData

struct AddCodingTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var trackedPlatforms: [TrackedPlatform]

    // Form Fields
    @State private var title: String = ""
    @State private var selectedPlatformId: String = ""
    @State private var selectedPlatformName: String = ""
    @State private var selectedTaskType: CodingTaskType = .practiceProblem
    @State private var difficulty: String = "None"
    @State private var customDifficulty: String = ""
    @State private var topicTags: String = ""
    @State private var hasStartDate: Bool = false
    @State private var startDate: Date = Date().addingTimeInterval(3600)
    @State private var hasDueDate: Bool = false
    @State private var dueDate: Date = Date().addingTimeInterval(86400)
    @State private var officialUrl: String = ""
    @State private var notes: String = ""
    @State private var isCompleted: Bool = false
    @State private var registrationStatus: ContestRegistrationStatus = .interested

    @State private var errorMessage: String? = nil

    private let standardDifficulties = ["None", "Easy", "Medium", "Hard", "Custom"]

    init(preselectedPlatformId: String? = nil, defaultType: CodingTaskType = .practiceProblem) {
        _selectedTaskType = State(initialValue: defaultType)
        if let pid = preselectedPlatformId {
            _selectedPlatformId = State(initialValue: pid)
            let catName = PlatformCatalog.find(id: pid)?.name ?? pid.capitalized
            _selectedPlatformName = State(initialValue: catName)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Section 1: Task Information
                Section("Task Details") {
                    TextField("Problem or Contest Title", text: $title)
                        .font(.body)

                    Picker("Platform", selection: $selectedPlatformId) {
                        ForEach(availablePlatformOptions, id: \.id) { opt in
                            HStack {
                                Circle()
                                    .fill(PlatformCatalog.color(for: opt.id))
                                    .frame(width: 8, height: 8)
                                Text(opt.name)
                            }
                            .tag(opt.id)
                        }
                    }
                    .onChange(of: selectedPlatformId) { _, newId in
                        updatePlatformName(for: newId)
                    }

                    Picker("Type", selection: $selectedTaskType) {
                        ForEach(CodingTaskType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    if selectedTaskType == .contest {
                        Picker("Registration Status", selection: $registrationStatus) {
                            ForEach(ContestRegistrationStatus.allCases) { status in
                                Label(status.rawValue, systemImage: status.iconName).tag(status)
                            }
                        }
                    }
                }

                // Section 2: Metadata (Difficulty & Topics)
                Section("Classification") {
                    Picker("Difficulty", selection: $difficulty) {
                        ForEach(standardDifficulties, id: \.self) { diff in
                            Text(diff).tag(diff)
                        }
                    }

                    if difficulty == "Custom" {
                        TextField("e.g. 1400 or Division 2", text: $customDifficulty)
                    }

                    TextField("Topics / Tags (e.g. DP, Trees)", text: $topicTags)
                }

                // Section 3: Schedule & Deadlines
                Section("Schedule") {
                    Toggle("Set Start Time (Contest / Event)", isOn: $hasStartDate)
                    if hasStartDate {
                        DatePicker("Start Date & Time", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                    }

                    Toggle("Set Submission Deadline", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Deadline", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    }
                }

                // Section 4: Web Link & Notes
                Section("Links & Notes") {
                    TextField("Official Problem / Contest URL", text: $officialUrl)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    TextField("Notes or Strategy", text: $notes, axis: .vertical)
                        .lineLimit(3...6)

                    Toggle("Mark as Completed", isOn: $isCompleted)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Color.red)
                    }
                }
            }
            .navigationTitle("Add Coding Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTask()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.theme.primaryAccent)
                }
            }
            .onAppear {
                initializeDefaultPlatform()
            }
        }
    }

    private var availablePlatformOptions: [(id: String, name: String)] {
        var options: [(id: String, name: String)] = []

        // First user's tracked platforms
        for tp in trackedPlatforms {
            options.append((tp.platformId, tp.platformName))
        }

        // Other catalog platforms not yet added
        for cat in PlatformCatalog.platforms where !options.contains(where: { $0.id == cat.id }) {
            options.append((cat.id, cat.name))
        }

        // Custom option
        options.append(("custom", "Other / Custom"))
        return options
    }

    private func initializeDefaultPlatform() {
        if selectedPlatformId.isEmpty {
            if let firstTracked = trackedPlatforms.first {
                selectedPlatformId = firstTracked.platformId
                selectedPlatformName = firstTracked.platformName
            } else {
                selectedPlatformId = "leetcode"
                selectedPlatformName = "LeetCode"
            }
        }
    }

    private func updatePlatformName(for id: String) {
        if let tracked = trackedPlatforms.first(where: { $0.platformId == id }) {
            selectedPlatformName = tracked.platformName
        } else if let cat = PlatformCatalog.find(id: id) {
            selectedPlatformName = cat.name
        } else {
            selectedPlatformName = "Custom"
        }
    }

    private func saveTask() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            errorMessage = "Please enter a task or contest title."
            return
        }

        var finalUrl: String? = nil
        let cleanUrl = officialUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanUrl.isEmpty {
            if cleanUrl.lowercased().hasPrefix("http://") || cleanUrl.lowercased().hasPrefix("https://") {
                finalUrl = cleanUrl
            } else {
                finalUrl = "https://\(cleanUrl)"
            }
        }

        var finalDifficulty: String? = nil
        if difficulty == "Custom" {
            let cleanCust = customDifficulty.trimmingCharacters(in: .whitespacesAndNewlines)
            finalDifficulty = cleanCust.isEmpty ? nil : cleanCust
        } else if difficulty != "None" {
            finalDifficulty = difficulty
        }

        let cleanTags = topicTags.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTags = cleanTags.isEmpty ? nil : cleanTags

        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let task = CodingTask(
            title: cleanTitle,
            platformId: selectedPlatformId,
            platformName: selectedPlatformName,
            taskType: selectedTaskType,
            registrationStatus: registrationStatus,
            difficulty: finalDifficulty,
            topicTags: finalTags,
            startDate: hasStartDate ? startDate : nil,
            dueDate: hasDueDate ? dueDate : nil,
            officialUrl: finalUrl,
            notes: cleanNotes,
            isCompleted: isCompleted
        )

        modelContext.insert(task)
        try? modelContext.save()

        Task {
            let descriptor = FetchDescriptor<CodingTask>()
            let allTasks = (try? modelContext.fetch(descriptor)) ?? [task]
            await CodingNotificationManager.shared.reconcile(tasks: allTasks)
        }

        dismiss()
    }
}
