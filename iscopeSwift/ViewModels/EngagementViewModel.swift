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
    
    private let db = Firestore.firestore()
    private var lastCommentDocument: DocumentSnapshot?
    private let commentsPageSize = 20
    
    // MARK: - Like Functions
    
    func toggleLike(for video: Video) async -> Video {
        guard !isTogglingLike,
              let videoId = video.id,
              let userId = Auth.auth().currentUser?.uid else { return video }
        
        isTogglingLike = true
        defer { isTogglingLike = false }
        
        var updatedVideo = video
        
        do {
            let videoRef = db.collection("videos").document(videoId)
            let likeRef = videoRef.collection("likes").document(userId)
            
            _ = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                let likeDoc: DocumentSnapshot
                let videoDoc: DocumentSnapshot
                do {
                    likeDoc = try transaction.getDocument(likeRef)
                    videoDoc = try transaction.getDocument(videoRef)
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
                
                guard let videoData = videoDoc.data() else {
                    errorPointer?.pointee = NSError(
                        domain: "EngagementViewModel",
                        code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "Video not found"]
                    )
                    return nil
                }
                
                let currentLikeCount = videoData["likeCount"] as? Int ?? 0
                
                if likeDoc.exists {
                    // Unlike
                    transaction.deleteDocument(likeRef)
                    transaction.updateData(["likeCount": max(0, currentLikeCount - 1)], forDocument: videoRef)
                    updatedVideo.likeCount = max(0, currentLikeCount - 1)
                    updatedVideo.isLiked = false
                } else {
                    // Like
                    let likeData: [String: Any] = [
                        "userId": userId,
                        "createdAt": FieldValue.serverTimestamp()
                    ]
                    transaction.setData(likeData, forDocument: likeRef)
                    transaction.updateData(["likeCount": currentLikeCount + 1], forDocument: videoRef)
                    updatedVideo.likeCount = currentLikeCount + 1
                    updatedVideo.isLiked = true
                }
                
                return nil
            })
            
            print("[EngagementViewModel] Successfully toggled like. New count: \(updatedVideo.likeCount), isLiked: \(updatedVideo.isLiked)")
        } catch {
            print("[EngagementViewModel] Error toggling like: \(error)")
            self.error = error.localizedDescription
        }
        
        return updatedVideo
    }
    
    // MARK: - Comment Functions
    
    func fetchComments(for videoId: String) async {
        print("[EngagementViewModel] Starting to fetch comments for video: \(videoId)")
        guard !isLoadingComments else {
            print("[EngagementViewModel] Already loading comments, skipping fetch")
            return
        }
        
        isLoadingComments = true
        defer { isLoadingComments = false }
        
        do {
            let query = db.collection("videos").document(videoId)
                .collection("comments")
                .order(by: "createdAt", descending: true)
                .limit(to: commentsPageSize)
            
            print("[EngagementViewModel] Executing comments query")
            let snapshot = try await query.getDocuments()
            print("[EngagementViewModel] Got \(snapshot.documents.count) comments from Firestore")
            
            self.comments = snapshot.documents.compactMap { document in
                let data = document.data()
                return Comment(
                    id: document.documentID,
                    videoId: videoId,
                    userId: data["userId"] as? String ?? "",
                    userDisplayName: data["userDisplayName"] as? String ?? "Anonymous",
                    text: data["text"] as? String ?? "",
                    createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                    likeCount: data["likeCount"] as? Int ?? 0,
                    isLiked: false // We'll fetch this separately if needed
                )
            }
            
            self.lastCommentDocument = snapshot.documents.last
            print("[EngagementViewModel] ✅ Successfully processed \(self.comments.count) comments")
        } catch {
            print("[EngagementViewModel] ❌ Error fetching comments: \(error)")
            self.error = error.localizedDescription
        }
    }
    
    func fetchMoreComments(for videoId: String) async {
        guard !isLoadingComments,
              let lastDocument = lastCommentDocument else { return }
        
        isLoadingComments = true
        defer { isLoadingComments = false }
        
        do {
            let query = db.collection("videos").document(videoId)
                .collection("comments")
                .order(by: "createdAt", descending: true)
                .limit(to: commentsPageSize)
                .start(afterDocument: lastDocument)
            
            let snapshot = try await query.getDocuments()
            
            let newComments = snapshot.documents.compactMap { document in
                let data = document.data()
                return Comment(
                    id: document.documentID,
                    videoId: videoId,
                    userId: data["userId"] as? String ?? "",
                    userDisplayName: data["userDisplayName"] as? String ?? "Anonymous",
                    text: data["text"] as? String ?? "",
                    createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                    likeCount: data["likeCount"] as? Int ?? 0,
                    isLiked: false
                )
            }
            
            self.comments.append(contentsOf: newComments)
            self.lastCommentDocument = snapshot.documents.last
        } catch {
            print("[EngagementViewModel] Error fetching more comments: \(error)")
            self.error = error.localizedDescription
        }
    }
    
    func postComment(on videoId: String, text: String, video: Video) async -> Video {
        print("[EngagementViewModel] Starting to post comment: '\(text)' for video: \(videoId)")
        
        // Check auth state
        guard let currentUser = Auth.auth().currentUser else {
            print("[EngagementViewModel] ❌ Failed to post comment: User not authenticated")
            self.error = "You must be signed in to comment"
            return video
        }
        
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("[EngagementViewModel] ❌ Failed to post comment: Empty text")
            self.error = "Comment cannot be empty"
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
            print("[EngagementViewModel] Created new comment reference: \(commentRef.documentID)")
            
            _ = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                print("[EngagementViewModel] Starting transaction for comment creation")
                let videoDoc: DocumentSnapshot
                do {
                    videoDoc = try transaction.getDocument(videoRef)
                } catch {
                    print("[EngagementViewModel] ❌ Failed to get video document in transaction: \(error)")
                    errorPointer?.pointee = error as NSError
                    return nil
                }
                
                guard let videoData = videoDoc.data() else {
                    print("[EngagementViewModel] ❌ Video document data is nil")
                    errorPointer?.pointee = NSError(
                        domain: "EngagementViewModel",
                        code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "Video not found"]
                    )
                    return nil
                }
                
                let currentCommentCount = videoData["commentCount"] as? Int ?? 0
                print("[EngagementViewModel] Current comment count: \(currentCommentCount)")
                
                let commentData: [String: Any] = [
                    "userId": currentUser.uid,
                    "userDisplayName": userDisplayName,
                    "text": text,
                    "createdAt": FieldValue.serverTimestamp(),
                    "likeCount": 0
                ]
                
                transaction.setData(commentData, forDocument: commentRef)
                transaction.updateData(["commentCount": currentCommentCount + 1], forDocument: videoRef)
                
                updatedVideo.commentCount = currentCommentCount + 1
                print("[EngagementViewModel] Updated comment count in transaction: \(updatedVideo.commentCount)")
                return nil
            })
            
            // Add the new comment to the local list
            let newComment = Comment(
                id: commentRef.documentID,
                videoId: videoId,
                userId: currentUser.uid,
                userDisplayName: userDisplayName,
                text: text,
                createdAt: Date(),
                likeCount: 0,
                isLiked: false
            )
            
            // Insert at the beginning since we're showing newest first
            self.comments.insert(newComment, at: 0)
            print("[EngagementViewModel] ✅ Successfully added comment to local list. Comments count: \(self.comments.count)")
            print("[EngagementViewModel] ✅ Successfully posted comment. New count: \(updatedVideo.commentCount)")
        } catch {
            print("[EngagementViewModel] ❌ Error posting comment: \(error)")
            self.error = error.localizedDescription
        }
        
        return updatedVideo
    }
    
    func deleteComment(_ comment: Comment) async {
        guard let commentId = comment.id,
              let userId = Auth.auth().currentUser?.uid,
              userId == comment.userId else { return }
        
        do {
            let commentRef = db.collection("videos").document(comment.videoId)
                .collection("comments").document(commentId)
            
            try await commentRef.delete()
            
            // Update comment count on video
            try await db.collection("videos").document(comment.videoId).updateData([
                "commentCount": FieldValue.increment(Int64(-1))
            ])
            
            // Remove comment from local array
            comments.removeAll { $0.id == commentId }
        } catch {
            print("[EngagementViewModel] Error deleting comment: \(error)")
            self.error = error.localizedDescription
        }
    }
    
    // Add a function to verify data persistence
    func verifyDataPersistence(for videoId: String) async {
        print("[EngagementViewModel] Verifying data persistence for video: \(videoId)")
        
        do {
            let videoRef = db.collection("videos").document(videoId)
            let videoDoc = try await videoRef.getDocument()
            
            if let videoData = videoDoc.data() {
                let likeCount = videoData["likeCount"] as? Int ?? 0
                let commentCount = videoData["commentCount"] as? Int ?? 0
                print("[EngagementViewModel] ✅ Video data verified:")
                print("  - Like count: \(likeCount)")
                print("  - Comment count: \(commentCount)")
                
                // Check comments
                let commentsSnapshot = try await videoRef.collection("comments")
                    .order(by: "createdAt", descending: true)
                    .limit(to: 5)
                    .getDocuments()
                
                print("  - Recent comments:")
                for doc in commentsSnapshot.documents {
                    let data = doc.data()
                    print("    • \(data["userDisplayName"] as? String ?? "Anonymous"): \(data["text"] as? String ?? "")")
                }
                
                // Check likes
                if let userId = Auth.auth().currentUser?.uid {
                    let likeDoc = try await videoRef.collection("likes").document(userId).getDocument()
                    print("  - Current user like status: \(likeDoc.exists)")
                }
            } else {
                print("[EngagementViewModel] ❌ Video document not found")
            }
        } catch {
            print("[EngagementViewModel] ❌ Error verifying data: \(error)")
        }
    }
} 