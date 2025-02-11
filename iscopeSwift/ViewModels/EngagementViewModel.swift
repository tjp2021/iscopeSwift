import SwiftUI
import FirebaseFirestore
import FirebaseAuth

@MainActor
class EngagementViewModel: ObservableObject {
    @Published var comments: [Comment] = []
    @Published var error: String?
    @Published var isLoadingComments = false
    @Published var isPostingComment = false
    @Published var isTogglingLike = false
    @Published var showError = false
    @Published var hasMoreComments = true
    @Published private var likedVideoIds: Set<String> = []
    
    private let db = Firestore.firestore()
    private var lastCommentDocument: DocumentSnapshot?
    private let commentsPageSize = 20
    
    // MARK: - Like Functions
    
    func isVideoLiked(_ video: Video) -> Bool {
        return likedVideoIds.contains(video.id)
    }
    
    func handleLikeAction(for video: Video) async {
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
                likedVideoIds.remove(video.id)
            } else {
                // Like
                let likeData: [String: Any] = ["createdAt": FieldValue.serverTimestamp()]
                try await likeRef.setData(likeData)
                let updateData: [String: Any] = ["likeCount": FieldValue.increment(Int64(1))]
                try await videoRef.updateData(updateData)
                likedVideoIds.insert(video.id)
            }
        } catch {
            print("[EngagementViewModel] Error toggling like: \(error.localizedDescription)")
        }
    }
    
    func loadLikedStatus(for video: Video) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            let likeDoc = try await db.collection("videos")
                .document(video.id)
                .collection("likes")
                .document(userId)
                .getDocument()
            
            if likeDoc.exists {
                likedVideoIds.insert(video.id)
            } else {
                likedVideoIds.remove(video.id)
            }
        } catch {
            print("[EngagementViewModel] Error loading like status: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Comment Functions
    
    func fetchComments(for videoId: String?) async {
        guard let videoId = videoId else {
            self.error = "Invalid video ID"
            self.showError = true
            return
        }
        
        guard !isLoadingComments else { return }
        
        isLoadingComments = true
        defer { isLoadingComments = false }
        
        do {
            print("[EngagementViewModel] Fetching comments for video: \(videoId)")
            let query = db.collection("videos")
                .document(videoId)
                .collection("comments")
                .order(by: "createdAt", descending: true)
                .limit(to: commentsPageSize)
            
            let snapshot = try await query.getDocuments()
            print("[EngagementViewModel] Found \(snapshot.documents.count) comments")
            
            let newComments = snapshot.documents.compactMap { document -> Comment? in
                let data = document.data()
                return Comment(
                    id: document.documentID,
                    videoId: videoId,
                    text: data["text"] as? String ?? "",
                    userId: data["userId"] as? String ?? "",
                    userDisplayName: data["userDisplayName"] as? String ?? "Anonymous",
                    userEmail: data["userEmail"] as? String,
                    createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                    likeCount: data["likeCount"] as? Int ?? 0,
                    isLiked: false
                )
            }
            
            comments = newComments
            lastCommentDocument = snapshot.documents.last
            hasMoreComments = snapshot.documents.count == commentsPageSize
            error = nil
        } catch {
            print("[EngagementViewModel] Error fetching comments: \(error.localizedDescription)")
            self.error = error.localizedDescription
            self.showError = true
        }
    }
    
    func fetchMoreComments(for videoId: String?) async {
        guard let videoId = videoId else {
            self.error = "Invalid video ID"
            self.showError = true
            return
        }
        
        guard !isLoadingComments, hasMoreComments else { return }
        
        isLoadingComments = true
        defer { isLoadingComments = false }
        
        do {
            print("[EngagementViewModel] Fetching more comments for video: \(videoId)")
            guard let lastDoc = lastCommentDocument else {
                print("[EngagementViewModel] No last document reference")
                return
            }
            
            let query = db.collection("videos")
                .document(videoId)
                .collection("comments")
                .order(by: "createdAt", descending: true)
                .limit(to: commentsPageSize)
                .start(afterDocument: lastDoc)
            
            let snapshot = try await query.getDocuments()
            print("[EngagementViewModel] Found \(snapshot.documents.count) more comments")
            
            let newComments = snapshot.documents.compactMap { document -> Comment? in
                let data = document.data()
                return Comment(
                    id: document.documentID,
                    videoId: videoId,
                    text: data["text"] as? String ?? "",
                    userId: data["userId"] as? String ?? "",
                    userDisplayName: data["userDisplayName"] as? String ?? "Anonymous",
                    userEmail: data["userEmail"] as? String,
                    createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                    likeCount: data["likeCount"] as? Int ?? 0,
                    isLiked: false
                )
            }
            
            comments.append(contentsOf: newComments)
            lastCommentDocument = snapshot.documents.last
            hasMoreComments = snapshot.documents.count == commentsPageSize
            error = nil
        } catch {
            print("[EngagementViewModel] Error fetching more comments: \(error.localizedDescription)")
            self.error = error.localizedDescription
            self.showError = true
        }
    }
    
    func postComment(on videoId: String?, text: String, video: Video) async -> Video {
        guard let videoId = videoId else {
            print("[EngagementViewModel] ❌ Failed to post comment: Invalid video ID")
            self.error = "Invalid video ID"
            self.showError = true
            return video
        }
        
        print("[EngagementViewModel] Starting to post comment: '\(text)' for video: \(videoId)")
        
        // Check auth state
        guard let currentUser = Auth.auth().currentUser else {
            print("[EngagementViewModel] ❌ Failed to post comment: User not authenticated")
            self.error = "You must be signed in to comment"
            self.showError = true
            return video
        }
        
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("[EngagementViewModel] ❌ Failed to post comment: Empty text")
            self.error = "Comment cannot be empty"
            self.showError = true
            return video
        }
        
        // Get or set display name
        let userDisplayName = currentUser.displayName ?? "Anonymous"
        print("[EngagementViewModel] Posting comment as user: \(currentUser.uid), displayName: \(userDisplayName)")
        
        isPostingComment = true
        defer { isPostingComment = false }
        
        var updatedVideo = video
        
        do {
            let videoRef = db.collection("videos").document(videoId)
            let commentRef = videoRef.collection("comments").document()
            
            // Get video document outside transaction
            let videoDoc = try await videoRef.getDocument()
            let currentCommentCount = videoDoc.data()?["commentCount"] as? Int ?? 0
            
            let _ = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                // Create comment
                transaction.setData([
                    "text": text,
                    "userId": currentUser.uid,
                    "userDisplayName": userDisplayName,
                    "createdAt": Date(),
                    "likeCount": 0
                ], forDocument: commentRef)
                
                // Update video comment count
                transaction.updateData(["commentCount": currentCommentCount + 1], forDocument: videoRef)
                
                updatedVideo.commentCount = currentCommentCount + 1
                
                return nil
            })
            
            print("[EngagementViewModel] ✅ Successfully posted comment")
            
            // Refresh comments
            await fetchComments(for: videoId)
            
            return updatedVideo
        } catch {
            print("[EngagementViewModel] ❌ Error posting comment: \(error.localizedDescription)")
            self.error = error.localizedDescription
            self.showError = true
            return video
        }
    }
    
    func deleteComment(_ comment: Comment) async {
        // Since we've updated the Comment model to have optional videoId,
        // we need to handle the optional case here
        guard let videoId = comment.videoId else {
            print("[EngagementViewModel] ❌ Failed to delete comment: Invalid video ID")
            error = "Invalid video ID"
            showError = true
            return
        }
        
        do {
            let videoRef = db.collection("videos").document(videoId)
            let commentRef = videoRef.collection("comments").document(comment.id)
            
            // Get video document outside transaction
            let videoDoc = try await videoRef.getDocument()
            let currentCommentCount = videoDoc.data()?["commentCount"] as? Int ?? 0
            
            let _ = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                transaction.deleteDocument(commentRef)
                transaction.updateData(["commentCount": max(0, currentCommentCount - 1)], forDocument: videoRef)
                return nil
            })
            
            print("[EngagementViewModel] ✅ Successfully deleted comment")
            comments.removeAll { $0.id == comment.id }
        } catch {
            print("[EngagementViewModel] ❌ Error deleting comment: \(error.localizedDescription)")
            self.error = error.localizedDescription
            self.showError = true
        }
    }
    
    // MARK: - Data Verification
    
    func verifyDataPersistence(for videoId: String?) async {
        guard let videoId = videoId else {
            print("[EngagementViewModel] ❌ Failed to verify data: Invalid video ID")
            self.error = "Invalid video ID"
            self.showError = true
            return
        }
        print("[EngagementViewModel] Verifying data persistence for video: \(videoId)")
        await fetchComments(for: videoId)
    }
} 