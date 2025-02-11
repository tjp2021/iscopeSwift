import Foundation

/// ViewModel responsible for handling video transcription functionality
@MainActor
class TranscriptionViewModel: ObservableObject {
    @Published var isTranscribing = false
    @Published var transcriptionStatus: String?
    @Published var transcriptionText: String?
    @Published var transcriptionProgress: Double = 0
    @Published var transcriptionSegments: [TranscriptionSegment]?
    @Published var error: Error?
    
    // Single source of truth for server URL
    #if targetEnvironment(simulator)
    private let serverUrl = "http://127.0.0.1:3001"
    private let wsUrl = "ws://127.0.0.1:3001"
    #else
    private let serverUrl = "http://localhost:3001"
    private let wsUrl = "ws://localhost:3001"
    #endif
    
    private var webSocket: URLSessionWebSocketTask?
    private var timer: Timer?
    private var retryCount = 0
    private let maxRetries = 3
    
    init() {
        setupWebSocket()
    }
    
    deinit {
        // Just cleanup resources
        webSocket?.cancel()
        timer?.invalidate()
        webSocket = nil
        timer = nil
    }
    
    private func setupWebSocket() {
        print("[Transcription] Setting up WebSocket connection")
        guard let url = URL(string: wsUrl) else {
            print("[Transcription] ❌ Invalid WebSocket URL")
            return
        }
        
        let session = URLSession(configuration: .default)
        webSocket = session.webSocketTask(with: url)
        webSocket?.resume()
        receiveMessage()
    }
    
    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                
                switch result {
                case .success(let message):
                    switch message {
                    case .data(let data):
                        await self.handleWebSocketData(data)
                    case .string(let str):
                        if let data = str.data(using: .utf8) {
                            await self.handleWebSocketData(data)
                        }
                    @unknown default:
                        break
                    }
                    self.receiveMessage()
                    
                case .failure(let error):
                    print("[Transcription] ❌ WebSocket error:", error.localizedDescription)
                    await self.handleWebSocketFailure()
                }
            }
        }
    }
    
    private func handleWebSocketData(_ data: Data) async {
        do {
            let message = try JSONDecoder().decode(WebSocketMessage.self, from: data)
            if message.type == "progress" {
                self.transcriptionProgress = message.progress ?? 0
                self.updateTranscriptionStatus(for: message.progress ?? 0)
            }
        } catch {
            print("[Transcription] ❌ Failed to decode WebSocket message:", error)
        }
    }
    
    private func handleWebSocketFailure() async {
        if retryCount < maxRetries {
            retryCount += 1
            print("[Transcription] Retrying WebSocket connection (Attempt \(retryCount)/\(maxRetries))")
            setupWebSocket()
        }
    }
    
    private func updateTranscriptionStatus(for progress: Double) {
        if progress == 0 {
            transcriptionStatus = "Starting transcription..."
        } else if progress <= 0.3 {
            transcriptionStatus = "Processing video..."
        } else if progress < 1 {
            transcriptionStatus = "Transcribing audio..."
        } else if progress == 1 {
            transcriptionStatus = "Transcription completed!"
        } else {
            transcriptionStatus = "Processing..."
        }
    }
    
    private func subscribeToTranscription(videoId: String) {
        let message = ["type": "subscribe", "videoId": videoId]
        if let data = try? JSONEncoder().encode(message) {
            webSocket?.send(.data(data)) { error in
                if let error = error {
                    print("[Transcription] ❌ Failed to subscribe:", error)
                } else {
                    print("[Transcription] ✅ Subscribed to updates for video:", videoId)
                }
            }
        }
    }
    
    /// Start transcription for a video
    func startTranscription(videoUrl: String, videoId: String) async throws {
        print("[Transcription] Starting transcription for video:", videoId)
        transcriptionStatus = "Starting transcription..."
        transcriptionProgress = 0
        isTranscribing = true
        
        setupWebSocket()
        subscribeToTranscription(videoId: videoId)
        
        let url = URL(string: "\(serverUrl)/start-transcription")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["videoUrl": videoUrl, "videoId": videoId]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            print("[Transcription] ❌ Server error:", response)
            transcriptionStatus = "Transcription failed"
            throw NSError(domain: "Transcription",
                         code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                         userInfo: [NSLocalizedDescriptionKey: "Server error"])
        }
        
        let result = try JSONDecoder().decode(WhisperResponse.self, from: data)
        
        // Log timing data if available
        if let segments = result.segments {
            print("\n[Transcription] ✅ Received timing data:")
            print("Total segments:", segments.count)
            
            // Log first two segments for verification
            segments.prefix(2).forEach { segment in
                print("\nSegment:")
                print("Text:", segment.text)
                print("Time: \(segment.startTime)s -> \(segment.endTime)s")
                
                if let words = segment.words {
                    print("Words:")
                    words.forEach { word in
                        print("- '\(word.text)': \(word.startTime)s -> \(word.endTime)s")
                    }
                }
            }
        }
        
        transcriptionText = result.text
        transcriptionSegments = result.segments
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
    /// Transcription segments
    let segments: [TranscriptionSegment]?
}

/// WebSocket message model
struct WebSocketMessage: Codable {
    let type: String
    let progress: Double?
    let videoId: String?
} 