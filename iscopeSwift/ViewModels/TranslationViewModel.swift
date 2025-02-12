import Foundation
import FirebaseFirestore

@MainActor
class TranslationViewModel: ObservableObject {
    @Published var isTranslating = false
    @Published var currentLanguage: String = "en"
    @Published var availableLanguages: [String] = ["en", "es", "fr", "de", "it", "pt", "ru", "ja", "ko", "zh"]
    @Published var error: Error?
    
    private let db = Firestore.firestore()
    
    #if targetEnvironment(simulator)
    private let serverUrl = "http://127.0.0.1:3001"
    #else
    private let serverUrl = "http://localhost:3001"
    #endif
    
    private struct TranslationResponse: Codable {
        let translation: String
        let status: String
        let timestamp: TimeInterval
    }
    
    func translate(video: Video, to targetLanguage: String) async throws {
        guard let segments = video.transcriptionSegments else {
            throw NSError(domain: "Translation", code: -1, userInfo: [NSLocalizedDescriptionKey: "No transcription segments available"])
        }
        
        isTranslating = true
        defer { isTranslating = false }
        
        // Check if translation already exists and is completed
        if let existingTranslation = video.translations?[targetLanguage],
           existingTranslation.status == TranslationData.TranslationStatus.completed {
            currentLanguage = targetLanguage
            return
        }
        
        // Update status to pending
        try await updateTranslationStatus(for: video.id, language: targetLanguage, status: TranslationData.TranslationStatus.pending)
        
        // Translate each segment
        var translatedSegments: [[String: Any]] = []
        
        for segment in segments {
            let translatedText = try await translateText(segment.text, to: targetLanguage)
            let translatedSegment: [String: Any] = [
                "text": translatedText,
                "startTime": segment.startTime,
                "endTime": segment.endTime
            ]
            translatedSegments.append(translatedSegment)
        }
        
        // Create translation data
        let translationDict: [String: Any] = [
            "text": translatedSegments.map { $0["text"] as? String ?? "" }.joined(separator: " "),
            "segments": translatedSegments,
            "status": TranslationData.TranslationStatus.completed.rawValue,
            "lastUpdated": Date().timeIntervalSince1970 * 1000 // Convert to milliseconds since 1970
        ]
        
        // Update Firestore
        try await db.collection("videos").document(video.id).updateData([
            "translations.\(targetLanguage)": translationDict
        ])
        
        currentLanguage = targetLanguage
    }
    
    private func translateText(_ text: String, to targetLanguage: String) async throws -> String {
        guard let url = URL(string: "\(serverUrl)/translate") else {
            throw NSError(domain: "Translation", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["text": text, "targetLanguage": targetLanguage]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "Translation", code: -1, userInfo: [NSLocalizedDescriptionKey: "Server error"])
        }
        
        let result = try JSONDecoder().decode(TranslationResponse.self, from: data)
        return result.translation
    }
    
    private func updateTranslationStatus(
        for videoId: String,
        language: String,
        status: TranslationData.TranslationStatus
    ) async throws {
        let ref = db.collection("videos").document(videoId)
        try await ref.updateData([
            "translations.\(language).status": status.rawValue,
            "translations.\(language).lastUpdated": Date().timeIntervalSince1970 * 1000 // Convert to milliseconds since 1970
        ])
    }
    
    private func updateTranslation(
        for videoId: String,
        language: String,
        data: TranslationData
    ) async throws {
        let ref = db.collection("videos").document(videoId)
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(data)
        let decoded = try JSONSerialization.jsonObject(with: encoded)
        try await ref.updateData(["translations.\(language)": decoded])
    }
} 