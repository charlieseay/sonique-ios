import SwiftUI

/// Voice selection UI matching Claude iOS style
struct VoiceSelector: View {
    @Binding var selectedVoice: ElevenLabsVoice
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List(ElevenLabsVoice.allCases) { voice in
                Button(action: {
                    selectedVoice = voice
                    dismiss()
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(voice.displayName)
                                .font(.headline)
                            Text(voice.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if selectedVoice == voice {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Top 5 ElevenLabs voices - natural conversational English
enum ElevenLabsVoice: String, CaseIterable, Identifiable {
    case josh = "TxGEqnHWrfWFTfGW9XjX"        // Deep, clear American male
    case rachel = "21m00Tcm4TlvDq8ikWAM"     // Calm, warm American female
    case antoni = "ErXwobaYiN019PkySvjV"     // Natural, friendly American male
    case bella = "EXAVITQu4vr4xnSDxMaL"      // Soft, clear American female
    case adam = "pNInz6obpgDQGcFmaJgB"       // Confident, authoritative American male

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

    var description: String {
        switch self {
        case .josh: return "Deep, clear voice"
        case .rachel: return "Calm, warm voice"
        case .antoni: return "Natural, friendly voice"
        case .bella: return "Soft, clear voice"
        case .adam: return "Confident, authoritative voice"
        }
    }
}
