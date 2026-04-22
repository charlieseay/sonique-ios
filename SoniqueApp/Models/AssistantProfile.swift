import Foundation

struct AssistantProfile: Decodable, Equatable {
    let name: String
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case name
        case avatarUrl = "avatar_url"
    }
}
