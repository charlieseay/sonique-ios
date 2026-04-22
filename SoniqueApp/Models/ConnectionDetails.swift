import Foundation

struct ConnectionDetails: Decodable {
    let serverUrl: String
    let roomName: String
    let participantName: String
    let participantToken: String
}

struct ServerHealth {
    enum Status {
        case online, offline, checking
    }
    var status: Status = .checking
    var version: String?
}
