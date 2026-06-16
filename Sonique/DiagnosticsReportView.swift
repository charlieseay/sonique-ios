import SwiftUI
import UIKit

/// "Report a problem" — bundles the on-device trace log + app/device/connection state
/// into a text file and shares it via the system share sheet. This is the seed of the
/// larger support loop (see "Connection + Diagnostics + Support Loop — Vision"): later
/// this will POST to a collection endpoint that auto-files a bug + drives remediation.
struct DiagnosticsReportView: View {
    let connectionOK: Bool
    let activeEndpoint: String
    @Environment(\.dismiss) private var dismiss
    @State private var shareURL: IdentifiableURL?
    @State private var note: String = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("What happened?"),
                        footer: Text("Optional — a short note helps us reproduce the issue.")) {
                    TextField("e.g. Couldn't connect, no response, etc.", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section(header: Text("Included diagnostics")) {
                    LabeledContent("App version", value: appVersion)
                    LabeledContent("Connection", value: connectionOK ? "Reachable" : "Unreachable")
                    LabeledContent("Endpoint", value: activeEndpoint)
                    Text("A recent activity log is attached to help support diagnose the problem. No personal content beyond your conversation transcripts in the log.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Section {
                    Button {
                        if let url = buildReport() {
                            shareURL = IdentifiableURL(url: url)
                        }
                    } label: {
                        Label("Share with support", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .navigationTitle("Report a Problem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $shareURL) { wrapper in
                ShareSheet(items: [wrapper.url])
            }
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    /// Compose a single shareable diagnostics file: header + trace log.
    private func buildReport() -> URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let trace = (try? String(contentsOf: docs.appendingPathComponent("trace.log"), encoding: .utf8)) ?? "(no trace log)"

        let header = """
        Sonique Diagnostics Report
        ==========================
        App version : \(appVersion)
        Device      : \(UIDevice.current.model) — iOS \(UIDevice.current.systemVersion)
        Assistant   : \(AssistantProfile.shared.name)
        Connection  : \(connectionOK ? "Reachable" : "Unreachable")
        Endpoint    : \(activeEndpoint)
        User note   : \(note.isEmpty ? "(none)" : note)

        --- Activity Log ---
        \(trace)
        """

        let out = FileManager.default.temporaryDirectory.appendingPathComponent("sonique-diagnostics.txt")
        try? header.write(to: out, atomically: true, encoding: .utf8)
        return out
    }
}

/// UIActivityViewController wrapper.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// Wrapper to make URL work with .sheet(item:) without extending Foundation types
struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}
