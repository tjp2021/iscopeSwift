import Foundation

@MainActor
class TranscriptionViewModel: ObservableObject {
    @Published var isTranscribing = false
    @Published var transcriptionStatus: String?
    @Published var transcriptionText: String?
    @Published var error: Error?
    
    private let serverUrl = "http://localhost:3000"
    
    // Test function to try transcription
    func testTranscription() async throws {
        isTranscribing = true
        transcriptionStatus = "Starting test transcription..."
        
        // Use defer to ensure isTranscribing is set to false when function exits
        defer { isTranscribing = false }
        
        do {
            let url = URL(string: "\(serverUrl)/test-transcription")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }
            
            let result = try JSONDecoder().decode(WhisperResponse.self, from: data)
            transcriptionStatus = "Transcription completed!"
            transcriptionText = result.text
            
        } catch {
            self.error = error
            transcriptionStatus = "Test transcription failed"
            throw error
        }
    }
    
    // Start transcription for a video
    func startTranscription(videoUrl: String, languageCode: String = "en") async throws {
        isTranscribing = true
        transcriptionStatus = "Starting transcription..."
        
        // Use defer to ensure isTranscribing is set to false when function exits
        defer { isTranscribing = false }
        
        do {
            let url = URL(string: "\(serverUrl)/start-transcription")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body = ["videoUrl": videoUrl, "languageCode": languageCode]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }
            
            let result = try JSONDecoder().decode(WhisperResponse.self, from: data)
            transcriptionStatus = "Transcription completed!"
            transcriptionText = result.text
            
        } catch {
            self.error = error
            transcriptionStatus = "Transcription failed"
            throw error
        }
    }
}

// Response models
struct WhisperResponse: Codable {
    let jobId: String
    let status: String
    let transcriptUrl: String
    let text: String
} 