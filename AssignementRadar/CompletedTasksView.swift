//
//  CompletedTasksView.swift
//  AssignementRadar
//
//  Created for Assignment Radar Completed Tasks Archive & UI Refinement.
//

import SwiftUI
import SwiftData

/// Dedicated view displaying completed academic assignments from the real SwiftData store.
struct CompletedTasksView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(
        filter: #Predicate<Assignment> { $0.isCompleted && !$0.isArchived },
        sort: \Assignment.dueDate,
        order: .reverse
    ) private var completedAssignments: [Assignment]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if completedAssignments.isEmpty {
                    ContentUnavailableView {
                        Label("No Completed Tasks Yet", systemImage: "checkmark.circle")
                    } description: {
                        Text("Assignments you mark as finished on your dashboard will be cataloged here for your records.")
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(Color.theme.success)
                                    .font(.title3)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(completedAssignments.count) Finished Tasks")
                                        .font(.headline)
                                        .foregroundStyle(Color.theme.primaryText)
                                    Text("These assignments remain saved in your records and visible in the All dashboard view.")
                                        .font(.caption)
                                        .foregroundStyle(Color.theme.secondaryText)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Color.theme.cardBackground)

                        Section("Completed Tasks") {
                            ForEach(completedAssignments) { assignment in
                                completedTaskRow(assignment: assignment)
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
            .navigationTitle("Completed Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }

    private func completedTaskRow(assignment: Assignment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                withAnimation {
                    assignment.isCompleted.toggle()
                    if assignment.source == "moodle" {
                        MoodleAccountTaskStore.shared.saveState(for: assignment)
                    }
                    TaskSyncCoordinator.shared.recordTaskStateChange(for: assignment)
                    NotificationService.shared.scheduleReminders(for: assignment)
                    try? modelContext.save()
                    Task {
                        await CalendarSyncService.shared.handleAssignmentCompletionChanged(assignment)
                    }
                }
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.theme.primaryAccent)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(assignment.title)
                        .font(.headline)
                        .strikethrough(true, color: Color.theme.secondaryText)
                        .foregroundStyle(Color.theme.secondaryText)
                        .lineLimit(2)

                    Spacer()

                    Text(assignment.priority.rawValue)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.theme.secondarySurface)
                        .foregroundStyle(Color.theme.secondaryText)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                HStack(spacing: 6) {
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

                    if assignment.source == "moodle" {
                        HStack(spacing: 3) {
                            Image(systemName: "graduationcap.fill")
                                .font(.caption2)
                            Text("Moodle")
                                .font(.caption2)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.theme.secondarySurface)
                        .foregroundStyle(Color.theme.secondaryText)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else if assignment.source == "scan" {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.text.viewfinder")
                                .font(.caption2)
                            Text("Scan")
                                .font(.caption2)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.theme.secondarySurface)
                        .foregroundStyle(Color.theme.secondaryText)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

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

                    if assignment.hasValidDeadline {
                        HStack(spacing: 3) {
                            Image(systemName: assignment.isExam ? "calendar.badge.clock" : "calendar")
                                .font(.caption2)
                            if assignment.isExam {
                                if let session = assignment.sessionTime, !session.isEmpty {
                                    Text("\(assignment.dueDate.formatted(date: .abbreviated, time: .omitted)) • \(session)")
                                } else {
                                    Text(assignment.effectiveDate.formatted(date: .abbreviated, time: .shortened))
                                }
                            } else {
                                Text(assignment.dueDate.formatted(date: .abbreviated, time: .shortened))
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(Color.theme.secondaryText)
                    }
                }

                if !assignment.notes.isEmpty {
                    Text(assignment.notes)
                        .font(.caption2)
                        .foregroundStyle(Color.theme.secondaryText)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
