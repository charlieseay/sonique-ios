import SwiftUI

// MARK: - Colors

extension Color {
    static let soniqueBackground  = Color(red: 0.06, green: 0.06, blue: 0.08)
    static let soniqueSurface     = Color(red: 0.11, green: 0.11, blue: 0.14)
    static let soniqueBorder      = Color(white: 1, opacity: 0.08)
    static let soniqueText        = Color(white: 0.95)
    static let soniqueSubtext     = Color(white: 0.55)
    // Accent: indigo-violet gradient
    static let soniqueAccent      = Color(red: 0.45, green: 0.35, blue: 0.95)
    static let soniqueAccent2     = Color(red: 0.65, green: 0.45, blue: 1.0)
    // Status
    static let soniqueOnline  = Color(red: 0.20, green: 0.85, blue: 0.55)
    static let soniqueOffline = Color(red: 0.90, green: 0.35, blue: 0.35)
    static let soniqueWarning = Color(red: 1.0,  green: 0.75, blue: 0.20)
}

// MARK: - Gradient helpers

extension LinearGradient {
    static var soniqueAccent: LinearGradient {
        LinearGradient(
            colors: [.soniqueAccent, .soniqueAccent2],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Status badge

struct StatusBadge: View {
    enum Status {
        case online, offline, checking, active

        var color: Color {
            switch self {
            case .online:   return .soniqueOnline
            case .offline:  return .soniqueOffline
            case .checking: return .soniqueWarning
            case .active:   return .soniqueAccent2
            }
        }

        var label: String {
            switch self {
            case .online:   return "Online"
            case .offline:  return "Offline"
            case .checking: return "Checking"
            case .active:   return "Connected"
            }
        }
    }

    let status: Status

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(status.color)
                .frame(width: 7, height: 7)
                .overlay(
                    Circle()
                        .fill(status.color)
                        .frame(width: 7, height: 7)
                        .opacity(status == .checking || status == .active ? 0.4 : 0)
                        .scaleEffect(status == .checking || status == .active ? 1.8 : 1)
                        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: status == .checking)
                )
            Text(status.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(status.color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(status.color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Card container

struct SoniqueCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .background(Color.soniqueSurface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.soniqueBorder, lineWidth: 1)
            )
    }
}
