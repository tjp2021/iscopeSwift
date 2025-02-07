import SwiftUI
import FirebaseAuth
import AVKit

struct GridVideoPlayerView: View {
    let video: Video
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var isPlayerReady = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                if let player = player, isPlayerReady {
                    VideoPlayer(player: player)
                        .edgesIgnoringSafeArea(.all)
                } else {
                    ProgressView()
                        .tint(.white)
                }
                
                VStack {
                    Spacer()
                    VStack(alignment: .leading, spacing: 8) {
                        Text(video.title)
                            .font(.title2)
                            .foregroundColor(.white)
                        Text(video.description)
                            .font(.body)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding()
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [.clear, .black.opacity(0.7)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button(action: {
                player?.pause()
                dismiss()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white)
            })
            .task {
                setupPlayer()
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
        }
    }
    
    private func setupPlayer() {
        guard let url = URL(string: video.videoUrl) else {
            print("[GridVideoPlayer] Failed to create URL from: \(video.videoUrl)")
            return
        }
        
        print("[GridVideoPlayer] Setting up player for: \(video.title)")
        let newPlayer = AVPlayer(url: url)
        
        // Add observer for player readiness
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemNewAccessLogEntry,
            object: newPlayer.currentItem,
            queue: .main
        ) { _ in
            print("[GridVideoPlayer] Player ready for: \(video.title)")
            isPlayerReady = true
            newPlayer.play()
        }
        
        self.player = newPlayer
    }
}

struct CreatorVideoDetailView: View {
    let video: Video
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var showingDeleteConfirmation = false
    @StateObject private var viewModel = MyVideosViewModel()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Video Player Section
                    ZStack {
                        if let player = player {
                            VideoPlayer(player: player)
                                .aspectRatio(16/9, contentMode: .fit)
                                .overlay(
                                    Button(action: {
                                        isPlaying.toggle()
                                        if isPlaying {
                                            player.play()
                                        } else {
                                            player.pause()
                                        }
                                    }) {
                                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                            .font(.system(size: 72))
                                            .foregroundStyle(.white.opacity(0.8))
                                    }
                                    .opacity(isPlaying ? 0 : 1)
                                )
                        } else {
                            ProgressView()
                                .aspectRatio(16/9, contentMode: .fit)
                        }
                    }
                    
                    // Video Info Section
                    VStack(alignment: .leading, spacing: 16) {
                        // Title and Description
                        VStack(alignment: .leading, spacing: 8) {
                            Text(video.title)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text(video.description)
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        
                        // Stats Row
                        HStack(spacing: 24) {
                            StatView(count: video.viewCount, icon: "eye.fill", label: "Views")
                            StatView(count: video.likeCount, icon: "heart.fill", label: "Likes")
                            StatView(count: video.commentCount, icon: "bubble.right.fill", label: "Comments")
                        }
                        
                        // Post Date
                        HStack {
                            Image(systemName: "clock")
                                .foregroundColor(.secondary)
                            Text("Posted \(video.createdAt, style: .relative)")
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)
                        
                        Divider()
                        
                        // Action Buttons
                        VStack(spacing: 12) {
                            Button(action: {
                                // Share functionality
                            }) {
                                Label("Share Video", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            
                            Button(action: {
                                showingDeleteConfirmation = true
                            }) {
                                Label("Delete Video", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button(action: {
                player?.pause()
                dismiss()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            })
            .confirmationDialog(
                "Delete Video",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    Task {
                        if let id = video.id {
                            await viewModel.deleteVideo(video)
                            dismiss()
                        }
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to delete this video? This action cannot be undone.")
            }
            .task {
                setupPlayer()
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
        }
    }
    
    private func setupPlayer() {
        guard let url = URL(string: video.videoUrl) else { return }
        let newPlayer = AVPlayer(url: url)
        self.player = newPlayer
    }
}

struct StatView: View {
    let count: Int
    let icon: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text("\(count)")
                    .font(.headline)
            }
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct MyVideosView: View {
    @StateObject private var viewModel = MyVideosViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var videoToDelete: Video?
    @State private var showingDeleteConfirmation = false
    @State private var selectedVideo: Video?
    @State private var showingVideoPlayer = false
    
    // Grid layout configuration
    private let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]
    
    var totalViews: Int {
        viewModel.videos.reduce(0) { $0 + $1.viewCount }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                } else if viewModel.videos.isEmpty {
                    VStack(spacing: 16) {
                        ProfileHeaderView(totalVideos: 0, totalViews: 0)
                        
                        Spacer()
                        
                        Image(systemName: "video.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No Videos Yet")
                            .font(.headline)
                        Text("Videos you upload will appear here")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ProfileHeaderView(totalVideos: viewModel.videos.count, totalViews: totalViews)
                                .padding(.bottom)
                            
                            LazyVGrid(columns: columns, spacing: 1) {
                                ForEach(viewModel.videos) { video in
                                    VideoGridItem(video: video)
                                        .aspectRatio(1, contentMode: .fill)
                                        .frame(maxWidth: .infinity)
                                        .clipped()
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            selectedVideo = video
                                            showingVideoPlayer = true
                                        }
                                        .contextMenu {
                                            Button(role: .destructive) {
                                                videoToDelete = video
                                                showingDeleteConfirmation = true
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                            
                                            Button {
                                                // Edit functionality to be added
                                            } label: {
                                                Label("Edit", systemImage: "pencil")
                                            }
                                        }
                                }
                            }
                        }
                    }
                    .refreshable {
                        await viewModel.fetchUserVideos()
                    }
                }
            }
            .navigationTitle("My Videos")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(leading: Button("Done") {
                dismiss()
            })
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.error ?? "An unknown error occurred")
            }
            .confirmationDialog(
                "Delete Video",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                if let video = videoToDelete {
                    Button("Delete", role: .destructive) {
                        Task {
                            await viewModel.deleteVideo(video)
                            videoToDelete = nil
                        }
                    }
                }
                Button("Cancel", role: .cancel) {
                    videoToDelete = nil
                }
            } message: {
                Text("Are you sure you want to delete this video? This action cannot be undone.")
            }
            .fullScreenCover(isPresented: $showingVideoPlayer, content: {
                if let video = selectedVideo {
                    CreatorVideoDetailView(video: video)
                }
            })
            .onChange(of: selectedVideo) { _, video in
                if let video = video {
                    print("[MyVideosView] Video selected: \(video.title)")
                }
            }
            .onChange(of: showingVideoPlayer) { _, isShowing in
                print("[MyVideosView] Video player presentation state: \(isShowing)")
                if !isShowing {
                    selectedVideo = nil
                }
            }
            .onAppear {
                print("[MyVideosView] View appeared")
            }
            .onDisappear {
                print("[MyVideosView] View disappeared")
            }
        }
        .task {
            print("[MyVideosView] Task started - Fetching videos")
            await viewModel.fetchUserVideos()
        }
    }
}

#Preview {
    MyVideosView()
} 