//
//  PlatformDetailSheetView.swift
//  AssignementRadar
//
//  Created for Coding Radar Platform Settings & Manual Configuration.
//

import SwiftUI
import SwiftData

struct PlatformDetailSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    @Bindable var platform: TrackedPlatform

    @ObservedObject private var leetCodeProvider = LeetCodeProvider.shared
    @ObservedObject private var gfgProvider = GeeksForGeeksProvider.shared

    @State private var profileUrlText: String = ""
    @State private var customNotesText: String = ""
    @State private var isShowingRemoveAlert: Bool = false
    @State private var isShowingAddTaskSheet: Bool = false
    @State private var importStatusMessage: String? = nil

    private var catalogInfo: CatalogPlatform? {
        PlatformCatalog.find(id: platform.platformId)
    }

    private var statusBadgeText: String {
        if platform.platformId == "leetcode" || platform.platformId == "gfg" {
            return "Live Data Available"
        }
        if let pUrl = platform.profileUrl, !pUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Profile link saved"
        }
        return "Manual tracking"
    }

    var body: some View {
        NavigationStack {
            Form {
                // Section 1: Platform Header
                Section {
                    let platformColor = PlatformCatalog.color(for: platform.platformId)

                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(platformColor.opacity(0.14))
                                .frame(width: 44, height: 44)

                            Image(systemName: catalogInfo?.iconName ?? "terminal")
                                .font(.system(size: 20))
                                .foregroundStyle(platformColor)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(platform.platformName)
                                .font(.headline)
                                .foregroundStyle(Color.theme.primaryText)

                            Text(statusBadgeText)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.theme.secondaryText)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)

                    // Open Official Website Button
                    if let webUrl = catalogInfo?.websiteUrl {
                        Button {
                            openURL(webUrl)
                        } label: {
                            HStack {
                                Label("Open Official Website", systemImage: "arrow.up.right.square")
                                    .font(.subheadline)
                                Spacer()
                            }
                        }
                    }
                }

                // Section 2: Profile URL (Optional)
                Section("Student Profile Link") {
                    TextField("https://platform.com/profile/username", text: $profileUrlText)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .font(.subheadline)

                    HStack {
                        Button("Save Profile Link") {
                            saveProfileUrl()
                        }
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.theme.primaryAccent)

                        Spacer()

                        if let savedUrl = platform.profileUrl, let url = URL(string: savedUrl) {
                            Button {
                                openURL(url)
                            } label: {
                                Label("Open Profile", systemImage: "safari")
                                    .font(.footnote)
                            }
                        }
                    }
                }

                // Section 3: Automatic Imports for Supported Providers
                if platform.platformId == "leetcode" || platform.platformId == "gfg" {
                    Section("Live Challenge Feed") {
                        Button {
                            importTodayChallenge()
                        } label: {
                            HStack {
                                Label("Import Today's Daily Question", systemImage: "arrow.down.circle")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                            }
                        }

                        if let msg = importStatusMessage {
                            Text(msg)
                                .font(.caption)
                                .foregroundStyle(Color.theme.primaryAccent)
                        }
                    }
                }

                // Section 4: Quick Actions
                Section("Actions") {
                    Button {
                        isShowingAddTaskSheet = true
                    } label: {
                        HStack {
                            Label("Add Coding Task for \(platform.platformName)", systemImage: "plus.circle")
                                .font(.subheadline)
                            Spacer()
                        }
                    }
                }

                // Section 5: Remove Platform (Safe)
                Section {
                    Button(role: .destructive) {
                        isShowingRemoveAlert = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Remove from My Platforms")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                        }
                    }
                } footer: {
                    Text("Removing \(platform.platformName) removes it from your dashboard view. Your saved coding tasks and history will remain intact.")
                        .font(.caption2)
                        .foregroundStyle(Color.theme.secondaryText)
                }
            }
            .navigationTitle(platform.platformName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                profileUrlText = platform.profileUrl ?? ""
                customNotesText = platform.customNotes
            }
            .alert("Remove \(platform.platformName)?", isPresented: $isShowingRemoveAlert) {
                Button("Remove", role: .destructive) {
                    removePlatformSafely()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This platform will be removed from your dashboard. All of your coding tasks and completion records will be kept.")
            }
            .sheet(isPresented: $isShowingAddTaskSheet) {
                AddCodingTaskView(preselectedPlatformId: platform.platformId)
            }
        }
    }

    private func saveProfileUrl() {
        let clean = profileUrlText.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            platform.profileUrl = nil
        } else if clean.lowercased().hasPrefix("http://") || clean.lowercased().hasPrefix("https://") {
            platform.profileUrl = clean
        } else {
            platform.profileUrl = "https://\(clean)"
        }
        try? modelContext.save()
        profileUrlText = platform.profileUrl ?? ""
    }

    private func importTodayChallenge() {
        Task {
            await RefreshCoordinator.shared.refreshCoding(modelContext: modelContext)
            await MainActor.run {
                importStatusMessage = "Synced latest live challenge and contests for \(platform.platformName)."
            }
        }
    }

    private func removePlatformSafely() {
        // Safe deletion: removes platform configuration without touching user's coding tasks!
        modelContext.delete(platform)
        try? modelContext.save()
        dismiss()
    }
}
