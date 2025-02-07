import Foundation

struct Video: Identifiable, Codable {
    var id: String?
    let title: String
    let description: String
    let videoUrl: String
    let creatorId: String
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case videoUrl
        case creatorId
        case createdAt
    }
} 