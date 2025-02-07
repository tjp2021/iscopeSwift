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
        guard !isLoadingComments else { return }
        
        isLoadingComments = true
        defer { isLoadingComments = false }
        
        do {
            let query = db.collection("videos").document(videoId)
                .collection("comments")
                .order(by: "createdAt", descending: true)
                .limit(to: commentsPageSize)
            
            let snapshot = try await query.getDocuments()
            
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
            print("[EngagementViewModel] Fetched \(self.comments.count) comments")
        } catch {
            print("[EngagementViewModel] Error fetching comments: \(error)")
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
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let userId = Auth.auth().currentUser?.uid,
              let userDisplayName = Auth.auth().currentUser?.displayName else { return video }
        
        isPostingComment = true
        defer { isPostingComment = false }
        
        var updatedVideo = video
        
        do {
            let videoRef = db.collection("videos").document(videoId)
            let commentRef = videoRef.collection("comments").document()
            
            _ = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                let videoDoc: DocumentSnapshot
                do {
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
                
                let currentCommentCount = videoData["commentCount"] as? Int ?? 0
                
                let commentData: [String: Any] = [
                    "userId": userId,
                    "userDisplayName": userDisplayName,
                    "text": text,
                    "createdAt": FieldValue.serverTimestamp(),
                    "likeCount": 0
                ]
                
                transaction.setData(commentData, forDocument: commentRef)
                transaction.updateData(["commentCount": currentCommentCount + 1], forDocument: videoRef)
                
                updatedVideo.commentCount = currentCommentCount + 1
                return nil
            })
            
            // Add the new comment to the local list
            let newComment = Comment(
                id: commentRef.documentID,
                videoId: videoId,
                userId: userId,
                userDisplayName: userDisplayName,
                text: text,
                createdAt: Date(),
                likeCount: 0,
                isLiked: false
            )
            
            // Insert at the beginning since we're showing newest first
            self.comments.insert(newComment, at: 0)
            print("[EngagementViewModel] Successfully posted comment. New count: \(updatedVideo.commentCount)")
        } catch {
            print("[EngagementViewModel] Error posting comment: \(error)")
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
} 