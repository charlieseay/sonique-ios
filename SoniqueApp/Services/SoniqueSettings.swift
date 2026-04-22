import SwiftUI
import Combine

class SoniqueSettings: ObservableObject {
    @AppStorage("serverURL") var serverURL: String = "" {
        didSet { objectWillChange.send() }
    }
    @AppStorage("apiKey") var apiKey: String = "" {
        didSet { objectWillChange.send() }
    }
    @AppStorage("extendedSession") var extendedSession: Bool = false {
        didSet { objectWillChange.send() }
    }
    @AppStorage("hasCompletedSetup") var hasCompletedSetup: Bool = false

    var isConfigured: Bool {
        !serverURL.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var normalizedServerURL: String {
        var url = serverURL.trimmingCharacters(in: .whitespaces)
        if url.hasSuffix("/") { url = String(url.dropLast()) }
        return url
    }
}
