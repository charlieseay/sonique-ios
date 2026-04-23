import SwiftUI
import AppIntents
import PhotosUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SoniqueSettings
    @EnvironmentObject private var session: SessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var serverURLDraft = ""
    @State private var externalURLDraft = ""
    @State private var apiKeyDraft = ""
    @State private var isTesting = false
    @State private var testResult: TestResult?
    @State private var showQRScanner = false
    @State private var nameDraft = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isSavingProfile = false

    enum TestResult { case success, failure(String) }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.soniqueBackground.ignoresSafeArea()
                List {
                    if showQRScanner {
                        qrScannerSection
                    } else {
                        profileSection
                        serverSection
                        sessionSection
                        siriSection
                        aboutSection
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { saveAndDismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.soniqueAccent2)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            serverURLDraft = settings.serverURL
            externalURLDraft = settings.externalURL
            apiKeyDraft = settings.apiKey
            nameDraft = session.profile?.name ?? ""
        }
    }

    // MARK: - QR Scanner section

    private var qrScannerSection: some View {
        Section {
            VStack(spacing: 12) {
                Text("Scan the QR code from your base station's settings page to auto-configure.")
                    .font(.subheadline)
                    .foregroundStyle(Color.soniqueSubtext)
                    .multilineTextAlignment(.center)

                QRScannerView { value in
                    handleScannedQR(value)
                }
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Button("Cancel") { showQRScanner = false }
                    .foregroundStyle(Color.soniqueOffline)
            }
            .padding(.vertical, 8)
        } header: {
            Text("Scan QR Code").foregroundStyle(Color.soniqueSubtext)
        }
        .listRowBackground(Color.soniqueSurface)
    }

    // MARK: - Profile section

    private var profileSection: some View {
        Section {
            HStack(spacing: 14) {
                // Avatar picker
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Group {
                        if let data = session.avatarData, let img = UIImage(data: data) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(LinearGradient(colors: [.soniqueAccent, .soniqueAccent2],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 56, height: 56)
                                .overlay(Image(systemName: "waveform").foregroundStyle(.white))
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill(Color.soniqueSurface)
                            .frame(width: 20, height: 20)
                            .overlay(Image(systemName: "camera.fill").font(.system(size: 10)).foregroundStyle(Color.soniqueSubtext))
                    }
                }
                .onChange(of: selectedPhoto) { _, item in
                    Task { await uploadSelectedPhoto(item) }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Label("Name", systemImage: "person.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.soniqueSubtext)
                    TextField("Sonique", text: $nameDraft)
                        .foregroundStyle(Color.soniqueText)
                        .onSubmit { Task { await saveName() } }
                }
            }
            .padding(.vertical, 4)

            if isSavingProfile {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        } header: {
            Text("Assistant").foregroundStyle(Color.soniqueSubtext)
        } footer: {
            Text("Name and photo appear in the iOS app and macOS menu bar.")
                .foregroundStyle(Color.soniqueSubtext)
        }
        .listRowBackground(Color.soniqueSurface)
    }

    // MARK: - Server section

    private var serverSection: some View {
        Section {
            settingsField(
                label: "Local URL",
                icon: "server.rack",
                hint: "http://192.168.0.x:3000"
            ) {
                TextField("http://192.168.0.x:3000", text: $serverURLDraft)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .foregroundStyle(Color.soniqueText)
            }

            settingsField(
                label: "Remote URL",
                icon: "network",
                hint: "Optional — Tailscale, tunnel, etc."
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("http://100.x.x.x:3000", text: $externalURLDraft)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .foregroundStyle(Color.soniqueText)
                    Text("Used when your iPhone isn't on the local network.")
                        .font(.caption)
                        .foregroundStyle(Color.soniqueSubtext)
                }
            }

            settingsField(
                label: "API Key",
                icon: "key.horizontal.fill",
                hint: "Optional"
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    SecureField("Optional — leave empty for local network", text: $apiKeyDraft)
                        .foregroundStyle(Color.soniqueText)
                    Text("Set CAAL_API_KEY on the server to require authentication.")
                        .font(.caption)
                        .foregroundStyle(Color.soniqueSubtext)
                }
            }

            // QR onboarding shortcut
            Button {
                showQRScanner = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "qrcode.viewfinder").foregroundStyle(Color.soniqueAccent2)
                    Text("Scan QR Code to Configure").foregroundStyle(Color.soniqueText)
                }
            }

            // Test connection button
            Button {
                Task { await testConnection() }
            } label: {
                HStack(spacing: 10) {
                    if isTesting {
                        ProgressView().progressViewStyle(.circular).tint(.soniqueAccent2).scaleEffect(0.8)
                    } else {
                        Image(systemName: testResultIcon).foregroundStyle(testResultColor)
                    }
                    Text(isTesting ? "Testing…" : "Test Connection")
                        .foregroundStyle(Color.soniqueText)
                    Spacer()
                    if case .failure(let msg) = testResult {
                        Text(msg).font(.caption).foregroundStyle(Color.soniqueOffline).lineLimit(1)
                    }
                    if case .success = testResult {
                        Text("Reachable").font(.caption).foregroundStyle(Color.soniqueOnline)
                    }
                }
            }
            .disabled(serverURLDraft.trimmingCharacters(in: .whitespaces).isEmpty || isTesting)
        } header: {
            Text("Base Station").foregroundStyle(Color.soniqueSubtext)
        }
        .listRowBackground(Color.soniqueSurface)
    }

    // MARK: - Session section

    private var sessionSection: some View {
        Section {
            Toggle(isOn: $settings.extendedSession) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Extended Session").foregroundStyle(Color.soniqueText)
                    Text("4-hour token TTL — keeps Siri-triggered sessions alive longer")
                        .font(.caption).foregroundStyle(Color.soniqueSubtext)
                }
            }
            .tint(Color.soniqueAccent2)
        } header: {
            Text("Session").foregroundStyle(Color.soniqueSubtext)
        }
        .listRowBackground(Color.soniqueSurface)
    }

    // MARK: - Siri section

    private var siriSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                // Default phrases info
                VStack(alignment: .leading, spacing: 6) {
                    Label("Default phrases (ready now)", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.soniqueOnline)
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(["\"Hey Siri, Ask Sonique\"",
                                 "\"Hey Siri, Start Sonique\"",
                                 "\"Hey Siri, Open Sonique session\""], id: \.self) { phrase in
                            Text(phrase)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Color.soniqueSubtext)
                        }
                    }
                }

                Divider().background(Color.soniqueBorder)

                // Open Shortcuts for custom phrase
                VStack(alignment: .leading, spacing: 6) {
                    Text("Want a custom phrase?")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.soniqueText)
                    Text("Open Shortcuts to rename or create a custom trigger — tap the Sonique shortcut and set any phrase you want.")
                        .font(.caption)
                        .foregroundStyle(Color.soniqueSubtext)
                        .fixedSize(horizontal: false, vertical: true)

                    if #available(iOS 16, *) {
                        ShortcutsLink()
                            .shortcutsLinkStyle(.darkOutline)
                            .padding(.top, 4)
                    } else {
                        Link("Open Shortcuts", destination: URL(string: "shortcuts://")!)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.soniqueAccent2)
                    }
                }
            }
            .padding(.vertical, 6)
        } header: {
            Label("Siri", systemImage: "waveform").foregroundStyle(Color.soniqueSubtext)
        } footer: {
            Text("Siri shortcuts use the AppIntents framework. No manual setup required — the default phrases work as soon as you install the app.")
                .foregroundStyle(Color.soniqueSubtext)
        }
        .listRowBackground(Color.soniqueSurface)
    }

    // MARK: - About section

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version").foregroundStyle(Color.soniqueText)
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                    .foregroundStyle(Color.soniqueSubtext)
            }
            HStack {
                Text("Engine").foregroundStyle(Color.soniqueText)
                Spacer()
                Text("CAAL / LiveKit").foregroundStyle(Color.soniqueSubtext)
            }
        } header: {
            Text("About").foregroundStyle(Color.soniqueSubtext)
        }
        .listRowBackground(Color.soniqueSurface)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func settingsField<F: View>(label: String, icon: String, hint: String, @ViewBuilder field: () -> F) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.soniqueSubtext)
            field()
        }
        .padding(.vertical, 4)
    }

    private var testResultIcon: String {
        switch testResult {
        case .success:  return "checkmark.circle.fill"
        case .failure:  return "xmark.circle.fill"
        case nil:       return "network"
        }
    }

    private var testResultColor: Color {
        switch testResult {
        case .success:  return .soniqueOnline
        case .failure:  return .soniqueOffline
        case nil:       return .soniqueSubtext
        }
    }

    private func testConnection() async {
        isTesting = true
        testResult = nil
        let base = serverURLDraft.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/api/settings") else {
            testResult = .failure("Bad URL"); isTesting = false; return
        }
        var request = URLRequest(url: url, timeoutInterval: 5)
        if !apiKeyDraft.isEmpty { request.setValue(apiKeyDraft, forHTTPHeaderField: "x-api-key") }
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            testResult = (code == 200 || code == 401) ? .success : .failure("HTTP \(code)")
        } catch {
            testResult = .failure("Unreachable")
        }
        isTesting = false
    }

    private func saveAndDismiss() {
        settings.serverURL = serverURLDraft
        settings.externalURL = externalURLDraft
        settings.apiKey = apiKeyDraft
        settings.hasCompletedSetup = !serverURLDraft.trimmingCharacters(in: .whitespaces).isEmpty
        session.startHealthChecks(settings: settings)
        dismiss()
    }

    private func handleScannedQR(_ value: String) {
        guard let url = URL(string: value),
              url.scheme == "sonique",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let params = components.queryItems ?? []
        // New format: local= / external= / key=
        // Legacy format: url= / key= (backwards compatible)
        if let u = params.first(where: { $0.name == "local" })?.value { serverURLDraft = u }
        else if let u = params.first(where: { $0.name == "url" })?.value { serverURLDraft = u }
        if let e = params.first(where: { $0.name == "external" })?.value { externalURLDraft = e }
        if let k = params.first(where: { $0.name == "key" })?.value { apiKeyDraft = k }
        showQRScanner = false
        saveAndDismiss()
    }

    private func saveName() async {
        guard !nameDraft.isEmpty else { return }
        isSavingProfile = true
        try? await session.updateProfile(settings: settings, name: nameDraft)
        isSavingProfile = false
    }

    private func uploadSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isSavingProfile = true
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                try await session.updateProfile(settings: settings, imageData: data, imageExt: "jpg")
            }
        } catch {}
        isSavingProfile = false
    }
}


#Preview {
    SettingsView()
        .environmentObject(SoniqueSettings())
        .environmentObject(SessionManager())
}
