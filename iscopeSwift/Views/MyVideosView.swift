import SwiftUI
import FirebaseAuth

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
        NavigationView {
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
                                            print("[MyVideosView] Video selected: \(video.title)")
                                            selectedVideo = video
                                            showingVideoPlayer = true
                                            print("[MyVideosView] Presenting video player, showingVideoPlayer: \(showingVideoPlayer)")
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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
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
                    print("[MyVideosView] Creating VideoPlayerView for: \(video.title)")
                    NavigationView {
                        VideoPlayerView(video: video)
                        .navigationBarBackButtonHidden(true)
                    }
                    .navigationViewStyle(.stack)
                } else {
                    print("[MyVideosView] ❌ No video selected when presenting player")
                }
            })
        }
        .task {
            await viewModel.fetchUserVideos()
        }
    }
}

#Preview {
    MyVideosView()
} 