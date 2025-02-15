import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import Network

@MainActor
class VideoFeedViewModel: ObservableObject {
    @Published var videos: [Video] = []
    @Published var error: String?
    @Published var isLoadingMore = false
    @Published var isRefreshing = false
    @Published var isMuted = false  // Global mute state
    @Published var isOnline = true
    
    private var lastDocument: DocumentSnapshot?
    private var transcriptionListeners: [String: ListenerRegistration] = [:]
    private let pageSize = 5
    private let db = Firestore.firestore()
    private var networkMonitor = NWPathMonitor()
    private var retryTask: Task<Void, Never>?
    
    init() {
        setupNetworkMonitoring()
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
                if path.status == .satisfied {
                    self?.retryFailedOperations()
                }
            }
        }
        networkMonitor.start(queue: DispatchQueue.global())
    }
    
    private func retryFailedOperations() {
        retryTask?.cancel()
        retryTask = Task {
            if videos.isEmpty {
                await fetchVideos()
            }
            for video in videos {
                await refreshVideoState(video)
            }
        }
    }
    
    private func refreshVideoState(_ video: Video) async {
        guard !Task.isCancelled else { return }
        do {
            let videoDoc = try await db.collection("videos").document(video.id).getDocument()
            if let updatedVideo = try? videoDoc.data(as: Video.self),
               let index = videos.firstIndex(where: { $0.id == video.id }) {
                videos[index] = updatedVideo
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func toggleMute() {
        isMuted.toggle()
    }
    
    func refreshVideos() async {
        guard !isRefreshing else { return }
        
        isRefreshing = true
        lastDocument = nil
        await fetchVideos()
        isRefreshing = false
    }
    
    func fetchVideos() async {
        do {
            let snapshot = try await db.collection("videos")
                .order(by: "createdAt", descending: true)
                .getDocuments()
            
            let videos = snapshot.documents.compactMap { document -> Video? in
                var data = document.data()
                let url = data["url"] as? String ?? data["videoUrl"] as? String ?? ""
                print("[DEBUG] Video URL from Firestore: \(url) for video ID: \(document.documentID)")
                
                guard !url.isEmpty else {
                    print("[DEBUG] Skipping video with empty URL: \(document.documentID)")
                    return nil
                }
                
                // Convert Firestore Timestamp to milliseconds since 1970
                if let createdAtTimestamp = data["createdAt"] as? Timestamp {
                    data["createdAt"] = createdAtTimestamp.dateValue().timeIntervalSince1970 * 1000
                }
                
                // Convert translations timestamps if they exist
                if var translations = data["translations"] as? [String: [String: Any]] {
                    for (language, var translationData) in translations {
                        if let lastUpdatedTimestamp = translationData["lastUpdated"] as? Timestamp {
                            translationData["lastUpdated"] = lastUpdatedTimestamp.dateValue().timeIntervalSince1970 * 1000
                            translations[language] = translationData
                        }
                    }
                    data["translations"] = translations
                }
                
                // Parse transcription segments if they exist
                var parsedSegments: [TranscriptionSegment]? = nil
                if let segments = try? document.get("transcriptionSegments") as? [[String: Any]] {
                    parsedSegments = segments.compactMap { segmentData -> TranscriptionSegment? in
                        guard let text = segmentData["text"] as? String,
                              let startTime = segmentData["startTime"] as? Double,
                              let endTime = segmentData["endTime"] as? Double else {
                            return nil
                        }
                        return TranscriptionSegment(
                            text: text,
                            startTime: startTime,
                            endTime: endTime,
                            words: nil
                        )
                    }
                }
                
                // Convert to JSON and decode using our Codable implementation
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .millisecondsSince1970
                
                do {
                    let jsonData = try JSONSerialization.data(withJSONObject: data)
                    var video = try decoder.decode(Video.self, from: jsonData)
                    video.transcriptionSegments = parsedSegments
                    return video
                } catch {
                    print("[ERROR] Failed to decode video data: \(error)")
                    return nil
                }
            }
            
            print("[DEBUG] Fetched \(videos.count) valid videos with URLs")
            self.videos = videos
            self.lastDocument = snapshot.documents.last
            self.error = nil
            
            setupTranscriptionListeners()
            
        } catch {
            print("[ERROR] Failed to fetch videos: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }
    
    private func setupTranscriptionListeners() {
        // Remove existing listeners
        for listener in transcriptionListeners.values {
            listener.remove()
        }
        transcriptionListeners.removeAll()
        
        // Set up listeners for all videos
        for video in videos {
            print("[DEBUG] Setting up transcription listener for video: \(video.id)")
            print("[DEBUG] Current transcription status: \(video.transcriptionStatus ?? "nil")")
            
            let listener = db.collection("videos").document(video.id)
                .addSnapshotListener { [weak self] documentSnapshot, error in
                    guard let self = self else { return }
                    
                    if let error = error {
                        print("[ERROR] Transcription listener error: \(error.localizedDescription)")
                        self.error = error.localizedDescription
                        return
                    }
                    
                    guard let document = documentSnapshot, document.exists else {
                        print("[DEBUG] Document does not exist for video: \(video.id)")
                        return
                    }
                    
                    let data = document.data() ?? [:]
                    let transcriptionStatus = data["transcriptionStatus"] as? String
                    let transcriptionText = data["transcriptionText"] as? String
                    let transcriptionSegments = try? document.get("transcriptionSegments") as? [[String: Any]]
                    
                    print("[DEBUG] Received update for video \(video.id)")
                    print("[DEBUG] New transcription status: \(transcriptionStatus ?? "nil")")
                    print("[DEBUG] Has segments: \(transcriptionSegments != nil)")
                    
                    if let index = self.videos.firstIndex(where: { $0.id == video.id }) {
                        Task { @MainActor in
                            var updatedVideo = self.videos[index]
                            updatedVideo.transcriptionStatus = transcriptionStatus
                            updatedVideo.transcriptionText = transcriptionText
                            
                            if let segments = transcriptionSegments {
                                let parsedSegments: [TranscriptionSegment] = segments.compactMap { segmentData -> TranscriptionSegment? in
                                    guard let text = segmentData["text"] as? String,
                                          let startTime = segmentData["startTime"] as? Double,
                                          let endTime = segmentData["endTime"] as? Double else {
                                        return nil
                                    }
                                    return TranscriptionSegment(
                                        text: text,
                                        startTime: startTime,
                                        endTime: endTime,
                                        words: nil
                                    )
                                }
                                
                                if !parsedSegments.isEmpty {
                                    print("[DEBUG] Updated segments for video \(video.id): \(parsedSegments.count) segments")
                                    updatedVideo.transcriptionSegments = parsedSegments
                                }
                            }
                            
                            self.videos[index] = updatedVideo
                        }
                    }
                }
            
            transcriptionListeners[video.id] = listener
        }
    }
    
    deinit {
        for listener in transcriptionListeners.values {
            listener.remove()
        }
        transcriptionListeners.removeAll()
        networkMonitor.cancel()
        retryTask?.cancel()
    }
    
    func fetchMoreVideos() async {
        guard !isLoadingMore, let lastDocument = lastDocument else { return }
        
        isLoadingMore = true
        defer { isLoadingMore = false }
        
        do {
            let query = db.collection("videos")
                .order(by: "createdAt", descending: true)
                .limit(to: pageSize)
                .start(afterDocument: lastDocument)
            
            let snapshot = try await query.getDocuments()
            
            let newVideos = snapshot.documents.compactMap { document -> Video? in
                let data = document.data()
                let url = data["url"] as? String ?? data["videoUrl"] as? String ?? ""
                
                guard !url.isEmpty else { return nil }
                
                // Parse transcription segments if they exist
                var parsedSegments: [TranscriptionSegment]? = nil
                if let segments = try? document.get("transcriptionSegments") as? [[String: Any]] {
                    parsedSegments = segments.compactMap { segmentData -> TranscriptionSegment? in
                        guard let text = segmentData["text"] as? String,
                              let startTime = segmentData["startTime"] as? Double,
                              let endTime = segmentData["endTime"] as? Double else {
                            return nil
                        }
                        return TranscriptionSegment(
                            text: text,
                            startTime: startTime,
                            endTime: endTime,
                            words: nil
                        )
                    }
                }
                
                return Video(
                    id: document.documentID,
                    userId: data["userId"] as? String ?? "",
                    title: data["title"] as? String ?? "",
                    description: data["description"] as? String,
                    url: url,
                    thumbnailUrl: data["thumbnailUrl"] as? String,
                    createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                    viewCount: data["viewCount"] as? Int ?? 0,
                    transcriptionStatus: data["transcriptionStatus"] as? String,
                    transcriptionText: data["transcriptionText"] as? String,
                    transcriptionSegments: parsedSegments,
                    translations: nil
                )
            }
            
            self.videos.append(contentsOf: newVideos)
            self.lastDocument = snapshot.documents.last
            self.error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    private func createVideoData(_ video: Video) -> [String: Any] {
        let data: [String: Any] = [
            "title": video.title,
            "description": video.description as Any,
            "videoUrl": video.url,
            "userId": video.userId,
            "createdAt": video.createdAt,
            "viewCount": video.viewCount,
            "thumbnailUrl": video.thumbnailUrl as Any,
            "transcriptionStatus": video.transcriptionStatus as Any,
            "transcriptionText": video.transcriptionText as Any,
            "transcriptionSegments": video.transcriptionSegments as Any
        ]
        return data
    }
    
    #if DEBUG
    func seedTestData() async {
        let testVideos = [
            Video(
                id: UUID().uuidString,
                userId: "test_user",
                title: "Test Video 1",
                description: "Test video with valid URL",
                url: "https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4",
                thumbnailUrl: nil,
                createdAt: Date(),
                viewCount: 0,
                transcriptionStatus: nil,
                transcriptionText: nil,
                transcriptionSegments: nil
            ),
            Video(
                id: UUID().uuidString,
                userId: "test_user",
                title: "Test Video 2",
                description: "Another test video with valid URL",
                url: "https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4",
                thumbnailUrl: nil,
                createdAt: Date().addingTimeInterval(-86400),
                viewCount: 0,
                transcriptionStatus: nil,
                transcriptionText: nil,
                transcriptionSegments: nil
            )
        ]
        
        do {
            for video in testVideos {
                let data = createVideoData(video)
                try await db.collection("videos").document(video.id).setData(data)
            }
            await fetchVideos()
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func verifyAndSeedTestData() async {
        let snapshot = try? await db.collection("videos").getDocuments()
        let hasValidVideos = snapshot?.documents.contains { doc in
            let data = doc.data()
            return data["videoUrl"] as? String != nil && !(data["videoUrl"] as! String).isEmpty
        } ?? false
        
        if !hasValidVideos {
            await seedTestData()
        }
    }
    
    func clearAllVideos() async {
        do {
            let snapshot = try await db.collection("videos").getDocuments()
            for document in snapshot.documents {
                try await document.reference.delete()
            }
            self.videos = []
        } catch {
            self.error = error.localizedDescription
        }
    }

    func resetAndSeedTestData() async {
        await clearAllVideos()
        await seedTestData()
    }
    #endif
}

extension Video: @unchecked Sendable {} 