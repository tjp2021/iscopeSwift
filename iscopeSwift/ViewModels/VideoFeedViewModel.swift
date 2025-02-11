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
    
    func toggleLike(for video: Video) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            let likeRef = db.collection("videos").document(video.id).collection("likes").document(userId)
            let videoRef = db.collection("videos").document(video.id)
            
            let likeDoc = try await likeRef.getDocument()
            let isCurrentlyLiked = likeDoc.exists
            
            if isCurrentlyLiked {
                try await likeRef.delete()
                let updateData: [String: Any] = ["likeCount": FieldValue.increment(Int64(-1))]
                try await videoRef.updateData(updateData)
                
                if let index = videos.firstIndex(where: { $0.id == video.id }) {
                    videos[index].likeCount -= 1
                }
            } else {
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
            print("[VideoFeedViewModel] Fetching videos...")
            let snapshot = try await db.collection("videos")
                .order(by: "createdAt", descending: true)
                .getDocuments()
            
            let videos = snapshot.documents.compactMap { document -> Video? in
                let data = document.data()
                let url = data["videoUrl"] as? String ?? ""
                print("[VideoFeedViewModel] Found video with URL: \(url)")
                return Video(
                    id: document.documentID,
                    userId: data["userId"] as? String ?? "",
                    title: data["title"] as? String ?? "",
                    description: data["description"] as? String,
                    url: url,
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
            
            print("[VideoFeedViewModel] Fetched \(videos.count) videos")
            
            self.videos = videos
            self.lastDocument = snapshot.documents.last
            self.error = nil
            
            setupTranscriptionListeners()
            
        } catch {
            print("[VideoFeedViewModel] Error: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }
    
    private func setupTranscriptionListeners() {
        print("[VideoFeedViewModel] Setting up transcription listeners")
        for listener in transcriptionListeners.values {
            listener.remove()
        }
        transcriptionListeners.removeAll()
        
        for video in videos {
            print("[VideoFeedViewModel] Setting up listener for video \(video.id)")
            let listener = db.collection("videos").document(video.id)
                .addSnapshotListener { [weak self] documentSnapshot, error in
                    guard let self = self else { 
                        print("[VideoFeedViewModel] Self is nil in listener")
                        return 
                    }
                    
                    if let error = error {
                        print("[VideoFeedViewModel] Listener error for video \(video.id): \(error)")
                        self.error = error.localizedDescription
                        return
                    }
                    
                    guard let document = documentSnapshot, document.exists else {
                        print("[VideoFeedViewModel] No document found for video \(video.id)")
                        return
                    }
                    
                    let data = document.data() ?? [:]
                    print("[VideoFeedViewModel] Received update for video \(video.id)")
                    print("[VideoFeedViewModel] Transcription status: \(data["transcriptionStatus"] as? String ?? "nil")")
                    
                    let transcriptionStatus = data["transcriptionStatus"] as? String
                    let transcriptionText = data["transcriptionText"] as? String
                    
                    // Debug raw transcription segments data
                    if let rawSegments = try? document.get("transcriptionSegments") {
                        print("[VideoFeedViewModel] Raw segments type: \(type(of: rawSegments))")
                        print("[VideoFeedViewModel] Raw segments: \(rawSegments)")
                    } else {
                        print("[VideoFeedViewModel] No raw segments found in document")
                    }
                    
                    let transcriptionSegments = try? document.get("transcriptionSegments") as? [[String: Any]]
                    
                    if let index = self.videos.firstIndex(where: { $0.id == video.id }) {
                        Task { @MainActor in
                            var updatedVideo = self.videos[index]
                            updatedVideo.transcriptionStatus = transcriptionStatus
                            updatedVideo.transcriptionText = transcriptionText
                            
                            if let segments = transcriptionSegments {
                                print("[VideoFeedViewModel] Processing \(segments.count) segments for video \(video.id)")
                                var parsedSegments: [TranscriptionSegment] = []
                                
                                for segmentData in segments {
                                    if let text = segmentData["text"] as? String,
                                       let startTime = segmentData["startTime"] as? Double,
                                       let endTime = segmentData["endTime"] as? Double {
                                        let segment = TranscriptionSegment(
                                            text: text,
                                            startTime: startTime,
                                            endTime: endTime,
                                            words: nil
                                        )
                                        parsedSegments.append(segment)
                                        print("[VideoFeedViewModel] Parsed segment - text: \(text), time: \(startTime)-\(endTime)")
                                    } else {
                                        print("[VideoFeedViewModel] Failed to parse segment: \(segmentData)")
                                    }
                                }
                                
                                print("[VideoFeedViewModel] Successfully parsed \(parsedSegments.count) segments")
                                updatedVideo.transcriptionSegments = parsedSegments
                            } else {
                                print("[VideoFeedViewModel] No segments to process for video \(video.id)")
                            }
                            
                            print("[VideoFeedViewModel] Updating video in array with \(updatedVideo.transcriptionSegments?.count ?? 0) segments")
                            self.videos[index] = updatedVideo
                        }
                    } else {
                        print("[VideoFeedViewModel] Could not find video \(video.id) in videos array")
                    }
                }
            
            transcriptionListeners[video.id] = listener
        }
        print("[VideoFeedViewModel] Finished setting up \(transcriptionListeners.count) listeners")
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
                    transcriptionSegments: nil
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
    
    #if DEBUG
    func seedTestData() async {
        print("[VideoFeedViewModel] Seeding test data...")
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
                likeCount: 0,
                commentCount: 0,
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
                likeCount: 0,
                commentCount: 0,
                transcriptionStatus: nil,
                transcriptionText: nil,
                transcriptionSegments: nil
            )
        ]
        
        do {
            for video in testVideos {
                let data = createVideoData(video)
                try await db.collection("videos").document(video.id).setData(data)
                print("[VideoFeedViewModel] Adding test video with URL: \(video.url)")
            }
            print("[VideoFeedViewModel] Test data seeded successfully")
            await fetchVideos()
        } catch {
            print("[VideoFeedViewModel] Error seeding test data: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }
    
    func verifyAndSeedTestData() async {
        print("[VideoFeedViewModel] Verifying videos...")
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
    
    func clearAllVideos() async {
        print("[VideoFeedViewModel] Clearing all videos from database...")
        do {
            let snapshot = try await db.collection("videos").getDocuments()
            for document in snapshot.documents {
                print("[VideoFeedViewModel] Deleting video: \(document.documentID)")
                try await document.reference.delete()
            }
            print("[VideoFeedViewModel] Successfully cleared all videos")
            self.videos = []
        } catch {
            print("[VideoFeedViewModel] Error clearing videos: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }

    func resetAndSeedTestData() async {
        print("[VideoFeedViewModel] Starting database reset and seed...")
        await clearAllVideos()
        await seedTestData()
    }
    #endif
}

extension Video: @unchecked Sendable {} 