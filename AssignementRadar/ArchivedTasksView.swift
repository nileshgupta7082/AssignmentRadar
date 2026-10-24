//
//  ArchivedTasksView.swift
//  AssignementRadar
//
//  Created for Assignment Radar Task Archival Management & UI Refinement.
//

import SwiftUI
import SwiftData

/// Dedicated view displaying archived assignments with options to restore or delete.
struct ArchivedTasksView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(
        filter: #Predicate<Assignment> { $0.isArchived },
        sort: \Assignment.dueDate,
        order: .forward
    ) private var archivedAssignments: [Assignment]

    @State private var assignmentToDelete: Assignment? = nil
    @State private var isShowingDeleteAlert: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if archivedAssignments.isEmpty {
                    ContentUnavailableView {
                        Label("No Archived Tasks", systemImage: "archivebox")
                    } description: {
                        Text("Tasks you swipe left to archive from your main dashboard will be safely preserved here away from your active views.")
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            HStack(spacing: 12) {
                                Image(systemName: "archivebox.fill")
                                    .font(.title3)
                                    .foregroundStyle(Color.theme.warning)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(archivedAssignments.count) Archived Tasks")
                                        .font(.headline)
                                        .foregroundStyle(Color.theme.primaryText)
                                    Text("Archived tasks are excluded from your active dashboard and reminder alerts. You can restore them anytime.")
                                        .font(.caption)
                                        .foregroundStyle(Color.theme.secondaryText)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Color.theme.cardBackground)

                        Section("Archived Tasks") {
                            ForEach(archivedAssignments) { assignment in
                                archivedTaskRow(assignment: assignment)
                            }
                        }
                        .listRowBackground(Color.theme.cardBackground)
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Color.theme.mainBackground)
                }
            }
            .background(Color.theme.mainBackground)
            .navigationTitle("Archived Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .alert("Delete Assignment", isPresented: $isShowingDeleteAlert, presenting: assignmentToDelete) { item in
                Button("Delete", role: .destructive) {
                    modelContext.delete(item)
                    try? modelContext.save()
                }
                Button("Cancel", role: .cancel) {}
            } message: { item in
                Text("Are you sure you want to permanently delete '\(item.title)'? This action cannot be undone.")
            }
        }
    }

    private func archivedTaskRow(assignment: Assignment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(assignment.title)
                        .font(.headline)
                        .foregroundStyle(Color.theme.primaryText)

                    if !assignment.course.isEmpty {
                        Text(assignment.course)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.theme.secondarySurface)
                            .foregroundStyle(Color.theme.primaryText)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                Spacer()

                // Exam Badge
                if assignment.isExam {
                    HStack(spacing: 3) {
                        Image(systemName: "graduationcap.circle.fill")
                            .font(.caption2)
                        Text("Exam")
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.theme.examSurface)
                    .foregroundStyle(Color.theme.exam)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                // Priority Badge
                Text(assignment.priority.rawValue)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.theme.secondarySurface)
                    .foregroundStyle(Color.theme.secondaryText)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                // Completed Badge if applicable
                if assignment.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.theme.success)
                        .font(.subheadline)
                }
            }

            // Due Date or Exam Session
            HStack(spacing: 4) {
                Image(systemName: assignment.isExam ? "calendar.badge.clock" : "calendar")
                    .font(.caption2)
                if assignment.isExam {
                    if let session = assignment.sessionTime, !session.isEmpty {
                        Text("Exam: \(assignment.dueDate.formatted(date: .abbreviated, time: .omitted)) • \(session)")
                    } else {
                        Text("Exam: \(assignment.effectiveDate.formatted(date: .abbreviated, time: .shortened))")
                    }
                } else {
                    Text("Due: \(assignment.dueDate.formatted(date: .abbreviated, time: .shortened))")
                }
            }
            .font(.caption)
            .foregroundStyle(Color.theme.secondaryText)

            // Action Buttons: Restore & Delete
            HStack(spacing: 12) {
                Button {
                    withAnimation {
                        restoreAssignment(assignment)
                    }
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward.circle.fill")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.theme.primaryAccent)
                .controlSize(.small)

                Button(role: .destructive) {
                    assignmentToDelete = assignment
                    isShowingDeleteAlert = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }

    private func restoreAssignment(_ assignment: Assignment) {
        assignment.isArchived = false
        if !assignment.isCompleted {
            NotificationService.shared.scheduleReminders(for: assignment)
        }
        try? modelContext.save()
    }
}
