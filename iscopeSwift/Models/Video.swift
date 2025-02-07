import Foundation

struct Video: Identifiable, Codable {
    var id: String?
    let title: String
    let description: String
    let videoUrl: String
    let creatorId: String
    let createdAt: Date
    var likeCount: Int
    var commentCount: Int
    var isLiked: Bool
    var viewCount: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case videoUrl
        case creatorId
        case createdAt
        case likeCount
        case commentCount
        case isLiked
        case viewCount
    }
    
    init(id: String? = nil,
         title: String,
         description: String,
         videoUrl: String,
         creatorId: String,
         createdAt: Date,
         likeCount: Int = 0,
         commentCount: Int = 0,
         isLiked: Bool = false,
         viewCount: Int = 0) {
        self.id = id
        self.title = title
        self.description = description
        self.videoUrl = videoUrl
        self.creatorId = creatorId
        self.createdAt = createdAt
        self.likeCount = likeCount
        self.commentCount = commentCount
        self.isLiked = isLiked
        self.viewCount = viewCount
    }
} 