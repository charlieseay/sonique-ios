import SwiftUI
import AVFoundation

struct OnboardingView: View {
    @State private var currentStep = 0
    @State private var micPermissionGranted = false
    @State private var isCheckingPermission = false
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var bonjourDiscovery: BonjourDiscovery

    var body: some View {
        TabView(selection: $currentStep) {
            // Step 1: Welcome
            VStack(spacing: 30) {
                Spacer()

                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 100))
                    .foregroundColor(.blue)

                Text("Meet Quinn")
                    .font(.largeTitle)
                    .bold()

                Text("Your voice assistant\nPowered by your Mac")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()

                Button(action: {
                    withAnimation {
                        currentStep = 1
                    }
                }) {
                    Text("Get Started")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
            .tag(0)

            // Step 2: Microphone Permission
            VStack(spacing: 30) {
                Spacer()

                Image(systemName: "mic.fill")
                    .font(.system(size: 70))
                    .foregroundColor(.blue)

                Text("Microphone Access")
                    .font(.title)
                    .bold()

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Why:")
                            .font(.headline)
                            .foregroundColor(.blue)

                        Text("Quinn listens for your voice commands and questions")
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Without it:")
                            .font(.headline)
                            .foregroundColor(.orange)

                        Text("Quinn won't be able to hear you")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: 600)
                .padding(.horizontal, 50)

                Spacer()

                VStack(spacing: 12) {
                    if micPermissionGranted {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Permission granted!")
                                .foregroundColor(.green)
                        }
                        .padding()

                        Button("Continue") {
                            withAnimation {
                                currentStep = 2
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else {
                        Button(action: requestMicPermission) {
                            Text("Grant Microphone Access")
                                .font(.headline)
                                .frame(maxWidth: 300)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isCheckingPermission)
                    }
                }
                .padding(.bottom, 40)
            }
            .tag(1)
            .onAppear {
                checkMicPermission()
            }

            // Step 3: Connect to SoniqueBar
            VStack(spacing: 30) {
                Spacer()

                if bonjourDiscovery.discoveredURL == nil {
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding()

                    Text("Looking for SoniqueBar...")
                        .font(.headline)

                    Text("Make sure SoniqueBar is running on your Mac")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)

                    Text("Connected!")
                        .font(.title)
                        .bold()

                    Text("Found SoniqueBar on your Mac")
                        .font(.body)
                        .foregroundColor(.secondary)

                    Button("Get Started") {
                        // Mark onboarding complete
                        UserDefaults.standard.set(true, forKey: "onboarding_complete")
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                Spacer()
            }
            .tag(2)
            .onAppear {
                // Start Bonjour discovery when this step appears
                bonjourDiscovery.start()
            }
        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }

    private func checkMicPermission() {
        micPermissionGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    private func requestMicPermission() {
        isCheckingPermission = true

        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                micPermissionGranted = granted
                isCheckingPermission = false
                if granted {
                    // Auto-advance after brief delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation {
                            currentStep = 2
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(BonjourDiscovery())
}
