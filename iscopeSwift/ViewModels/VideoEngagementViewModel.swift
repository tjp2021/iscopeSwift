import Foundation
import FirebaseFirestore

class VideoEngagementViewModel: ObservableObject {
    @Published private var likedVideoIds: Set<String> = []
    private let db = Firestore.firestore()
    
    func isVideoLiked(_ video: Video) -> Bool {
        return likedVideoIds.contains(video.id)
    }
    
    func handleLikeAction(for video: Video) {
        if likedVideoIds.contains(video.id) {
            likedVideoIds.remove(video.id)
        } else {
            likedVideoIds.insert(video.id)
        }
        // Update Firestore if needed
        updateLikeStatus(for: video)
    }
    
    private func updateLikeStatus(for video: Video) {
        // Implement Firestore update logic here if needed
        // This is just a placeholder for now since we're focusing on transcription
    }
} 