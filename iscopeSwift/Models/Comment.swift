import Foundation

struct Comment: Identifiable, Codable {
    var id: String?
    let videoId: String?
    let userId: String
    let userDisplayName: String
    let text: String
    let createdAt: Date
    var likeCount: Int
    var isLiked: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case videoId
        case userId
        case userDisplayName
        case text
        case createdAt
        case likeCount
        case isLiked
    }
    
    init(id: String? = nil,
         videoId: String?,
         userId: String,
         userDisplayName: String,
         text: String,
         createdAt: Date = Date(),
         likeCount: Int = 0,
         isLiked: Bool = false) {
        self.id = id
        self.videoId = videoId
        self.userId = userId
        self.userDisplayName = userDisplayName
        self.text = text
        self.createdAt = createdAt
        self.likeCount = likeCount
        self.isLiked = isLiked
    }
} 