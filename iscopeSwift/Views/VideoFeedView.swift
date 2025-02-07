import SwiftUI
import FirebaseFirestore
import AVKit

struct VideoFeedView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @StateObject private var viewModel = VideoFeedViewModel()
    @State private var showingUploadSheet = false
    @State private var showError = false
    
    var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading videos...")
                } else if viewModel.videos.isEmpty {
                    ContentUnavailableView(
                        "No Videos",
                        systemImage: "video.slash",
                        description: Text("Videos you upload will appear here")
                    )
                    #if DEBUG
                    .overlay(alignment: .bottom) {
                        Button(action: {
                            Task {
                                await viewModel.seedTestData()
                            }
                        }) {
                            Text("Add Test Videos")
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                        .padding(.bottom, 50)
                    }
                    #endif
                } else {
                    List {
                        ForEach(viewModel.videos) { video in
                            NavigationLink {
                                VideoPlayerView(video: video)
                            } label: {
                                VideoRowView(video: video)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Video Feed")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        Task {
                            do {
                                try authViewModel.signOut()
                            } catch {
                                viewModel.error = error.localizedDescription
                                showError = true
                            }
                        }
                    }) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingUploadSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingUploadSheet) {
                UploadVideoView()
            }
            .refreshable {
                await viewModel.fetchVideos()
            }
            .task {
                await viewModel.fetchVideos()
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.error ?? "An unknown error occurred")
            }
        }
    }
}

struct VideoRowView: View {
    let video: Video
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(video.title)
                .font(.headline)
            Text(video.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
                Text(video.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct VideoPlayerView: View {
    let video: Video
    @State private var player: AVPlayer?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack {
            if let player = player {
                VideoPlayer(player: player)
                    .aspectRatio(16/9, contentMode: .fit)
            } else {
                ProgressView()
                    .aspectRatio(16/9, contentMode: .fit)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text(video.title)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(video.description)
                    .font(.body)
                    .foregroundColor(.secondary)
                
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                    Text("Posted \(video.createdAt, style: .relative)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            
            Spacer()
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let url = URL(string: video.videoUrl) {
                player = AVPlayer(url: url)
                player?.play()
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    player?.pause()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
} 