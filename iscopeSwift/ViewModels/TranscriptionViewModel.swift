import Foundation

/// ViewModel responsible for handling video transcription functionality
@MainActor
class TranscriptionViewModel: ObservableObject {
    @Published var isTranscribing = false
    @Published var transcriptionStatus: String?
    @Published var transcriptionText: String?
    @Published var error: Error?
    
    private let serverUrl = "http://localhost:3000"
    
    /// Tests the transcription service with a mock request
    /// This function is used to verify the connection and response handling
    func testTranscription() async throws {
        isTranscribing = true
        transcriptionStatus = "Starting test transcription..."
        
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
    
    /// Starts the transcription process for a video
    /// - Parameters:
    ///   - videoUrl: The URL of the video to transcribe
    ///   - languageCode: The language code for transcription (default: "en")
    func startTranscription(videoUrl: String, languageCode: String = "en") async throws {
        isTranscribing = true
        transcriptionStatus = "Starting transcription..."
        
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

/// Response model for transcription requests
struct WhisperResponse: Codable {
    /// Unique identifier for the transcription job
    let jobId: String
    /// Current status of the transcription (e.g., "completed")
    let status: String
    /// URL where the full transcript can be downloaded
    let transcriptUrl: String
    /// The transcribed text content
    let text: String
} 