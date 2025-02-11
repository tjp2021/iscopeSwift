import SwiftUI
import FirebaseFirestore
import FirebaseAuth

@MainActor
class VideoFeedViewModel: ObservableObject {
    @Published var videos: [Video] = []
    @Published var error: String?
    @Published var isLoadingMore = false
    @Published var isRefreshing = false
    @Published var isMuted = false  // Global mute state
    
    private var lastDocument: DocumentSnapshot?
    private let pageSize = 5
    private let db = Firestore.firestore()
    
    func toggleMute() {
        isMuted.toggle()
    }
    
    func toggleLike(for video: Video) async {
        guard let videoId = video.id, let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            let likeRef = db.collection("videos").document(videoId).collection("likes").document(userId)
            let videoRef = db.collection("videos").document(videoId)
            
            if video.isLiked {
                // Unlike
                try await likeRef.delete()
                try await videoRef.updateData([
                    "likeCount": FieldValue.increment(Int64(-1))
                ])
                
                if let index = videos.firstIndex(where: { $0.id == videoId }) {
                    videos[index].isLiked = false
                    videos[index].likeCount -= 1
                }
            } else {
                // Like
                try await likeRef.setData(["createdAt": FieldValue.serverTimestamp()])
                try await videoRef.updateData([
                    "likeCount": FieldValue.increment(Int64(1))
                ])
                
                if let index = videos.firstIndex(where: { $0.id == videoId }) {
                    videos[index].isLiked = true
                    videos[index].likeCount += 1
                }
            }
        } catch {
            print("[VideoFeedViewModel] Error toggling like: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }
    
    func refreshVideos() async {
        print("[VideoFeedViewModel] Starting refresh")
        guard !isRefreshing else { return }
        
        isRefreshing = true
        lastDocument = nil
        await fetchVideos()
        isRefreshing = false
    }
    
    func fetchVideos() async {
        print("[VideoFeedViewModel] Starting to fetch videos")
        do {
            print("[VideoFeedViewModel] Executing Firestore query")
            let snapshot = try await db.collection("videos")
                .order(by: "createdAt", descending: true)
                .getDocuments()
            
            print("[VideoFeedViewModel] Got \(snapshot.documents.count) videos")
            
            // First, decode the basic video data
            var videos = snapshot.documents.compactMap { document -> Video? in
                let data = document.data()
                let transcriptionStatus = data["transcriptionStatus"] as? String
                let transcriptionText = data["transcriptionText"] as? String
                
                print("[VideoFeedViewModel] Video \(document.documentID):")
                print("  - Raw Data: \(data)")
                print("  - Transcription Status: \(String(describing: transcriptionStatus))")
                print("  - Transcription Text: \(String(describing: transcriptionText))")
                
                var video = Video(
                    id: document.documentID,
                    title: data["title"] as? String ?? "",
                    description: data["description"] as? String ?? "",
                    videoUrl: data["videoUrl"] as? String ?? "",
                    creatorId: data["creatorId"] as? String ?? "",
                    createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                    likeCount: data["likeCount"] as? Int ?? 0,
                    commentCount: data["commentCount"] as? Int ?? 0,
                    isLiked: false,
                    viewCount: data["viewCount"] as? Int ?? 0,
                    transcriptionStatus: transcriptionStatus,
                    transcriptionText: transcriptionText
                )
                
                // Verify the video object was created correctly
                print("[VideoFeedViewModel] Created video object:")
                print("  - ID: \(String(describing: video.id))")
                print("  - Status: \(String(describing: video.transcriptionStatus))")
                print("  - Text: \(String(describing: video.transcriptionText))")
                
                return video
            }
            
            // Then, if user is logged in, fetch like status for each video
            if let userId = Auth.auth().currentUser?.uid {
                print("[VideoFeedViewModel] Fetching like status for user: \(userId)")
                for i in 0..<videos.count {
                    if let videoId = videos[i].id {
                        let likeDoc = try? await db.collection("videos")
                            .document(videoId)
                            .collection("likes")
                            .document(userId)
                            .getDocument()
                        videos[i].isLiked = likeDoc?.exists ?? false
                    }
                }
            }
            
            print("[VideoFeedViewModel] Successfully processed \(videos.count) videos")
            self.videos = videos
            
            // Set up real-time listeners for transcription updates
            setupTranscriptionListeners()
            
        } catch {
            print("[VideoFeedViewModel] Error fetching videos: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }
    
    private func setupTranscriptionListeners() {
        print("[VideoFeedViewModel] Setting up transcription listeners")
        
        // Remove any existing listeners
        for listener in transcriptionListeners.values {
            listener.remove()
        }
        transcriptionListeners.removeAll()
        
        // Set up new listeners for each video
        for video in videos {
            guard let videoId = video.id else { continue }
            
            print("[VideoFeedViewModel] Setting up listener for video: \(videoId)")
            print("  - Current Status: \(String(describing: video.transcriptionStatus))")
            print("  - Current Text: \(String(describing: video.transcriptionText))")
            
            let listener = db.collection("videos").document(videoId)
                .addSnapshotListener { [weak self] documentSnapshot, error in
                    guard let self = self else { return }
                    
                    if let error = error {
                        print("[VideoFeedViewModel] Error listening to video \(videoId): \(error)")
                        return
                    }
                    
                    guard let document = documentSnapshot, document.exists else {
                        print("[VideoFeedViewModel] Document does not exist for video \(videoId)")
                        return
                    }
                    
                    let data = document.data() ?? [:]
                    print("[VideoFeedViewModel] Received update for video \(videoId):")
                    print("  - Raw Data: \(data)")
                    
                    let transcriptionStatus = data["transcriptionStatus"] as? String
                    let transcriptionText = data["transcriptionText"] as? String
                    
                    print("  - Status: \(String(describing: transcriptionStatus))")
                    print("  - Text: \(String(describing: transcriptionText))")
                    
                    if let index = self.videos.firstIndex(where: { $0.id == videoId }) {
                        print("[VideoFeedViewModel] Updating video at index: \(index)")
                        
                        Task { @MainActor in
                            // Create a new video instance with updated values
                            var updatedVideo = self.videos[index]
                            updatedVideo.transcriptionStatus = transcriptionStatus
                            updatedVideo.transcriptionText = transcriptionText
                            
                            // Update the videos array
                            self.videos[index] = updatedVideo
                            
                            print("[VideoFeedViewModel] Video updated successfully")
                            print("  - ID: \(videoId)")
                            print("  - New Status: \(String(describing: updatedVideo.transcriptionStatus))")
                            print("  - New Text: \(String(describing: updatedVideo.transcriptionText))")
                        }
                    } else {
                        print("[VideoFeedViewModel] Could not find video with ID: \(videoId)")
                    }
                }
            
            transcriptionListeners[videoId] = listener
        }
        
        print("[VideoFeedViewModel] Finished setting up \(transcriptionListeners.count) listeners")
    }
    
    private var transcriptionListeners: [String: ListenerRegistration] = [:]
    
    deinit {
        // Clean up listeners
        for listener in transcriptionListeners.values {
            listener.remove()
        }
        transcriptionListeners.removeAll()
    }
    
    func fetchMoreVideos() async {
        print("[VideoFeedViewModel] Starting to fetch more videos")
        guard !isLoadingMore, let lastDocument = lastDocument else {
            print("[VideoFeedViewModel] Cannot fetch more: isLoadingMore=\(isLoadingMore), lastDocument=\(lastDocument != nil)")
            return
        }
        
        isLoadingMore = true
        defer { isLoadingMore = false }
        
        do {
            let query = db.collection("videos")
                .order(by: "createdAt", descending: true)
                .limit(to: pageSize)
                .start(afterDocument: lastDocument)
            
            print("[VideoFeedViewModel] Executing pagination query")
            let snapshot = try await query.getDocuments()
            print("[VideoFeedViewModel] Got \(snapshot.documents.count) additional videos")
            
            let newVideos = snapshot.documents.compactMap { document in
                let data = document.data()
                return Video(
                    id: document.documentID,
                    title: data["title"] as? String ?? "",
                    description: data["description"] as? String ?? "",
                    videoUrl: data["videoUrl"] as? String ?? "",
                    creatorId: data["creatorId"] as? String ?? "",
                    createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                    likeCount: data["likeCount"] as? Int ?? 0,
                    commentCount: data["commentCount"] as? Int ?? 0,
                    isLiked: false,
                    viewCount: data["viewCount"] as? Int ?? 0
                )
            }
            
            // Fetch like status for each video if user is logged in
            if let userId = Auth.auth().currentUser?.uid {
                await withTaskGroup(of: (String, Bool).self) { group in
                    for video in newVideos {
                        group.addTask {
                            let likeDoc = try? await self.db.collection("videos")
                                .document(video.id ?? "")
                                .collection("likes")
                                .document(userId)
                                .getDocument()
                            return (video.id ?? "", likeDoc?.exists ?? false)
                        }
                    }
                    
                    var likeStatuses: [String: Bool] = [:]
                    for await (videoId, isLiked) in group {
                        likeStatuses[videoId] = isLiked
                    }
                    
                    let updatedNewVideos = newVideos.map { video in
                        var updatedVideo = video
                        updatedVideo.isLiked = likeStatuses[video.id ?? ""] ?? false
                        return updatedVideo
                    }
                    
                    self.videos.append(contentsOf: updatedNewVideos)
                }
            } else {
                self.videos.append(contentsOf: newVideos)
            }
            
            self.lastDocument = snapshot.documents.last
            self.error = nil
            print("[VideoFeedViewModel] Successfully processed additional videos")
        } catch {
            print("[VideoFeedViewModel] Error fetching more videos: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }
    
    private func createVideoData(_ video: Video) -> [String: Any] {
        let data: [String: any Sendable] = [
            "title": video.title,
            "description": video.description,
            "videoUrl": video.videoUrl,
            "creatorId": video.creatorId,
            "createdAt": video.createdAt,
            "likeCount": video.likeCount,
            "commentCount": video.commentCount,
            "viewCount": video.viewCount
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
                title: "News Report Sample",
                description: "Short news clip with clear speech for testing transcription",
                videoUrl: "https://storage.googleapis.com/aai-web-samples/news.mp4",
                creatorId: "test_user",
                createdAt: Date(),
                likeCount: 0,
                commentCount: 0,
                isLiked: false,
                viewCount: 0
            ),
            Video(
                id: UUID().uuidString,
                title: "Mountain Hiking",
                description: "Epic hike through the mountains. The views were breathtaking!",
                videoUrl: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
                creatorId: "test_user",
                createdAt: Date().addingTimeInterval(-86400),
                likeCount: 0,
                commentCount: 0,
                isLiked: false,
                viewCount: 0
            )
        ]
        
        do {
            for video in testVideos {
                let data = createVideoData(video)
                try await db.collection("videos").document(video.id!).setData(data)
            }
            print("[VideoFeedViewModel] ✅ Test data seeded successfully")
            await fetchVideos()
        } catch {
            print("[VideoFeedViewModel] ❌ Error seeding test data: \(error.localizedDescription)")
        }
    }
    #endif
}

extension Video: @unchecked Sendable {}  // Since Video is a struct with only Sendable properties 