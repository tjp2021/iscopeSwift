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
                    GridVideoPlayerView(video: video)
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