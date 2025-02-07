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
                .whereField("creatorId", isEqualTo: userId)
                .order(by: "createdAt", descending: true)
                .getDocuments()
            
            print("[MyVideosViewModel] Found \(snapshot.documents.count) videos")
            
            self.videos = snapshot.documents.compactMap { document in
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
        } catch {
            print("[MyVideosViewModel] Error fetching videos: \(error.localizedDescription)")
            self.error = error.localizedDescription
            self.showError = true
        }
    }
    
    func deleteVideo(_ video: Video) async {
        guard let videoId = video.id else {
            error = "Invalid video ID"
            showError = true
            return
        }
        
        do {
            print("[MyVideosViewModel] Deleting video: \(videoId)")
            
            // Delete video document
            try await db.collection("videos").document(videoId).delete()
            
            // Remove from local array
            videos.removeAll { $0.id == videoId }
            
            print("[MyVideosViewModel] Successfully deleted video")
        } catch {
            print("[MyVideosViewModel] Error deleting video: \(error.localizedDescription)")
            self.error = error.localizedDescription
            self.showError = true
        }
    }
} 