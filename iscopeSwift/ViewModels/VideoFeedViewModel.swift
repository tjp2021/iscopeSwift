import SwiftUI
import FirebaseFirestore

@MainActor
class VideoFeedViewModel: ObservableObject {
    @Published var videos: [Video] = []
    @Published var isLoading = false
    @Published var error: String?
    private let db = Firestore.firestore()
    
    func fetchVideos() async {
        isLoading = true
        error = nil
        
        do {
            let snapshot = try await db.collection("videos")
                .order(by: "created_at", descending: true)
                .getDocuments()
            
            videos = snapshot.documents.compactMap { document in
                try? document.data(as: Video.self)
            }
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    // MARK: - Development Helpers
    
    #if DEBUG
    func seedTestData() async {
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
                    "id": video.id!,
                    "title": video.title,
                    "description": video.description,
                    "video_url": video.videoUrl,
                    "creator_id": video.creatorId,
                    "created_at": video.createdAt
                ])
            }
            print("✅ Test data seeded successfully")
            await fetchVideos()
        } catch {
            print("❌ Error seeding test data: \(error.localizedDescription)")
        }
    }
    #endif
} 