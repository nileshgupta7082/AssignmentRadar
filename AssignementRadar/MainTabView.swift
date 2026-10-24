//
//  MainTabView.swift
//  AssignementRadar
//
//  Created for Assignment Radar & Coding Radar Root Workspace Navigation.
//

import SwiftUI
import SwiftData

/// The two primary workspaces of the application.
enum AppWorkspace: String, CaseIterable, Identifiable {
    case assignmentRadar = "academic"
    case codingRadar = "coding"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .assignmentRadar: return "Assignment Radar"
        case .codingRadar: return "Coding Radar"
        }
    }

    var tabLabel: String {
        switch self {
        case .assignmentRadar: return "Assignment Radar"
        case .codingRadar: return "Coding Radar"
        }
    }

    var iconName: String {
        switch self {
        case .assignmentRadar: return "graduationcap.fill"
        case .codingRadar: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

/// Root container view providing immediate, predictable switching between Assignment Radar and Coding Radar.
struct MainTabView: View {
    @AppStorage("selected_app_workspace") private var selectedWorkspaceRaw: String = AppWorkspace.assignmentRadar.rawValue
    @EnvironmentObject private var sessionManager: SessionManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(named: "CardBackground") ?? UIColor(red: 0.14, green: 0.17, blue: 0.14, alpha: 1.0)
        appearance.shadowColor = UIColor(white: 0.15, alpha: 0.4)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    private var selectedWorkspace: Binding<AppWorkspace> {
        Binding(
            get: { AppWorkspace(rawValue: selectedWorkspaceRaw) ?? .assignmentRadar },
            set: { newWorkspace in
                guard newWorkspace.rawValue != selectedWorkspaceRaw else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    selectedWorkspaceRaw = newWorkspace.rawValue
                }
            }
        )
    }

    var body: some View {
        TabView(selection: selectedWorkspace) {
            // Workspace 1: Assignment Radar (Academic)
            Group {
                if sessionManager.isAuthenticated {
                    ContentView()
                } else {
                    MoodleLoginView()
                }
            }
            .tabItem {
                Label(AppWorkspace.assignmentRadar.tabLabel, systemImage: AppWorkspace.assignmentRadar.iconName)
            }
            .tag(AppWorkspace.assignmentRadar)

            // Workspace 2: Coding Radar (Competitive Programming & Challenges)
            CodingRadarDashboardView()
                .tabItem {
                    Label(AppWorkspace.codingRadar.tabLabel, systemImage: AppWorkspace.codingRadar.iconName)
                }
                .tag(AppWorkspace.codingRadar)
        }
        .tint(Color.theme.primaryAccent)
        .background(Color.theme.mainBackground)
        .animation(.easeInOut(duration: 0.25), value: selectedWorkspaceRaw)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    let descriptor = FetchDescriptor<CodingTask>()
                    let tasks = (try? modelContext.fetch(descriptor)) ?? []
                    await CodingNotificationManager.shared.reconcile(tasks: tasks)
                }
            }
        }
        .task {
            let descriptor = FetchDescriptor<CodingTask>()
            let tasks = (try? modelContext.fetch(descriptor)) ?? []
            await CodingNotificationManager.shared.reconcile(tasks: tasks)
        }
    }
}
