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
            
            let videos = snapshot.documents.compactMap { document -> Video? in
                var data = document.data()
                let url = data["url"] as? String ?? data["videoUrl"] as? String ?? ""
                
                // Convert Firestore Timestamp to milliseconds since 1970
                if let createdAtTimestamp = data["createdAt"] as? Timestamp {
                    data["createdAt"] = createdAtTimestamp.dateValue().timeIntervalSince1970 * 1000
                }
                
                // Convert to JSON and decode using our Codable implementation
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .millisecondsSince1970
                
                do {
                    let jsonData = try JSONSerialization.data(withJSONObject: data)
                    return try decoder.decode(Video.self, from: jsonData)
                } catch {
                    print("[ERROR] Failed to decode video data: \(error)")
                    return nil
                }
            }
            
            self.videos = videos
            self.error = nil
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