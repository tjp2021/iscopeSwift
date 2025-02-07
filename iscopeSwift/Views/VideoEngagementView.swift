import SwiftUI
import FirebaseAuth

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
                    await viewModel.fetchComments(for: video.id ?? "")
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
        .sheet(isPresented: $showComments) {
            CommentsView(video: $video, viewModel: viewModel)
        }
    }
}

struct CommentsView: View {
    @Binding var video: Video
    @ObservedObject var viewModel: EngagementViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var newComment = ""
    @State private var showError = false
    @FocusState private var isCommentFieldFocused: Bool
    
    var body: some View {
        NavigationView {
            VStack {
                if viewModel.isLoadingComments {
                    ProgressView()
                        .padding()
                } else if viewModel.comments.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.right")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No comments yet")
                            .font(.headline)
                        Text("Be the first to comment!")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .onAppear {
                        print("[CommentsView] No comments to display")
                    }
                } else {
                    List {
                        ForEach(viewModel.comments) { comment in
                            CommentRowView(comment: comment, viewModel: viewModel)
                                .onAppear {
                                    print("[CommentsView] Rendering comment: \(comment.id ?? "unknown") - '\(comment.text)'")
                                }
                        }
                        
                        if !viewModel.comments.isEmpty {
                            Color.clear
                                .frame(height: 50)
                                .onAppear {
                                    print("[CommentsView] Loading more comments...")
                                    Task {
                                        await viewModel.fetchMoreComments(for: video.id ?? "")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .onAppear {
                        print("[CommentsView] Displaying \(viewModel.comments.count) comments")
                    }
                }
                
                // Comment input
                VStack(spacing: 0) {
                    Divider()
                    HStack {
                        TextField("Add a comment...", text: $newComment)
                            .textFieldStyle(.roundedBorder)
                            .focused($isCommentFieldFocused)
                        
                        Button {
                            print("[CommentsView] Attempting to post comment: '\(newComment)'")
                            Task {
                                let updatedVideo = await viewModel.postComment(on: video.id ?? "", text: newComment, video: video)
                                if viewModel.error == nil {
                                    print("[CommentsView] Comment posted, updating video with new count: \(updatedVideo.commentCount)")
                                    video = updatedVideo
                                    newComment = ""
                                    isCommentFieldFocused = false
                                    
                                    // Verify data persistence
                                    await viewModel.verifyDataPersistence(for: video.id ?? "")
                                } else {
                                    showError = true
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(newComment.isEmpty ? .secondary : .blue)
                        }
                        .disabled(newComment.isEmpty || viewModel.isPostingComment)
                    }
                    .padding()
                }
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.error ?? "An unknown error occurred")
            }
            .onAppear {
                print("[CommentsView] View appeared")
                Task {
                    // Verify data persistence when view appears
                    await viewModel.verifyDataPersistence(for: video.id ?? "")
                }
            }
            .onDisappear {
                print("[CommentsView] View disappeared")
            }
        }
    }
}

struct CommentRowView: View {
    let comment: Comment
    @ObservedObject var viewModel: EngagementViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(comment.userDisplayName)
                    .font(.headline)
                Spacer()
                Text(comment.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(comment.text)
                .font(.body)
            
            HStack {
                Button {
                    // Like comment functionality
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: comment.isLiked ? "heart.fill" : "heart")
                            .foregroundColor(comment.isLiked ? .red : .secondary)
                        if comment.likeCount > 0 {
                            Text("\(comment.likeCount)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                if let currentUserId = Auth.auth().currentUser?.uid,
                   currentUserId == comment.userId {
                    Button {
                        Task {
                            await viewModel.deleteComment(comment)
                        }
                    } label: {
                        Text("Delete")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
} 