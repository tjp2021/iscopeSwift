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
        GeometryReader { geometry in
            ZStack {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.videos) { video in
                            VideoPageView(video: video)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .id(video.id)
                        }
                    }
                }
                .scrollTargetBehavior(.paging)
                .background(Color.black)
                
                // Bottom toolbar with buttons
                VStack {
                    Spacer()
                    HStack(spacing: 30) {
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
                            VStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .foregroundColor(.white)
                                    .font(.system(size: 24))
                                    .frame(width: 44, height: 44)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                                Text("Sign Out")
                                    .foregroundColor(.white)
                                    .font(.caption)
                            }
                        }
                        
                        Button {
                            showingUploadSheet = true
                        } label: {
                            VStack {
                                Image(systemName: "plus")
                                    .foregroundColor(.white)
                                    .font(.system(size: 24))
                                    .frame(width: 44, height: 44)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                                Text("Upload")
                                    .foregroundColor(.white)
                                    .font(.caption)
                            }
                        }
                        
                        #if DEBUG
                        Button {
                            Task {
                                print("[VideoFeedView] Generating test data")
                                await viewModel.seedTestData()
                            }
                        } label: {
                            VStack {
                                Image(systemName: "doc.badge.plus")
                                    .foregroundColor(.white)
                                    .font(.system(size: 24))
                                    .frame(width: 44, height: 44)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                                Text("Test Data")
                                    .foregroundColor(.white)
                                    .font(.caption)
                            }
                        }
                        #endif
                    }
                    .padding(.bottom, geometry.safeAreaInsets.bottom + 20)
                    .padding(.horizontal)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [.clear, .black.opacity(0.5)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showingUploadSheet) {
            UploadVideoView()
        }
        .task {
            print("[VideoFeedView] Task started - Fetching videos")
            await viewModel.fetchVideos()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.error ?? "An unknown error occurred")
        }
        .onAppear {
            print("[VideoFeedView] View appeared")
        }
        .onDisappear {
            print("[VideoFeedView] View disappeared")
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
        print("[VideoPlayer] Setting up player for URL: \(url)")
        cleanup()
        
        let playerItem = AVPlayerItem(url: url)
        playerItem.automaticallyPreservesTimeOffsetFromLive = true
        let newPlayer = AVPlayer(playerItem: playerItem)
        
        // Enable background audio
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            print("[VideoPlayer] Audio session setup successful")
        } catch {
            print("[VideoPlayer] Audio session setup failed: \(error)")
        }
        
        playerItem.addObserver(
            self,
            forKeyPath: #keyPath(AVPlayerItem.status),
            options: [.old, .new],
            context: &playerItemContext
        )
        print("[VideoPlayer] Added status observer")
        
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            print("[VideoPlayer] Video reached end, looping")
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
                    print("[VideoPlayer] Status: Ready to play")
                    self?.isLoading = false
                    self?.player?.play()
                case .failed:
                    print("[VideoPlayer] Status: Failed to play")
                    if let error = self?.player?.currentItem?.error {
                        print("[VideoPlayer] Error: \(error)")
                    }
                    self?.isLoading = false
                case .unknown:
                    print("[VideoPlayer] Status: Unknown")
                    self?.isLoading = true
                @unknown default:
                    print("[VideoPlayer] Status: Unknown default case")
                    self?.isLoading = false
                }
            }
        }
    }
    
    func cleanup() {
        print("[VideoPlayer] Cleaning up resources")
        if let player = player, let playerItem = player.currentItem {
            player.pause()
            playerItem.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.status))
            NotificationCenter.default.removeObserver(self)
        }
        player = nil
        isLoading = true
    }
    
    deinit {
        print("[VideoPlayer] Manager being deallocated")
        cleanup()
    }
}

struct VideoPageView: View {
    let video: Video
    @StateObject private var playerManager = VideoPlayerManager()
    @State private var player: AVPlayer?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let player = player {
                    CustomVideoPlayer(player: player)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .edgesIgnoringSafeArea(.all)
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
        }
        .onAppear {
            print("[VideoPageView] View appeared for video: \(video.title)")
            setupVideo()
        }
        .onDisappear {
            print("[VideoPageView] View disappeared for video: \(video.title)")
            playerManager.cleanup()
            player = nil
        }
    }
    
    private func setupVideo() {
        guard let url = URL(string: video.videoUrl) else {
            print("[VideoPageView] Invalid URL for video: \(video.title)")
            return
        }
        print("[VideoPageView] Setting up video with URL: \(url)")
        player = playerManager.setupPlayer(for: url)
        player?.play()
    }
}

// Custom video player view to handle full screen
struct CustomVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        print("[CustomVideoPlayer] Creating AVPlayerViewController")
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        controller.allowsPictureInPicturePlayback = true
        player.play()
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        print("[CustomVideoPlayer] Updating AVPlayerViewController")
        uiViewController.player = player
        player.play()
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