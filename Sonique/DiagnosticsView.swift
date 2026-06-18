import SwiftUI

/// User-facing diagnostics report view
struct DiagnosticsView: View {
    let diagnosis: DiagnosticResponse.Diagnosis
    let remediation: DiagnosticResponse.RemediationResult?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Problem Detected", systemImage: "exclamationmark.triangle.fill")
                            .font(.title2)
                            .foregroundColor(.orange)

                        Text(diagnosis.diagnosis)
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)

                    // Root Cause
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Root Cause", systemImage: "magnifyingglass")
                            .font(.headline)

                        Text(diagnosis.rootCause)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)

                    // Evidence
                    if !diagnosis.evidence.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Evidence", systemImage: "doc.text")
                                .font(.headline)

                            ForEach(diagnosis.evidence, id: \.self) { evidence in
                                HStack(alignment: .top) {
                                    Text("•")
                                    Text(evidence)
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                    }

                    // Auto-Remediation Result
                    if let remediation = remediation {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(
                                remediation.success ? "Auto-Fix Applied" : "Auto-Fix Failed",
                                systemImage: remediation.success ? "checkmark.circle.fill" : "xmark.circle.fill"
                            )
                            .font(.headline)
                            .foregroundColor(remediation.success ? .green : .red)

                            Text(remediation.message)
                                .font(.body)
                                .foregroundColor(.secondary)

                            if !remediation.actionsTaken.isEmpty {
                                Text("Actions taken:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                ForEach(remediation.actionsTaken, id: \.self) { action in
                                    HStack(alignment: .top) {
                                        Text("•")
                                        Text(action)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }

                            if let error = remediation.error {
                                Text("Error: \(error)")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                    }

                    // User Action Required
                    if let userAction = diagnosis.remediation.userAction {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("What You Should Do", systemImage: "person.fill.checkmark")
                                .font(.headline)
                                .foregroundColor(.blue)

                            Text(userAction)
                                .font(.body)
                                .foregroundColor(.primary)
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }

                    // Workaround
                    if let workaround = diagnosis.remediation.workaround {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Temporary Workaround", systemImage: "wrench.fill")
                                .font(.headline)

                            Text(workaround)
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                    }

                    // Technical Details (collapsible)
                    if let technicalDetails = diagnosis.technicalDetails {
                        DisclosureGroup("Technical Details") {
                            Text(technicalDetails)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.05))
                        .cornerRadius(12)
                    }

                    // Confidence
                    HStack {
                        Text("Diagnostic Confidence:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ProgressView(value: diagnosis.confidence, total: 1.0)
                            .frame(maxWidth: 100)

                        Text("\(Int(diagnosis.confidence * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
                .padding()
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    DiagnosticsView(
        diagnosis: DiagnosticResponse.Diagnosis(
            diagnosis: "iOS App Transport Security blocking HTTP over cellular",
            confidence: 0.95,
            evidence: [
                "URLError -1001 (timeout) on cellular network",
                "Attempting HTTP connection to Tailscale IP (100.x.x.x)",
                "iOS blocks insecure HTTP by default on cellular (iOS 14+)"
            ],
            rootCause: "Info.plist missing NSAppTransportSecurity exceptions for Tailscale IP",
            remediation: DiagnosticResponse.Remediation(
                autoFixable: false,
                requires: "iOS app rebuild with Info.plist update",
                userAction: "Install latest build from TestFlight with ATS exceptions, or switch to WiFi",
                workaround: "Connect to WiFi network or use VPN with HTTPS proxy",
                autoFixSteps: nil
            ),
            technicalDetails: "Timestamp: 2026-06-18\nError: NSURLErrorDomain\nCode: -1001\nNetwork: cellular"
        ),
        remediation: nil
    )
}
