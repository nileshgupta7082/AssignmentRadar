//
//  AddPlatformCatalogView.swift
//  AssignementRadar
//
//  Created for Coding Radar Platform Catalog Selection.
//

import SwiftUI
import SwiftData

struct AddPlatformCatalogView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var trackedPlatforms: [TrackedPlatform]

    @State private var selectedCatalogPlatform: CatalogPlatform? = nil

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Select competitive programming platforms to track on your Coding Radar dashboard. Each platform operates with manual tracking or official live feeds.")
                        .font(.footnote)
                        .foregroundStyle(Color.theme.secondaryText)
                }
                .listRowBackground(Color.clear)

                Section("Supported Platforms") {
                    ForEach(PlatformCatalog.platforms) { platform in
                        let isTracked = trackedPlatforms.contains(where: { $0.platformId == platform.id })

                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(platform.accentColor.opacity(0.14))
                                    .frame(width: 38, height: 38)

                                Image(systemName: platform.iconName)
                                    .font(.system(size: 17))
                                    .foregroundStyle(platform.accentColor)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(platform.name)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Color.theme.primaryText)

                                    if platform.supportsAutomaticData {
                                        Text("Live Feed")
                                            .font(.system(size: 10, weight: .bold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Color.theme.successSurface)
                                            .foregroundStyle(Color.theme.success)
                                            .clipShape(Capsule())
                                    } else {
                                        Text("Manual")
                                            .font(.system(size: 10, weight: .medium))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Color.theme.secondarySurface)
                                            .foregroundStyle(Color.theme.secondaryText)
                                            .clipShape(Capsule())
                                    }
                                }

                                Text(platform.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(Color.theme.secondaryText)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if isTracked {
                                Button {
                                    selectedCatalogPlatform = platform
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: "checkmark")
                                            .font(.caption2.bold())
                                        Text("Added")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(Color.theme.secondarySurface)
                                    .foregroundStyle(Color.theme.primaryAccent)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button {
                                    addPlatform(platform)
                                } label: {
                                    Text("+ Add")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 5)
                                        .background(Color.theme.primaryAccent)
                                        .foregroundStyle(Color.theme.cardBackground)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Platform Catalog")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.medium)
                }
            }
            .sheet(item: $selectedCatalogPlatform) { platform in
                if let tracked = trackedPlatforms.first(where: { $0.platformId == platform.id }) {
                    PlatformDetailSheetView(platform: tracked)
                }
            }
        }
    }

    private func addPlatform(_ catalog: CatalogPlatform) {
        guard !trackedPlatforms.contains(where: { $0.platformId == catalog.id }) else { return }
        let newTracked = TrackedPlatform(
            platformId: catalog.id,
            platformName: catalog.name,
            profileUrl: nil,
            customHandle: nil,
            customNotes: "",
            isManualTrackingEnabled: true
        )
        modelContext.insert(newTracked)
        try? modelContext.save()

        Task {
            await RefreshCoordinator.shared.refreshCoding(modelContext: modelContext)
        }
    }
}
