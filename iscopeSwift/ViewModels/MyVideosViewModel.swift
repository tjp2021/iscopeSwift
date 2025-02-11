import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
class MyVideosViewModel: ObservableObject {
    @Published var videos: [Video] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var showError = false
    
    private let db = Firestore.firestore()
    
    func fetchUserVideos() async {
        guard let userId = Auth.auth().currentUser?.uid else {
            error = "User not authenticated"
            showError = true
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            print("[MyVideosViewModel] Fetching videos for user: \(userId)")
            let snapshot = try await db.collection("videos")
                .whereField("userId", isEqualTo: userId)
                .order(by: "createdAt", descending: true)
                .getDocuments()
            
            print("[MyVideosViewModel] Found \(snapshot.documents.count) videos")
            
            self.videos = snapshot.documents.compactMap { document in
                let data = document.data()
                return Video(
                    id: document.documentID,
                    userId: data["userId"] as? String ?? "",
                    title: data["title"] as? String ?? "",
                    description: data["description"] as? String,
                    url: data["url"] as? String ?? "",
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
        } catch {
            print("[MyVideosViewModel] Error fetching videos: \(error.localizedDescription)")
            self.error = error.localizedDescription
            self.showError = true
        }
    }
    
    func deleteVideo(_ video: Video) async {
        do {
            print("[MyVideosViewModel] Deleting video: \(video.id)")
            
            // Delete video document
            try await db.collection("videos").document(video.id).delete()
            
            // Remove from local array
            if let index = videos.firstIndex(where: { $0.id == video.id }) {
                videos.remove(at: index)
            }
            
            print("[MyVideosViewModel] Successfully deleted video")
        } catch {
            print("[MyVideosViewModel] Error deleting video: \(error.localizedDescription)")
            self.error = error.localizedDescription
            self.showError = true
        }
    }
} 