//
//  MoodleLoginView.swift
//  AssignementRadar
//
//  Created for Moodle-First Login Screen.
//

import SwiftUI
import SwiftData

struct MoodleLoginView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var sessionManager = SessionManager.shared

    // Form inputs (Fixed college Moodle endpoint: http://lms.kiet.edu/moodle)
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var isPasswordVisible: Bool = false

    // State
    @State private var isAuthenticating: Bool = false
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header Logo & Branding
                    VStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color.theme.softAccentSurface)
                                .frame(width: 64, height: 64)

                            Image(systemName: "graduationcap.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(Color.theme.primaryAccent)
                        }
                        .padding(.top, 16)

                        VStack(spacing: 4) {
                            Text("Assignment Radar")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.theme.primaryText)

                            Text("Sign in with your university Moodle account to automatically sync course deadlines and academic schedules.")
                                .font(.footnote)
                                .foregroundStyle(Color.theme.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                    }

                    // Login Card
                    VStack(alignment: .leading, spacing: 14) {
                        // Username Field
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Username")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.theme.secondaryText)

                            TextField("Student ID or username", text: $username)
                                .font(.subheadline)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .padding(10)
                                .background(Color.theme.secondarySurface)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(Color.theme.primaryText)
                        }

                        // Password Field
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Password")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.theme.secondaryText)

                            HStack {
                                if isPasswordVisible {
                                    TextField("Password", text: $password)
                                        .font(.subheadline)
                                        .autocorrectionDisabled()
                                        .textInputAutocapitalization(.never)
                                } else {
                                    SecureField("Password", text: $password)
                                        .font(.subheadline)
                                        .autocorrectionDisabled()
                                        .textInputAutocapitalization(.never)
                                }

                                Button {
                                    isPasswordVisible.toggle()
                                } label: {
                                    Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                        .font(.footnote)
                                        .foregroundStyle(Color.theme.secondaryText)
                                }
                            }
                            .padding(10)
                            .background(Color.theme.secondarySurface)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(Color.theme.primaryText)
                        }

                        // Error message
                        if let error = errorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(Color.theme.overdue)
                                Text(error)
                                    .font(.caption2)
                                    .foregroundStyle(Color.theme.overdue)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.theme.overdueSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        // Sign In Button
                        Button {
                            Task {
                                await performLogin()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if isAuthenticating {
                                    ProgressView()
                                        .tint(Color.theme.mainBackground)
                                    Text("Signing In...")
                                        .font(.callout)
                                        .fontWeight(.semibold)
                                } else {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.callout)
                                    Text("Sign In with Moodle")
                                        .font(.callout)
                                        .fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.theme.primaryAccent)
                            .foregroundStyle(Color.theme.mainBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .disabled(isAuthenticating || username.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
                        .opacity((username.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty) ? 0.6 : 1.0)
                    }
                    .padding(18)
                    .background(Color.theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 16)

                    // Secondary Action: Continue Offline / Local Mode
                    VStack(spacing: 6) {
                        Button {
                            sessionManager.continueAsGuest()
                        } label: {
                            Text("Continue with Local Workspaces & Notice Scanner")
                                .font(.footnote)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.theme.primaryAccent)
                        }

                        Text("You can sign in with Moodle anytime from the profile menu.")
                            .font(.caption2)
                            .foregroundStyle(Color.theme.secondaryText)
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 20)
                }
            }
            .background(Color.theme.mainBackground)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func performLogin() async {
        isAuthenticating = true
        errorMessage = nil

        let endpoint = MoodleService.defaultSiteUrl
        UserDefaults.standard.set(endpoint, forKey: "moodle_site_url")

        let cleanUser = username.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let token = try await MoodleService.shared.login(
                siteUrl: endpoint,
                username: cleanUser,
                password: password
            )

            // Test connection to fetch student display name
            let siteInfo = try await MoodleService.shared.testConnection(
                siteUrl: endpoint,
                token: token
            )

            let displayName = siteInfo.displayName
            let siteName = siteInfo.sitename ?? "KIET Moodle LMS"

            // Save session with user account ID and transition to dashboard
            sessionManager.logInWithMoodle(
                user: displayName,
                site: siteName,
                accountId: cleanUser.lowercased()
            )

            // Trigger fresh background synchronization
            Task {
                await RefreshCoordinator.shared.refreshAll(modelContext: modelContext)
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }

        isAuthenticating = false
    }
}
