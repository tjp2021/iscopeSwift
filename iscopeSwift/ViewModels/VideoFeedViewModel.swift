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
                    // Network is back, retry failed operations
                    self?.retryFailedOperations()
                }
            }
        }
        networkMonitor.start(queue: DispatchQueue.global())
    }
    
    private func retryFailedOperations() {
        retryTask?.cancel()
        retryTask = Task {
            // Retry loading videos if we have none
            if videos.isEmpty {
                await fetchVideos()
            }
            // Refresh existing video states
            for video in videos {
                await refreshVideoState(video)
            }
        }
    }
    
    private func refreshVideoState(_ video: Video) async {
        guard !Task.isCancelled else { return }
        // Refresh video metadata, likes, etc.
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
    
    func toggleLike(for video: Video) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            let likeRef = db.collection("videos").document(video.id).collection("likes").document(userId)
            let videoRef = db.collection("videos").document(video.id)
            
            let likeDoc = try await likeRef.getDocument()
            let isCurrentlyLiked = likeDoc.exists
            
            if isCurrentlyLiked {
                // Unlike
                try await likeRef.delete()
                let updateData: [String: Any] = ["likeCount": FieldValue.increment(Int64(-1))]
                try await videoRef.updateData(updateData)
                
                if let index = videos.firstIndex(where: { $0.id == video.id }) {
                    videos[index].likeCount -= 1
                }
            } else {
                // Like
                let likeData: [String: Any] = ["createdAt": FieldValue.serverTimestamp()]
                try await likeRef.setData(likeData)
                let updateData: [String: Any] = ["likeCount": FieldValue.increment(Int64(1))]
                try await videoRef.updateData(updateData)
                
                if let index = videos.firstIndex(where: { $0.id == video.id }) {
                    videos[index].likeCount += 1
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
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
            print("[VideoFeedViewModel] Starting to fetch videos")
            let snapshot = try await db.collection("videos")
                .order(by: "createdAt", descending: true)
                .getDocuments()
            
            print("[VideoFeedViewModel] Got \(snapshot.documents.count) videos from Firestore")
            
            let videos = snapshot.documents.compactMap { document -> Video? in
                let data = document.data()
                print("[VideoFeedViewModel] Processing video document: \(document.documentID)")
                print("[VideoFeedViewModel] Full document data: \(data)")
                print("[VideoFeedViewModel] URL field type: \(type(of: data["videoUrl"]))")
                print("[VideoFeedViewModel] URL field value: \(data["videoUrl"] ?? "missing")")
                
                return Video(
                    id: document.documentID,
                    userId: data["userId"] as? String ?? "",
                    title: data["title"] as? String ?? "",
                    description: data["description"] as? String,
                    url: data["videoUrl"] as? String ?? "",
                    thumbnailUrl: data["thumbnailUrl"] as? String,
                    createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                    viewCount: data["viewCount"] as? Int ?? 0,
                    likeCount: data["likeCount"] as? Int ?? 0,
                    commentCount: data["commentCount"] as? Int ?? 0,
                    transcriptionStatus: data["transcriptionStatus"] as? String,
                    transcriptionText: data["transcriptionText"] as? String,
                    transcriptionSegments: nil
                )
            }
            
            print("[VideoFeedViewModel] Processed \(videos.count) valid videos")
            for (index, video) in videos.enumerated() {
                print("[VideoFeedViewModel] Video \(index): ID=\(video.id), URL=\(video.url)")
            }
            
            self.videos = videos
            self.lastDocument = snapshot.documents.last
            self.error = nil
            
            // Set up real-time listeners for transcription updates
            setupTranscriptionListeners()
            
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    private func setupTranscriptionListeners() {
        for listener in transcriptionListeners.values {
            listener.remove()
        }
        transcriptionListeners.removeAll()
        
        for video in videos {
            let listener = db.collection("videos").document(video.id)
                .addSnapshotListener { [weak self] documentSnapshot, error in
                    guard let self = self else { return }
                    
                    if let error = error {
                        self.error = error.localizedDescription
                        return
                    }
                    
                    guard let document = documentSnapshot, document.exists else { return }
                    
                    let data = document.data() ?? [:]
                    let transcriptionStatus = data["transcriptionStatus"] as? String
                    let transcriptionText = data["transcriptionText"] as? String
                    
                    if let index = self.videos.firstIndex(where: { $0.id == video.id }) {
                        Task { @MainActor in
                            var updatedVideo = self.videos[index]
                            updatedVideo.transcriptionStatus = transcriptionStatus
                            updatedVideo.transcriptionText = transcriptionText
                            self.videos[index] = updatedVideo
                        }
                    }
                }
            
            transcriptionListeners[video.id] = listener
        }
    }
    
    deinit {
        // Clean up listeners
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
            
            let newVideos = snapshot.documents.compactMap { document in
                let data = document.data()
                return Video(
                    id: document.documentID,
                    userId: data["userId"] as? String ?? "",
                    title: data["title"] as? String ?? "",
                    description: data["description"] as? String,
                    url: data["videoUrl"] as? String ?? "",
                    thumbnailUrl: data["thumbnailUrl"] as? String,
                    createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                    viewCount: data["viewCount"] as? Int ?? 0,
                    likeCount: data["likeCount"] as? Int ?? 0,
                    commentCount: data["commentCount"] as? Int ?? 0,
                    transcriptionStatus: data["transcriptionStatus"] as? String,
                    transcriptionText: data["transcriptionText"] as? String,
                    transcriptionSegments: nil // We'll fetch this separately if needed
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
            "likeCount": video.likeCount,
            "commentCount": video.commentCount,
            "viewCount": video.viewCount,
            "thumbnailUrl": video.thumbnailUrl as Any,
            "transcriptionStatus": video.transcriptionStatus as Any,
            "transcriptionText": video.transcriptionText as Any
        ]
        return data
    }
    
    // MARK: - Development Helpers
    
    #if DEBUG
    func seedTestData() async {
        print("[VideoFeedViewModel] Starting to seed test data")
        let testVideos = [
            Video(
                id: UUID().uuidString,
                userId: "test_user",
                title: "Big Buck Bunny",
                description: "Test video with valid URL",
                url: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
                thumbnailUrl: nil,
                createdAt: Date(),
                viewCount: 0,
                likeCount: 0,
                commentCount: 0,
                transcriptionStatus: nil,
                transcriptionText: nil,
                transcriptionSegments: nil
            ),
            Video(
                id: UUID().uuidString,
                userId: "test_user",
                title: "Elephant Dream",
                description: "Another test video with valid URL",
                url: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4",
                thumbnailUrl: nil,
                createdAt: Date().addingTimeInterval(-86400),
                viewCount: 0,
                likeCount: 0,
                commentCount: 0,
                transcriptionStatus: nil,
                transcriptionText: nil,
                transcriptionSegments: nil
            )
        ]
        
        do {
            print("[VideoFeedViewModel] Creating test videos in Firestore")
            for video in testVideos {
                let data = createVideoData(video)
                print("[VideoFeedViewModel] Adding video with URL: \(video.url)")
                try await db.collection("videos").document(video.id).setData(data)
            }
            print("[VideoFeedViewModel] Test data seeded successfully")
            await fetchVideos()
        } catch {
            print("[VideoFeedViewModel] Error seeding test data: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }
    
    // Helper function to seed test data and verify URLs
    func verifyAndSeedTestData() async {
        print("[VideoFeedViewModel] Verifying existing videos...")
        let snapshot = try? await db.collection("videos").getDocuments()
        let hasValidVideos = snapshot?.documents.contains { doc in
            let data = doc.data()
            return data["videoUrl"] as? String != nil && !(data["videoUrl"] as! String).isEmpty
        } ?? false
        
        if !hasValidVideos {
            print("[VideoFeedViewModel] No valid videos found, seeding test data...")
            await seedTestData()
        } else {
            print("[VideoFeedViewModel] Valid videos found, skipping test data seeding")
        }
    }
    #endif
}

extension Video: @unchecked Sendable {} 