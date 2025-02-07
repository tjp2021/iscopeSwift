import Foundation
import FirebaseFirestore

struct Comment: Identifiable {
    let id: String
    let videoId: String?
    let text: String
    let userId: String
    let userDisplayName: String
    let userEmail: String?
    let createdAt: Date
    let likeCount: Int
    let isLiked: Bool
    
    static func from(_ document: QueryDocumentSnapshot) -> Comment? {
        let data = document.data()
        return Comment(
            id: document.documentID,
            videoId: nil,  // This will be set by the caller when needed
            text: data["text"] as? String ?? "",
            userId: data["userId"] as? String ?? "",
            userDisplayName: data["userDisplayName"] as? String ?? "Anonymous",
            userEmail: data["userEmail"] as? String,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            likeCount: data["likeCount"] as? Int ?? 0,
            isLiked: false  // This will be set by the caller when needed
        )
    }
} 