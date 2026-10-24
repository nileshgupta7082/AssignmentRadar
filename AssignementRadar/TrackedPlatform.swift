//
//  TrackedPlatform.swift
//  AssignementRadar
//
//  Created for Coding Radar Platform Management.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Tracked Platform SwiftData Model

/// Represents a platform chosen by the user for active tracking in Coding Radar.
/// Each platform starts NOT added by default. Removing a platform preserves all associated tasks.
@Model
final class TrackedPlatform {
    var id: UUID = UUID()
    var platformId: String = ""
    var platformName: String = ""
    var profileUrl: String? = nil
    var customHandle: String? = nil
    var customNotes: String = ""
    var addedAt: Date = Date()
    var isManualTrackingEnabled: Bool = true

    init(
        platformId: String,
        platformName: String,
        profileUrl: String? = nil,
        customHandle: String? = nil,
        customNotes: String = "",
        isManualTrackingEnabled: Bool = true
    ) {
        self.id = UUID()
        self.platformId = platformId
        self.platformName = platformName
        self.profileUrl = profileUrl
        self.customHandle = customHandle
        self.customNotes = customNotes
        self.addedAt = Date()
        self.isManualTrackingEnabled = isManualTrackingEnabled
    }
}

// MARK: - Platform Catalog Definition

/// Fixed catalog definition of supported competitive programming platforms.
struct CatalogPlatform: Identifiable, Hashable {
    let id: String
    let name: String
    let websiteUrl: URL
    let iconName: String
    let subtitle: String
    let supportsAutomaticData: Bool
    let integrationStatusLabel: String
    let accentHex: String

    var accentColor: Color {
        Color(hex: accentHex)
    }

    var defaultUrlString: String {
        websiteUrl.absoluteString
    }
}

enum PlatformCatalog {
    static let platforms: [CatalogPlatform] = [
        CatalogPlatform(
            id: "leetcode",
            name: "LeetCode",
            websiteUrl: URL(string: "https://leetcode.com")!,
            iconName: "chevron.left.forwardslash.chevron.right",
            subtitle: "Daily challenges & weekly contests",
            supportsAutomaticData: true,
            integrationStatusLabel: "Live Data Available",
            accentHex: "#FFA116"
        ),
        CatalogPlatform(
            id: "gfg",
            name: "GeeksforGeeks",
            websiteUrl: URL(string: "https://practice.geeksforgeeks.org")!,
            iconName: "curlybraces",
            subtitle: "Problem of the Day & practice",
            supportsAutomaticData: true,
            integrationStatusLabel: "Live Data Available",
            accentHex: "#2F8D46"
        ),
        CatalogPlatform(
            id: "codeforces",
            name: "Codeforces",
            websiteUrl: URL(string: "https://codeforces.com")!,
            iconName: "chart.bar.xaxis",
            subtitle: "Rated rounds & problem archive",
            supportsAutomaticData: false,
            integrationStatusLabel: "Manual tracking",
            accentHex: "#6599FF"
        ),
        CatalogPlatform(
            id: "codechef",
            name: "CodeChef",
            websiteUrl: URL(string: "https://www.codechef.com")!,
            iconName: "fork.knife",
            subtitle: "Starters, Cook-Off & challenges",
            supportsAutomaticData: false,
            integrationStatusLabel: "Manual tracking",
            accentHex: "#E9B44C"
        ),
        CatalogPlatform(
            id: "atcoder",
            name: "AtCoder",
            websiteUrl: URL(string: "https://atcoder.jp")!,
            iconName: "a.circle",
            subtitle: "Beginner, Regular & Grand contests",
            supportsAutomaticData: false,
            integrationStatusLabel: "Manual tracking",
            accentHex: "#8C96A8"
        ),
        CatalogPlatform(
            id: "hackerrank",
            name: "HackerRank",
            websiteUrl: URL(string: "https://www.hackerrank.com")!,
            iconName: "h.square",
            subtitle: "Skill certification & practice kits",
            supportsAutomaticData: false,
            integrationStatusLabel: "Manual tracking",
            accentHex: "#2EC866"
        ),
        CatalogPlatform(
            id: "codestudio",
            name: "CodeStudio / Coding Ninjas",
            websiteUrl: URL(string: "https://www.naukri.com/code360")!,
            iconName: "laptopcomputer",
            subtitle: "Interview prep & guided paths",
            supportsAutomaticData: false,
            integrationStatusLabel: "Manual tracking",
            accentHex: "#B78AFF"
        )
    ]

    static func find(id: String) -> CatalogPlatform? {
        platforms.first { $0.id.lowercased() == id.lowercased() || $0.name.lowercased() == id.lowercased() }
    }

    /// Retrieves the platform-specific visual accent color with fallback to the primary theme accent.
    static func color(for platformNameOrId: String) -> Color {
        let clean = platformNameOrId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean.contains("leetcode") { return Color(hex: "#FFA116") }
        if clean.contains("geeks") || clean.contains("gfg") { return Color(hex: "#2F8D46") }
        if clean.contains("codeforces") { return Color(hex: "#6599FF") }
        if clean.contains("codechef") { return Color(hex: "#E9B44C") }
        if clean.contains("atcoder") { return Color(hex: "#8C96A8") }
        if clean.contains("hacker") { return Color(hex: "#2EC866") }
        if clean.contains("codestudio") || clean.contains("ninja") { return Color(hex: "#B78AFF") }

        if let matched = find(id: clean) {
            return matched.accentColor
        }
        return Color.theme.primaryAccent
    }
}
