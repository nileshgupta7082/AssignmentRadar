//
//  AssignementRadarApp.swift
//  AssignementRadar
//
//  Created by KIET4 on 23/10/26.
//

import SwiftUI
import SwiftData

@main
struct AssignementRadarApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Assignment.self,
            Hackathon.self,
            CodingTask.self,
            TrackedPlatform.self,
            CodingActivityRecord.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            print("Failed to initialize persistent ModelContainer: \(error). Falling back to fresh in-memory container.")
            do {
                let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                return try ModelContainer(for: schema, configurations: [fallbackConfig])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    @AppStorage("selected_app_theme") private var selectedThemeRaw: String = AppTheme.system.rawValue
    @StateObject private var sessionManager = SessionManager.shared
    @State private var isShowingLaunchAnimation: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {
        // Register NotificationService as UNUserNotificationCenter delegate at app launch
        _ = NotificationService.shared
    }

    private var currentColorScheme: ColorScheme? {
        (AppTheme(rawValue: selectedThemeRaw) ?? .system).colorScheme
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                MainTabView()

                if isShowingLaunchAnimation {
                    LaunchMotifView(isShowing: $isShowingLaunchAnimation, reduceMotion: reduceMotion)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.03)))
                        .zIndex(100)
                }
            }
            .environmentObject(sessionManager)
            .preferredColorScheme(currentColorScheme)
            .background(Color.theme.mainBackground)
        }
        .modelContainer(sharedModelContainer)
    }
}

// MARK: - Lightweight Radar Launch Motif

struct LaunchMotifView: View {
    @Binding var isShowing: Bool
    let reduceMotion: Bool

    @State private var pulseScale: CGFloat = 0.88
    @State private var ringScale: CGFloat = 0.75
    @State private var ringOpacity: Double = 0.75

    var body: some View {
        ZStack {
            Color.theme.mainBackground
                .ignoresSafeArea()

            VStack(spacing: 20) {
                // Radar Motif
                ZStack {
                    // Outer subtle radar pulse ring
                    Circle()
                        .stroke(Color.theme.primaryAccent.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 124, height: 124)
                        .scaleEffect(reduceMotion ? 1.0 : ringScale)
                        .opacity(reduceMotion ? 0.35 : ringOpacity)

                    // Inner radar ring
                    Circle()
                        .stroke(Color.theme.primaryAccent.opacity(0.45), lineWidth: 1.5)
                        .frame(width: 82, height: 82)

                    // Center radar glow
                    Circle()
                        .fill(Color.theme.primaryAccent.opacity(0.12))
                        .frame(width: 64, height: 64)

                    // Center radar scanner icon
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Color.theme.primaryAccent)
                        .scaleEffect(reduceMotion ? 1.0 : pulseScale)
                }

                VStack(spacing: 6) {
                    Text("Assignment Radar")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.theme.primaryText)

                    Text("Academic Deadlines & Exams")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.theme.secondaryText)
                }
            }
        }
        .onAppear {
            if reduceMotion {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isShowing = false
                    }
                }
            } else {
                withAnimation(.easeInOut(duration: 0.5)) {
                    pulseScale = 1.0
                    ringScale = 1.18
                    ringOpacity = 0.08
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        isShowing = false
                    }
                }
            }
        }
    }
}

