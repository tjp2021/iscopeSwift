import Foundation

struct Video: Identifiable, Codable, Equatable {
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
    var transcriptionStatus: String?  // "pending", "completed", "failed"
    var transcriptionText: String?    // The actual transcription when completed
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case videoUrl
        case creatorId
        case createdAt
        case likeCount
        case commentCount
        case viewCount
        case transcriptionStatus
        case transcriptionText
        // isLiked is intentionally omitted as it's computed from the likes collection
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        videoUrl = try container.decode(String.self, forKey: .videoUrl)
        creatorId = try container.decode(String.self, forKey: .creatorId)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        likeCount = try container.decode(Int.self, forKey: .likeCount)
        commentCount = try container.decode(Int.self, forKey: .commentCount)
        viewCount = try container.decode(Int.self, forKey: .viewCount)
        transcriptionStatus = try container.decodeIfPresent(String.self, forKey: .transcriptionStatus)
        transcriptionText = try container.decodeIfPresent(String.self, forKey: .transcriptionText)
        isLiked = false // Default value, will be set after fetching like status
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
         viewCount: Int = 0,
         transcriptionStatus: String? = nil,
         transcriptionText: String? = nil) {
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
        self.transcriptionStatus = transcriptionStatus
        self.transcriptionText = transcriptionText
    }
    
    static func == (lhs: Video, rhs: Video) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.description == rhs.description &&
        lhs.videoUrl == rhs.videoUrl &&
        lhs.creatorId == rhs.creatorId &&
        lhs.createdAt == rhs.createdAt &&
        lhs.likeCount == rhs.likeCount &&
        lhs.commentCount == rhs.commentCount &&
        lhs.isLiked == rhs.isLiked &&
        lhs.viewCount == rhs.viewCount &&
        lhs.transcriptionStatus == rhs.transcriptionStatus &&
        lhs.transcriptionText == rhs.transcriptionText
    }
} 