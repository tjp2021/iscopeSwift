import SwiftUI
import FirebaseFirestore

@MainActor
class VideoFeedViewModel: ObservableObject {
    @Published var videos: [Video] = []
    @Published var error: String?
    @Published var isLoadingMore = false
    @Published var isRefreshing = false
    
    private var lastDocument: DocumentSnapshot?
    private let pageSize = 5
    private let db = Firestore.firestore()
    
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
        guard !isLoadingMore else {
            print("[VideoFeedViewModel] Fetch already in progress")
            return
        }
        
        do {
            let query = db.collection("videos")
                .order(by: "createdAt", descending: true)
                .limit(to: pageSize)
            
            print("[VideoFeedViewModel] Executing Firestore query")
            let snapshot = try await query.getDocuments()
            print("[VideoFeedViewModel] Got \(snapshot.documents.count) videos")
            
            self.videos = snapshot.documents.compactMap { document in
                let data = document.data()
                return Video(
                    id: document.documentID,
                    title: data["title"] as? String ?? "",
                    description: data["description"] as? String ?? "",
                    videoUrl: data["videoUrl"] as? String ?? "",
                    creatorId: data["creatorId"] as? String ?? "",
                    createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                )
            }
            
            self.lastDocument = snapshot.documents.last
            self.error = nil
            print("[VideoFeedViewModel] Successfully processed videos")
        } catch {
            print("[VideoFeedViewModel] Error fetching videos: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
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
                    createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                )
            }
            
            self.videos.append(contentsOf: newVideos)
            self.lastDocument = snapshot.documents.last
            self.error = nil
            print("[VideoFeedViewModel] Successfully processed additional videos")
        } catch {
            print("[VideoFeedViewModel] Error fetching more videos: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }
    
    // MARK: - Development Helpers
    
    #if DEBUG
    func seedTestData() async {
        print("[VideoFeedViewModel] Starting to seed test data")
        let testVideos = [
            Video(
                id: UUID().uuidString,
                title: "Sunset at the Beach",
                description: "Beautiful sunset captured at Malibu Beach. The waves were perfect and the colors were amazing!",
                videoUrl: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4",
                creatorId: "test_user",
                createdAt: Date()
            ),
            Video(
                id: UUID().uuidString,
                title: "Mountain Hiking",
                description: "Epic hike through the mountains. The views were breathtaking and the weather was perfect for hiking.",
                videoUrl: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
                creatorId: "test_user",
                createdAt: Date().addingTimeInterval(-86400) // 1 day ago
            ),
            Video(
                id: UUID().uuidString,
                title: "City Timelapse",
                description: "24-hour timelapse of the city skyline. Watch as the city comes alive at night!",
                videoUrl: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4",
                creatorId: "test_user",
                createdAt: Date().addingTimeInterval(-172800) // 2 days ago
            )
        ]
        
        do {
            for video in testVideos {
                try await db.collection("videos").document(video.id!).setData([
                    "title": video.title,
                    "description": video.description,
                    "videoUrl": video.videoUrl,
                    "creatorId": video.creatorId,
                    "createdAt": video.createdAt
                ])
            }
            print("[VideoFeedViewModel] ✅ Test data seeded successfully")
            await fetchVideos()
        } catch {
            print("[VideoFeedViewModel] ❌ Error seeding test data: \(error.localizedDescription)")
        }
    }
    #endif
} 