import Foundation

/// ViewModel responsible for handling video transcription functionality
@MainActor
class TranscriptionViewModel: ObservableObject {
    @Published var isTranscribing = false
    @Published var transcriptionStatus: String?
    @Published var transcriptionText: String?
    @Published var transcriptionProgress: Double = 0
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
    private var session: URLSession?
    
    nonisolated init() {
        Task { @MainActor in
            setupWebSocket()
        }
    }
    
    deinit {
        print("[TranscriptionViewModel] Deinit called")
        // Since we can't use Task in deinit, we'll just do the minimal cleanup
        webSocket?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
    }
    
    private func setupWebSocket() {
        print("[TranscriptionViewModel] Setting up WebSocket")
        session = URLSession(configuration: .default)
        guard let url = URL(string: wsUrl) else { return }
        
        webSocket = session?.webSocketTask(with: url)
        webSocket?.resume()
        
        receiveMessage()
    }
    
    private func disconnectWebSocket() {
        print("[TranscriptionViewModel] Disconnecting WebSocket")
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil
    }
    
    private func receiveMessage() {
        guard let webSocket = webSocket else { return }
        
        webSocket.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    Task { @MainActor in
                        self.handleWebSocketMessage(text)
                    }
                case .data(let data):
                    print("[TranscriptionViewModel] Received binary message: \(data)")
                @unknown default:
                    break
                }
                // Continue receiving messages only if webSocket is still active
                if self.webSocket != nil {
                    Task { @MainActor in
                        self.receiveMessage()
                    }
                }
                
            case .failure(let error):
                print("[TranscriptionViewModel] WebSocket receive error: \(error)")
                Task { @MainActor in
                    self.error = error
                }
            }
        }
    }
    
    private func handleWebSocketMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let message = try? JSONDecoder().decode(WebSocketMessage.self, from: data) else {
            print("Failed to decode WebSocket message")
            return
        }
        
        switch message.type {
        case "connection":
            print("WebSocket connected: \(message.message ?? "")")
        case "progress":
            transcriptionProgress = message.progress ?? 0
            updateTranscriptionStatus(for: message.progress ?? 0)
        case "error":
            error = NSError(domain: "Transcription",
                          code: -1,
                          userInfo: [NSLocalizedDescriptionKey: message.message ?? "Unknown error"])
        default:
            break
        }
    }
    
    private func updateTranscriptionStatus(for progress: Double) {
        switch progress {
        case 0:
            transcriptionStatus = "Starting transcription..."
        case 0.3:
            transcriptionStatus = "Processing video..."
        case 0.5:
            transcriptionStatus = "Transcribing audio..."
        case 1.0:
            transcriptionStatus = "Transcription completed!"
        default:
            transcriptionStatus = "Processing..."
        }
    }
    
    private func subscribeToTranscription(videoId: String) {
        let message = WebSocketMessage(type: "subscribe", videoId: videoId)
        if let data = try? JSONEncoder().encode(message),
           let text = String(data: data, encoding: .utf8) {
            webSocket?.send(.string(text)) { error in
                if let error = error {
                    print("WebSocket send error: \(error)")
                }
            }
        }
    }
    
    /// Start transcription for a video
    func startTranscription(videoUrl: String, videoId: String) async throws {
        isTranscribing = true
        transcriptionStatus = "Starting transcription..."
        transcriptionProgress = 0
        
        // Subscribe to real-time updates
        subscribeToTranscription(videoId: videoId)
        
        do {
            let url = URL(string: "\(serverUrl)/start-transcription")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body = ["videoUrl": videoUrl, "videoId": videoId]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }
            
            let result = try JSONDecoder().decode(WhisperResponse.self, from: data)
            transcriptionText = result.text
            
        } catch {
            self.error = error
            transcriptionStatus = "Transcription failed"
            isTranscribing = false
            throw error
        }
    }
    
    // Public cleanup method that can be called from outside
    func cleanupResources() {
        print("[TranscriptionViewModel] Cleanup called")
        isTranscribing = false
        transcriptionStatus = nil
        transcriptionText = nil
        transcriptionProgress = 0
        error = nil
        disconnectWebSocket()
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

/// WebSocket message model
struct WebSocketMessage: Codable {
    let type: String
    let message: String?
    let videoId: String?
    let progress: Double?
    
    init(type: String, message: String? = nil, videoId: String? = nil, progress: Double? = nil) {
        self.type = type
        self.message = message
        self.videoId = videoId
        self.progress = progress
    }
} 