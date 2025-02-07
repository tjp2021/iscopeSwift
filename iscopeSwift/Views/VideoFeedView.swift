import SwiftUI
import FirebaseFirestore
import AVKit
import Combine

struct VideoFeedView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @StateObject private var viewModel = VideoFeedViewModel()
    @State private var showingUploadSheet = false
    @State private var showError = false
    @State private var currentIndex = 0
    
    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(viewModel.videos) { video in
                VideoPageView(video: video)
                    .tag(video.id as String?)
                    .ignoresSafeArea()
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        .background(Color.black)
        .environment(\.layoutDirection, .rightToLeft)
        .overlay(alignment: .topTrailing) {
            VStack {
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
                        .foregroundColor(.white)
                        .padding()
                }
                
                Button {
                    showingUploadSheet = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundColor(.white)
                        .padding()
                }
            }
            .padding(.top, 50)
        }
        .sheet(isPresented: $showingUploadSheet) {
            UploadVideoView()
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

// Player Manager class to handle KVO
class VideoPlayerManager: NSObject, ObservableObject {
    @Published var isLoading = true
    private var player: AVPlayer?
    private var playerItemContext = 0
    private var cancellables = Set<AnyCancellable>()
    
    func setupPlayer(for url: URL) -> AVPlayer {
        cleanup()
        
        let playerItem = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: playerItem)
        
        playerItem.addObserver(
            self,
            forKeyPath: #keyPath(AVPlayerItem.status),
            options: [.old, .new],
            context: &playerItemContext
        )
        
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            newPlayer.seek(to: .zero)
            newPlayer.play()
        }
        
        self.player = newPlayer
        return newPlayer
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard context == &playerItemContext else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }

        if keyPath == #keyPath(AVPlayerItem.status) {
            let status: AVPlayerItem.Status
            if let statusNumber = change?[.newKey] as? NSNumber {
                status = AVPlayerItem.Status(rawValue: statusNumber.intValue)!
            } else {
                status = .unknown
            }
            
            DispatchQueue.main.async { [weak self] in
                switch status {
                case .readyToPlay:
                    self?.isLoading = false
                    self?.player?.play()
                case .failed:
                    self?.isLoading = false
                    print("Player item failed with error: \(String(describing: self?.player?.currentItem?.error))")
                case .unknown:
                    self?.isLoading = true
                @unknown default:
                    self?.isLoading = false
                }
            }
        }
    }
    
    func cleanup() {
        if let player = player, let playerItem = player.currentItem {
            player.pause()
            playerItem.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.status))
            NotificationCenter.default.removeObserver(self)
        }
        player = nil
    }
    
    deinit {
        cleanup()
    }
}

struct VideoPageView: View {
    let video: Video
    @StateObject private var playerManager = VideoPlayerManager()
    @State private var player: AVPlayer?
    
    var body: some View {
        ZStack {
            if let player = player {
                CustomVideoPlayer(player: player)
                    .ignoresSafeArea()
                    .overlay(
                        VStack {
                            Spacer()
                            VStack(alignment: .leading, spacing: 8) {
                                Text(video.title)
                                    .font(.title3)
                                    .bold()
                                    .foregroundColor(.white)
                                Text(video.description)
                                    .font(.subheadline)
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
                    )
            }
            
            if playerManager.isLoading {
                ProgressView()
                    .tint(.white)
            }
        }
        .onAppear {
            setupVideo()
        }
        .onDisappear {
            playerManager.cleanup()
            player = nil
        }
    }
    
    private func setupVideo() {
        guard let url = URL(string: video.videoUrl) else { return }
        player = playerManager.setupPlayer(for: url)
    }
}

// Custom video player view to handle full screen
struct CustomVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
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