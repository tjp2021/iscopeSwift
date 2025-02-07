import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct VideoEngagementView: View {
    @Binding var video: Video
    @ObservedObject var viewModel: VideoFeedViewModel
    @StateObject private var engagementViewModel = EngagementViewModel()
    @State private var showComments = false
    @State private var showingUploadSheet = false
    @State private var showingMyVideosSheet = false
    @State private var newComment = ""
    @State private var showLikeAnimation = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Like button
            Button {
                Task {
                    let updatedVideo = await engagementViewModel.toggleLike(for: video)
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
                    await engagementViewModel.fetchComments(for: video.id)
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
            
            // Mute button
            Button {
                viewModel.toggleMute()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    Text(viewModel.isMuted ? "Unmute" : "Mute")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
                .frame(width: 50, height: 50)
                .contentShape(Rectangle())
            }
            
            // Upload button
            Button {
                showingUploadSheet = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .frame(width: 50, height: 50)
                .contentShape(Rectangle())
            }
            
            // My Videos button (using profile photo)
            Button {
                showingMyVideosSheet = true
            } label: {
                VStack(spacing: 4) {
                    // TODO: Replace with actual profile photo when available
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .frame(width: 50, height: 50)
                .contentShape(Rectangle())
            }
        }
        .padding(.trailing, 8)
        .padding(.top, 50)
        .sheet(isPresented: $showComments) {
            CommentsView(video: $video)
        }
        .sheet(isPresented: $showingUploadSheet) {
            UploadVideoView()
        }
        .sheet(isPresented: $showingMyVideosSheet) {
            MyVideosView()
        }
    }
} 