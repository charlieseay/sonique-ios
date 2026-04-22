import Foundation

enum SessionState: Equatable {
    case idle
    case connecting
    case active
    case disconnecting
    case error(String)

    var isActive: Bool {
        if case .active = self { return true }
        return false
    }

    var isConnecting: Bool {
        if case .connecting = self { return true }
        return false
    }
}

enum AgentState {
    case idle
    case listening
    case thinking
    case speaking

    var label: String {
        switch self {
        case .idle:      return "Ready"
        case .listening: return "Listening"
        case .thinking:  return "Thinking"
        case .speaking:  return "Speaking"
        }
    }
}
