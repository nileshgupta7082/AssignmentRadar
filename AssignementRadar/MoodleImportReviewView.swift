//
//  MoodleImportReviewView.swift
//  AssignementRadar
//
//  Created for Moodle Deadline Integration.
//

import SwiftUI
import SwiftData

/// Editable review screen for Moodle-imported deadlines with duplicate detection and selective saving.
struct MoodleImportReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Binding var drafts: [MoodleDraft]
    var onImportCompleted: (() -> Void)? = nil

    private var selectedCount: Int {
        drafts.filter { $0.isSelected }.count
    }

    private var duplicateCount: Int {
        drafts.filter { $0.isDuplicate }.count
    }

    var body: some View {
        NavigationStack {
            List {
                // Summary & Guidance Banner
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.blue)
                            Text("Ready to Import")
                                .font(.headline)
                        }

                        Text("Select which deadlines to save to your local Radar. Items already in your Radar are marked and unchecked by default.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if duplicateCount > 0 {
                            HStack {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                                Text("\(duplicateCount) potential duplicate(s) detected.")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                Spacer()
                                Button("Deselect Duplicates") {
                                    for i in drafts.indices where drafts[i].isDuplicate {
                                        drafts[i].isSelected = false
                                    }
                                }
                                .font(.caption)
                                .fontWeight(.semibold)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // List of Moodle Drafts
                Section("Deadlines to Review (\(selectedCount) selected)") {
                    ForEach($drafts) { $draft in
                        moodleDraftRow(draft: $draft)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Review Deadlines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Import (\(selectedCount))") {
                        confirmImport()
                    }
                    .disabled(selectedCount == 0)
                    .fontWeight(.bold)
                }
            }
        }
    }

    // MARK: - Row Subview

    private func moodleDraftRow(draft: Binding<MoodleDraft>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Checkbox, Activity Type badge, and Duplicate tag
            HStack(spacing: 8) {
                Button {
                    draft.wrappedValue.isSelected.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: draft.wrappedValue.isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(draft.wrappedValue.isSelected ? .blue : .secondary)
                        Text(draft.wrappedValue.isSelected ? "Import" : "Skip")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(draft.wrappedValue.isSelected ? .primary : .secondary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                // Activity type badge (e.g., Assignment, Quiz)
                Text(draft.wrappedValue.activityType)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.12))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())

                // Duplicate badge
                if draft.wrappedValue.isDuplicate {
                    Text("Duplicate")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }

                // Delete draft from list
                Button(role: .destructive) {
                    if let idx = drafts.firstIndex(where: { $0.id == draft.wrappedValue.id }) {
                        drafts.remove(at: idx)
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }

            // Editable Title
            VStack(alignment: .leading, spacing: 2) {
                Text("Title")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextField("Title", text: draft.title)
                    .textFieldStyle(.roundedBorder)
            }

            // Editable Course
            VStack(alignment: .leading, spacing: 2) {
                Text("Course")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextField("Course", text: draft.course)
                    .textFieldStyle(.roundedBorder)
            }

            // Due Date Picker
            DatePicker("Due Date", selection: draft.dueDate, displayedComponents: [.date, .hourAndMinute])
                .font(.subheadline)

            // Priority Picker
            Picker("Priority", selection: draft.priority) {
                ForEach(Priority.allCases) { p in
                    Text(p.rawValue).tag(p)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 6)
        .opacity(draft.wrappedValue.isSelected ? 1.0 : 0.6)
    }

    // MARK: - Save Confirmed Records

    private func confirmImport() {
        let itemsToImport = drafts.filter { $0.isSelected }

        let descriptor = FetchDescriptor<Assignment>()
        let existingList = (try? modelContext.fetch(descriptor)) ?? []

        for draft in itemsToImport {
            let cleanTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanCourse = draft.course.trimmingCharacters(in: .whitespacesAndNewlines)

            // Check if matching assignment already exists in SwiftData
            if let existing = existingList.first(where: {
                if let mId = $0.moodleEventId, mId == draft.moodleEventId { return true }
                return $0.title.caseInsensitiveCompare(cleanTitle) == .orderedSame &&
                       $0.course.caseInsensitiveCompare(cleanCourse) == .orderedSame
            }) {
                // Update properties but PRESERVE existing completion status
                existing.dueDate = draft.dueDate
                existing.priority = draft.priority
                existing.notes = draft.notes
                existing.sourceUrl = draft.sourceUrl
                existing.moodleEventId = draft.moodleEventId
                // existing.isCompleted is preserved!
                if existing.isCompleted {
                    NotificationService.shared.cancelReminders(for: existing.id)
                } else {
                    NotificationService.shared.scheduleReminders(for: existing)
                }
            } else {
                let newAssignment = Assignment(
                    title: cleanTitle,
                    course: cleanCourse,
                    dueDate: draft.dueDate,
                    priority: draft.priority,
                    notes: draft.notes,
                    isCompleted: false,
                    source: "moodle",
                    moodleEventId: draft.moodleEventId,
                    sourceUrl: draft.sourceUrl
                )
                modelContext.insert(newAssignment)
                NotificationService.shared.scheduleReminders(for: newAssignment)
            }
        }

        try? modelContext.save()
        onImportCompleted?()
        dismiss()
    }
}
