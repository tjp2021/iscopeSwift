import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct VideoEngagementView: View {
    @Binding var video: Video
    @StateObject private var viewModel = EngagementViewModel()
    @State private var showComments = false
    @State private var newComment = ""
    @State private var showLikeAnimation = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Like button
            Button {
                Task {
                    let updatedVideo = await viewModel.toggleLike(for: video)
                    video = updatedVideo
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        showLikeAnimation = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showLikeAnimation = false
                    }
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: video.isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 32))
                        .foregroundColor(video.isLiked ? .red : .white)
                        .scaleEffect(showLikeAnimation ? 1.3 : 1.0)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    Text("\(video.likeCount)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
                .frame(width: 50, height: 50)
                .contentShape(Rectangle())
            }
            
            // Comment button
            Button {
                Task {
                    await viewModel.fetchComments(for: video.id)
                    showComments = true
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "bubble.right")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    Text("\(video.commentCount)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
                .frame(width: 50, height: 50)
                .contentShape(Rectangle())
            }
            
            // Share button
            Button {
                // Share functionality
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    Text("Share")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
                .frame(width: 50, height: 50)
                .contentShape(Rectangle())
            }
        }
        .padding(.trailing, 8)
        .sheet(isPresented: $showComments, onDismiss: {
            Task {
                // Refresh video data to get updated comment count
                if let videoId = video.id {
                    let db = Firestore.firestore()
                    do {
                        let doc = try await db.collection("videos").document(videoId).getDocument()
                        if let data = doc.data(),
                           let commentCount = data["commentCount"] as? Int {
                            video.commentCount = commentCount
                        }
                    } catch {
                        print("[VideoEngagementView] Error refreshing video data: \(error.localizedDescription)")
                    }
                }
            }
        }) {
            CommentsView(video: video)
        }
    }
} 