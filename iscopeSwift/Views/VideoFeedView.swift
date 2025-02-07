import SwiftUI
import FirebaseFirestore
import AVKit

struct VideoFeedView: View {
    @StateObject private var viewModel = VideoFeedViewModel()
    @State private var showingUploadSheet = false
    
    var body: some View {
        NavigationView {
            List {
                ForEach(viewModel.videos) { video in
                    NavigationLink {
                        VideoPlayerView(video: video)
                    } label: {
                        VideoRowView(video: video)
                    }
                }
            }
            .navigationTitle("Video Feed")
            .toolbar {
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
            Text(video.createdAt, style: .relative)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct VideoPlayerView: View {
    let video: Video
    @State private var player: AVPlayer?
    
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
                
                Text("Posted \(video.createdAt, style: .relative)")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
    }
}

class VideoFeedViewModel: ObservableObject {
    @Published var videos: [Video] = []
    private let db = Firestore.firestore()
    
    @MainActor
    func fetchVideos() async {
        do {
            let snapshot = try await db.collection("videos")
                .order(by: "created_at", descending: true)
                .getDocuments()
            
            videos = snapshot.documents.compactMap { document in
                try? document.data(as: Video.self)
            }
        } catch {
            print("Error fetching videos: \(error.localizedDescription)")
        }
    }
} 