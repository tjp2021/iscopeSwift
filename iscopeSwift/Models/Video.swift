import Foundation
import FirebaseFirestore

struct Video: Codable, Identifiable {
    var id: String?
    var title: String
    var description: String
    var videoUrl: String // points to the S3 URL
    var creatorId: String
    var createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case videoUrl = "video_url"
        case creatorId = "creator_id"
        case createdAt = "created_at"
    }
} 