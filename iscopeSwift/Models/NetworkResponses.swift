import Foundation

struct PresignedUrlResponse: Codable {
    let uploadURL: String
    let key: String
    
    var imageKey: String { key }
    var videoKey: String { key }
} 