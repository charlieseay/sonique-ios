import SwiftUI

/// Dynamic voice picker — lists ElevenLabs' studio voices, samples each on tap
/// (sample-before-select, like Claude/Gemini), and sets the active voice.
struct VoiceSelector: View {
    let apiKey: String
    @Binding var selectedVoiceID: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var catalog: VoiceCatalog

    init(apiKey: String, selectedVoiceID: Binding<String>) {
        self.apiKey = apiKey
        self._selectedVoiceID = selectedVoiceID
        self._catalog = StateObject(wrappedValue: VoiceCatalog(apiKey: apiKey))
    }

    var body: some View {
        NavigationView {
            Group {
                if catalog.isLoading {
                    ProgressView("Loading voices…")
                } else if let err = catalog.error {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                        Text(err).font(.caption).foregroundColor(.secondary)
                    }
                } else {
                    List(catalog.voices) { voice in
                        HStack(spacing: 12) {
                            // Sample button
                            Button {
                                if catalog.sampling == voice.id {
                                    catalog.stopSample()
                                } else {
                                    catalog.playSample(voice)
                                }
                            } label: {
                                Image(systemName: catalog.sampling == voice.id ? "stop.circle.fill" : "play.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(catalog.sampling == voice.id ? .red : .accentColor)
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(voice.displayName).font(.headline)
                                if !voice.descriptor.isEmpty {
                                    Text(voice.descriptor)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            if selectedVoiceID == voice.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedVoiceID = voice.id
                            Config.selectedVoiceID = voice.id
                            Config.selectedVoiceName = voice.displayName
                            catalog.stopSample()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Choose a Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { catalog.stopSample(); dismiss() }
                }
            }
            .task { await catalog.load() }
            .onDisappear { catalog.stopSample() }
        }
    }
}

/// Curated fallback voices — used by the playback path when no dynamic ID is set.
enum ElevenLabsVoice: String, CaseIterable, Identifiable {
    case josh = "TxGEqnHWrfWFTfGW9XjX"
    case rachel = "21m00Tcm4TlvDq8ikWAM"
    case antoni = "ErXwobaYiN019PkySvjV"
    case bella = "EXAVITQu4vr4xnSDxMaL"
    case adam = "pNInz6obpgDQGcFmaJgB"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .josh: return "Josh"
        case .rachel: return "Rachel"
        case .antoni: return "Antoni"
        case .bella: return "Bella"
        case .adam: return "Adam"
        }
    }
}
