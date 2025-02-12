import Foundation

struct Video: Identifiable, Codable, Equatable {
    var id: String
    var userId: String
    var title: String
    var description: String?
    var url: String
    var thumbnailUrl: String?
    var createdAt: Date
    var viewCount: Int
    var likeCount: Int
    var commentCount: Int
    var transcriptionStatus: String?  // "pending", "completed", "failed"
    var transcriptionText: String?    // The actual transcription when completed
    var transcriptionSegments: [TranscriptionSegment]? // Array of timed segments
    var translations: [String: TranslationData]? // Language code -> Translation data
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case title
        case description
        case url
        case thumbnailUrl
        case createdAt
        case viewCount
        case likeCount
        case commentCount
        case transcriptionStatus
        case transcriptionText
        case transcriptionSegments
        case translations
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        url = try container.decode(String.self, forKey: .url)
        thumbnailUrl = try container.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        viewCount = try container.decodeIfPresent(Int.self, forKey: .viewCount) ?? 0
        likeCount = try container.decodeIfPresent(Int.self, forKey: .likeCount) ?? 0
        commentCount = try container.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0
        transcriptionStatus = try container.decodeIfPresent(String.self, forKey: .transcriptionStatus)
        transcriptionText = try container.decodeIfPresent(String.self, forKey: .transcriptionText)
        transcriptionSegments = try container.decodeIfPresent([TranscriptionSegment].self, forKey: .transcriptionSegments)
        translations = try container.decodeIfPresent([String: TranslationData].self, forKey: .translations)
    }
    
    init(id: String,
         userId: String,
         title: String,
         description: String? = nil,
         url: String,
         thumbnailUrl: String? = nil,
         createdAt: Date = Date(),
         viewCount: Int = 0,
         likeCount: Int = 0,
         commentCount: Int = 0,
         transcriptionStatus: String? = nil,
         transcriptionText: String? = nil,
         transcriptionSegments: [TranscriptionSegment]? = nil,
         translations: [String: TranslationData]? = nil) {
        self.id = id
        self.userId = userId
        self.title = title
        self.description = description
        self.url = url
        self.thumbnailUrl = thumbnailUrl
        self.createdAt = createdAt
        self.viewCount = viewCount
        self.likeCount = likeCount
        self.commentCount = commentCount
        self.transcriptionStatus = transcriptionStatus
        self.transcriptionText = transcriptionText
        self.transcriptionSegments = transcriptionSegments
        self.translations = translations
    }
    
    static func == (lhs: Video, rhs: Video) -> Bool {
        return lhs.id == rhs.id &&
        lhs.userId == rhs.userId &&
        lhs.title == rhs.title &&
        lhs.description == rhs.description &&
        lhs.url == rhs.url &&
        lhs.thumbnailUrl == rhs.thumbnailUrl &&
        lhs.createdAt == rhs.createdAt &&
        lhs.viewCount == rhs.viewCount &&
        lhs.likeCount == rhs.likeCount &&
        lhs.commentCount == rhs.commentCount &&
        lhs.transcriptionStatus == rhs.transcriptionStatus &&
        lhs.transcriptionText == rhs.transcriptionText &&
        lhs.transcriptionSegments == rhs.transcriptionSegments &&
        lhs.translations == rhs.translations
    }
}

extension Video {
    static var mock: Video {
        Video(
            id: "mockId",
            userId: "mockUserId",
            title: "Mock Video",
            description: "A mock video for testing",
            url: "https://example.com/video.mp4",
            thumbnailUrl: nil,
            createdAt: Date(),
            viewCount: 100,
            likeCount: 50,
            commentCount: 10,
            transcriptionStatus: "completed",
            transcriptionText: "This is a mock transcription text for testing purposes.",
            transcriptionSegments: nil,
            translations: nil
        )
    }
}

// Translation data structure
struct TranslationData: Codable, Equatable {
    var text: String
    var segments: [TranscriptionSegment]?
    var status: TranslationStatus
    var lastUpdated: Date
    
    enum TranslationStatus: String, Codable {
        case pending
        case completed
        case failed
    }
}

// Transcription segment structure
struct TranscriptionSegment: Codable, Equatable {
    var text: String
    var startTime: Double  // Start time in seconds
    var endTime: Double    // End time in seconds
    var words: [Word]?     // Optional word-level timing data
    
    struct Word: Codable, Equatable {
        var text: String
        var startTime: Double
        var endTime: Double
    }
} 