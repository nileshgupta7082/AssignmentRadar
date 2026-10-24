//
//  MoodleConnectView.swift
//  AssignementRadar
//
//  Created for Moodle Deadline Integration.
//

import SwiftUI
import SwiftData

/// Connect view for authenticating directly with Moodle over HTTP/HTTPS, retrieving assignments, and reviewing imports.
struct MoodleConnectView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // Form Inputs
    @State private var siteUrl: String = UserDefaults.standard.string(forKey: "moodle_site_url") ?? "http://lms.kiet.edu/moodle"
    @State private var token: String = MoodleKeychainHelper.loadToken() ?? ""
    @State private var username: String = ""
    @State private var password: String = ""

    // Manual token alternative
    @State private var isShowingManualToken: Bool = false

    // Focus state for smooth keyboard navigation
    private enum FocusableField: Hashable {
        case siteUrl
        case username
        case password
        case token
    }

    @FocusState private var focusedField: FocusableField?

    // Loading & Operation States
    @State private var isAuthenticating: Bool = false
    @State private var isSyncing: Bool = false
    @State private var statusMessage: String? = nil
    @State private var errorMessage: String? = nil

    // Persisted Connection Information
    @State private var connectedUser: String? = UserDefaults.standard.string(forKey: "moodle_connected_user")
    @State private var connectedSite: String? = UserDefaults.standard.string(forKey: "moodle_connected_site")
    @State private var lastSyncDate: Date? = UserDefaults.standard.object(forKey: "moodle_last_sync") as? Date

    // Navigation & Review Sheets
    @State private var fetchedDrafts: [MoodleDraft] = []
    @State private var isShowingReviewSheet: Bool = false
    @State private var isShowingScannerSheet: Bool = false

    private var isConnected: Bool {
        connectedUser != nil && !siteUrl.isEmpty && !token.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Connection Status Header
                Section("Connection Status") {
                    HStack(spacing: 12) {
                        Image(systemName: isConnected ? "checkmark.circle.fill" : "graduationcap.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(isConnected ? .green : .blue)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(isConnected ? "Connected to Moodle" : "Moodle Not Connected")
                                .font(.headline)

                            if let user = connectedUser, let site = connectedSite {
                                Text("\(user) • \(site)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Connect to retrieve assignments and deadlines directly from your LMS.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let lastSync = lastSyncDate {
                                Text("Last synced: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // MARK: - Status Feedback
                if let status = statusMessage {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.theme.success)
                            Text(status)
                                .font(.subheadline)
                                .foregroundStyle(Color.theme.primaryText)
                        }
                    }
                    .listRowBackground(Color.theme.cardBackground)
                }

                // MARK: - Error Feedback
                if let error = errorMessage {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(Color.theme.overdue)
                                Text(error)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.theme.primaryText)
                            }

                            Button {
                                isShowingScannerSheet = true
                            } label: {
                                Label("Use Notice & Datesheet Scanner", systemImage: "doc.text.viewfinder")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color.theme.primaryAccent)
                            }
                            .padding(.top, 2)
                        }
                    }
                    .listRowBackground(Color.theme.cardBackground)
                }

                // MARK: - Connected State Actions
                if isConnected {
                    Section("Assignment Synchronization") {
                        Button {
                            syncAssignments()
                        } label: {
                            HStack {
                                Label("Sync Moodle Assignments", systemImage: "arrow.triangle.2.circlepath")
                                    .fontWeight(.semibold)
                                Spacer()
                                if isSyncing {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isSyncing)
                    }

                    Section {
                        Button(role: .destructive) {
                            disconnect()
                        } label: {
                            Text("Disconnect & Remove Credentials")
                        }
                    }
                } else {
                    // MARK: - Authentication Form
                    Section("Moodle Portal URL") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("College Moodle Website")
                                .font(.caption)
                                .foregroundStyle(Color.theme.secondaryText)

                            TextField("e.g. http://lms.kiet.edu/moodle", text: $siteUrl)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .keyboardType(.URL)
                                .textContentType(.URL)
                                .submitLabel(.next)
                                .focused($focusedField, equals: .siteUrl)
                                .onSubmit {
                                    focusedField = .username
                                }

                            if siteUrl.lowercased().hasPrefix("http://") {
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "exclamationmark.shield")
                                        .font(.caption2)
                                        .foregroundStyle(Color.theme.warning)
                                    Text("Security Notice: Plain HTTP traffic is unencrypted. This connection is allowed exclusively for the college LMS host under a targeted App Transport Security exception. Avoid using sensitive credentials on public or untrusted Wi-Fi.")
                                        .font(.caption2)
                                        .foregroundStyle(Color.theme.secondaryText)
                                }
                                .padding(.top, 2)
                            }
                        }
                    }

                    Section("Direct Sign-In") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Username / College Email")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            TextField("Username or Email (e.g. student@kiet.edu)", text: $username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .keyboardType(.emailAddress)
                                .textContentType(.username)
                                .submitLabel(.next)
                                .focused($focusedField, equals: .username)
                                .onSubmit {
                                    focusedField = .password
                                }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Password")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            SecureField("Password", text: $password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .textContentType(.password)
                                .submitLabel(.go)
                                .focused($focusedField, equals: .password)
                                .onSubmit {
                                    if !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty && !isAuthenticating {
                                        focusedField = nil
                                        authenticateAndConnect()
                                    }
                                }
                        }

                        Text("Your credentials are submitted directly to the Moodle server to generate an authorized access token. Passwords are never stored on this device.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Button {
                            focusedField = nil
                            authenticateAndConnect()
                        } label: {
                            HStack {
                                Spacer()
                                if isAuthenticating {
                                    ProgressView()
                                        .padding(.trailing, 8)
                                }
                                Text("Authenticate & Connect")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .disabled(username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty || isAuthenticating)
                    }

                    // Manual Token Option
                    Section {
                        DisclosureGroup("Alternative: Connect with Existing Token", isExpanded: $isShowingManualToken) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("If your college administrator generated a personal web-service token, paste it below:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                SecureField("Paste 32-character token", text: $token)
                                    .textFieldStyle(.roundedBorder)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .keyboardType(.asciiCapable)
                                    .submitLabel(.done)
                                    .focused($focusedField, equals: .token)
                                    .onSubmit {
                                        if !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isAuthenticating {
                                            focusedField = nil
                                            connectWithManualToken()
                                        }
                                    }

                                Button("Connect with Token") {
                                    focusedField = nil
                                    connectWithManualToken()
                                }
                                .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAuthenticating)
                                .buttonStyle(.borderedProminent)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                // MARK: - Document Scanning Fallback
                Section("Document Extraction Fallback") {
                    Button {
                        isShowingScannerSheet = true
                    } label: {
                        Label("Scan Notice or Datesheet", systemImage: "doc.text.viewfinder")
                    }
                }
            }
            .navigationTitle("Connect Moodle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isShowingReviewSheet) {
                MoodleImportReviewView(drafts: $fetchedDrafts) {
                    lastSyncDate = Date()
                    UserDefaults.standard.set(lastSyncDate, forKey: "moodle_last_sync")
                    statusMessage = "Successfully imported selected assignments!"
                }
            }
            .sheet(isPresented: $isShowingScannerSheet) {
                NoticeScannerView()
            }
        }
    }

    // MARK: - Operations

    private func authenticateAndConnect() {
        isAuthenticating = true
        errorMessage = nil
        statusMessage = nil

        let targetUrl = siteUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let enteredUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let enteredPassword = password

        Task {
            do {
                // 1. Direct authentication with Moodle mobile token endpoint
                let receivedToken = try await MoodleService.shared.login(
                    siteUrl: targetUrl,
                    username: enteredUsername,
                    password: enteredPassword
                )

                // 2. Immediately erase plaintext password from memory
                await MainActor.run {
                    password = ""
                    token = receivedToken
                }

                // 3. Verify token and retrieve site and student profile info
                let info = try await MoodleService.shared.testConnection(
                    siteUrl: targetUrl,
                    token: receivedToken
                )

                await MainActor.run {
                    isAuthenticating = false
                    connectedUser = info.displayName
                    connectedSite = info.sitename ?? "Moodle Portal"

                    // Persist connection state
                    UserDefaults.standard.set(targetUrl, forKey: "moodle_site_url")
                    UserDefaults.standard.set(connectedUser, forKey: "moodle_connected_user")
                    UserDefaults.standard.set(connectedSite, forKey: "moodle_connected_site")

                    statusMessage = "Connected successfully as \(info.displayName)!"
                }
            } catch {
                await MainActor.run {
                    isAuthenticating = false
                    errorMessage = studentFriendlyErrorMessage(from: error)
                }
            }
        }
    }

    private func connectWithManualToken() {
        isAuthenticating = true
        errorMessage = nil
        statusMessage = nil

        let targetUrl = siteUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                let info = try await MoodleService.shared.testConnection(siteUrl: targetUrl, token: trimmedToken)
                await MainActor.run {
                    isAuthenticating = false
                    connectedUser = info.displayName
                    connectedSite = info.sitename ?? "Moodle Portal"

                    UserDefaults.standard.set(targetUrl, forKey: "moodle_site_url")
                    UserDefaults.standard.set(connectedUser, forKey: "moodle_connected_user")
                    UserDefaults.standard.set(connectedSite, forKey: "moodle_connected_site")
                    MoodleKeychainHelper.saveToken(trimmedToken)

                    statusMessage = "Connected successfully as \(info.displayName)!"
                }
            } catch {
                await MainActor.run {
                    isAuthenticating = false
                    errorMessage = studentFriendlyErrorMessage(from: error)
                }
            }
        }
    }

    private func syncAssignments() {
        isSyncing = true
        errorMessage = nil
        statusMessage = nil

        let targetUrl = siteUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentToken = token

        // Query existing SwiftData assignments for deduplication
        let descriptor = FetchDescriptor<Assignment>()
        let existing = (try? modelContext.fetch(descriptor)) ?? []

        Task {
            do {
                let drafts = try await MoodleService.shared.fetchAssignments(
                    siteUrl: targetUrl,
                    token: currentToken,
                    existingAssignments: existing
                )
                await MainActor.run {
                    isSyncing = false
                    if drafts.isEmpty {
                        statusMessage = "No upcoming assignments or deadlines found on Moodle."
                    } else {
                        fetchedDrafts = drafts
                        isShowingReviewSheet = true
                    }
                }
            } catch {
                await MainActor.run {
                    isSyncing = false
                    errorMessage = studentFriendlyErrorMessage(from: error)
                }
            }
        }
    }

    private func disconnect() {
        SessionManager.shared.logOut(modelContext: modelContext)
        siteUrl = "http://lms.kiet.edu/moodle"
        token = ""
        username = ""
        password = ""
        connectedUser = nil
        connectedSite = nil
        lastSyncDate = nil
        statusMessage = "Moodle logged out and data safely cleared."
        errorMessage = nil
        dismiss()
    }

    // MARK: - Student-Friendly Error Mapping

    private func studentFriendlyErrorMessage(from error: Error) -> String {
        let desc = error.localizedDescription

        // 1. Invalid credentials
        if desc.localizedCaseInsensitiveContains("invalidlogin") ||
           desc.localizedCaseInsensitiveContains("invalid username or password") {
            return "Invalid username or password. Please verify your college login credentials and try again."
        }

        // 2. Expired session
        if desc.localizedCaseInsensitiveContains("invalidtoken") ||
           desc.localizedCaseInsensitiveContains("expired") {
            return "Your Moodle session has expired. Please sign in again to refresh."
        }

        // 3. Permission or web service issue
        if desc.localizedCaseInsensitiveContains("accessexception") ||
           desc.localizedCaseInsensitiveContains("access denied") ||
           desc.localizedCaseInsensitiveContains("web-service") {
            return "Moodle Web Services access is unavailable for this account. Please verify with your college portal."
        }

        // 4. Missing credentials
        if desc.localizedCaseInsensitiveContains("credentials") {
            return "Please enter both your college username and password."
        }

        // 5. Insecure HTTP rejected (for untrusted domains)
        if desc.localizedCaseInsensitiveContains("unencrypted and blocked") ||
           desc.localizedCaseInsensitiveContains("plain http") {
            return "Insecure connection blocked. Only secure HTTPS or approved college portals are supported."
        }

        // 6. Network connectivity / ATS / timeout errors
        if desc.localizedCaseInsensitiveContains("app transport security") ||
           desc.localizedCaseInsensitiveContains("network connection failed") ||
           desc.localizedCaseInsensitiveContains("timed out") ||
           desc.localizedCaseInsensitiveContains("offline") ||
           desc.localizedCaseInsensitiveContains("could not connect") {
            return "Couldn't connect to Moodle. Check your connection and try again."
        }

        // 7. General fallback
        return "Couldn't connect to Moodle. Check your connection and try again."
    }
}

#Preview {
    MoodleConnectView()
        .modelContainer(for: Assignment.self, inMemory: true)
}
