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
        
        // Handle createdAt as milliseconds since 1970
        if let timestamp = try container.decodeIfPresent(Double.self, forKey: .createdAt) {
            createdAt = Date(timeIntervalSince1970: timestamp / 1000.0)
        } else {
            createdAt = Date()
        }
        
        viewCount = try container.decodeIfPresent(Int.self, forKey: .viewCount) ?? 0
        transcriptionStatus = try container.decodeIfPresent(String.self, forKey: .transcriptionStatus)
        transcriptionText = try container.decodeIfPresent(String.self, forKey: .transcriptionText)
        transcriptionSegments = try container.decodeIfPresent([TranscriptionSegment].self, forKey: .transcriptionSegments)
        translations = try container.decodeIfPresent([String: TranslationData].self, forKey: .translations)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(url, forKey: .url)
        try container.encodeIfPresent(thumbnailUrl, forKey: .thumbnailUrl)
        try container.encode(createdAt.timeIntervalSince1970 * 1000, forKey: .createdAt)
        try container.encode(viewCount, forKey: .viewCount)
        try container.encodeIfPresent(transcriptionStatus, forKey: .transcriptionStatus)
        try container.encodeIfPresent(transcriptionText, forKey: .transcriptionText)
        try container.encodeIfPresent(transcriptionSegments, forKey: .transcriptionSegments)
        try container.encodeIfPresent(translations, forKey: .translations)
    }
    
    init(id: String,
         userId: String,
         title: String,
         description: String? = nil,
         url: String,
         thumbnailUrl: String? = nil,
         createdAt: Date = Date(),
         viewCount: Int = 0,
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
    
    enum CodingKeys: String, CodingKey {
        case text
        case segments
        case status
        case lastUpdated
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        segments = try container.decodeIfPresent([TranscriptionSegment].self, forKey: .segments)
        status = try container.decode(TranslationStatus.self, forKey: .status)
        
        // Handle lastUpdated as milliseconds since 1970
        if let timestamp = try container.decodeIfPresent(Double.self, forKey: .lastUpdated) {
            lastUpdated = Date(timeIntervalSince1970: timestamp / 1000.0)
        } else {
            lastUpdated = Date()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(segments, forKey: .segments)
        try container.encode(status, forKey: .status)
        
        // Encode lastUpdated as milliseconds since 1970
        try container.encode(lastUpdated.timeIntervalSince1970 * 1000, forKey: .lastUpdated)
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