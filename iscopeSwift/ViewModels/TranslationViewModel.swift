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
    
    func translate(video: Video, to targetLanguage: String) async throws {
        guard let segments = video.transcriptionSegments else {
            print("[DEBUG] Translation failed: No transcription segments available")
            throw NSError(domain: "Translation", code: -1, userInfo: [NSLocalizedDescriptionKey: "No transcription segments available"])
        }
        
        print("[DEBUG] Starting translation to \(targetLanguage)")
        print("[DEBUG] Number of segments to translate: \(segments.count)")
        
        isTranslating = true
        defer { isTranslating = false }
        
        // Check if translation already exists and is completed
        if let existingTranslation = video.translations?[targetLanguage],
           existingTranslation.status == .completed {
            print("[DEBUG] Found existing completed translation for \(targetLanguage)")
            currentLanguage = targetLanguage
            return
        }
        
        print("[DEBUG] No existing translation found, starting new translation")
        
        // Update status to pending
        try await updateTranslationStatus(for: video.id, language: targetLanguage, status: .pending)
        
        // Translate each segment
        var translatedSegments: [TranscriptionSegment] = []
        
        for (index, segment) in segments.enumerated() {
            print("[DEBUG] Translating segment \(index + 1)/\(segments.count)")
            let translatedText = try await translateText(segment.text, to: targetLanguage)
            var translatedSegment = segment
            translatedSegment.text = translatedText
            translatedSegments.append(translatedSegment)
        }
        
        print("[DEBUG] All segments translated successfully")
        
        // Create translation data
        let translationData = TranslationData(
            text: translatedSegments.map { $0.text }.joined(separator: " "),
            segments: translatedSegments,
            status: .completed,
            lastUpdated: Date()
        )
        
        print("[DEBUG] Updating Firestore with translated data")
        
        // Update Firestore
        try await updateTranslation(
            for: video.id,
            language: targetLanguage,
            data: translationData
        )
        
        print("[DEBUG] Translation process completed successfully")
        currentLanguage = targetLanguage
    }
    
    private func translateText(_ text: String, to targetLanguage: String) async throws -> String {
        guard let url = URL(string: "\(serverUrl)/translate") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["text": text, "targetLanguage": targetLanguage]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        struct TranslationResponse: Codable {
            let translation: String
            let status: String
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
            "translations.\(language).lastUpdated": Date()
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