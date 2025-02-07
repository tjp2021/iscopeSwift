import SwiftUI
import AVKit
import Combine

// Player Manager class to handle KVO
class VideoPlayerManager: NSObject, ObservableObject {
    @Published var isLoading = true
    @Published var error: Error?
    @Published private(set) var currentTime: Double = 0
    
    private var player: AVPlayer?
    private var playerItemContext = 0
    private var timeObserverToken: Any?
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
        } catch {
            print("[VideoPlayer] Audio session setup failed: \(error)")
            self.error = error
        }
        
        // Add periodic time observer only in DEBUG mode
        #if DEBUG
        let interval = CMTime(seconds: 2, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
        }
        #endif
        
        playerItem.addObserver(
            self,
            forKeyPath: #keyPath(AVPlayerItem.status),
            options: [.old, .new],
            context: &playerItemContext
        )
        
        // Add error observer
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] notification in
            if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                print("[VideoPlayer] Failed to play to end: \(error)")
                self?.error = error
            }
        }
        
        // Add playback ended observer
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
                    self?.error = nil
                    self?.player?.play()
                case .failed:
                    if let error = self?.player?.currentItem?.error {
                        print("[VideoPlayer] Error: \(error)")
                        self?.error = error
                    }
                    self?.isLoading = false
                case .unknown:
                    self?.isLoading = true
                    self?.error = nil
                @unknown default:
                    self?.isLoading = false
                    self?.error = nil
                }
            }
        }
    }
    
    func cleanup() {
        if let player = player {
            player.pause()
            
            if let timeObserverToken = timeObserverToken {
                player.removeTimeObserver(timeObserverToken)
                self.timeObserverToken = nil
            }
            
            player.currentItem?.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.status))
            NotificationCenter.default.removeObserver(self)
        }
        
        player = nil
        isLoading = true
        error = nil
        currentTime = 0
    }
    
    deinit {
        cleanup()
    }
}

struct VideoPageView: View {
    @Binding var video: Video
    @ObservedObject var viewModel: VideoFeedViewModel
    @StateObject private var playerManager = VideoPlayerManager()
    @State private var player: AVPlayer?
    @State private var showError = false
    @State private var errorMessage: String?
    @State private var isRetrying = false
    @State private var isVisible = false
    @State private var showingComments = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let player = player {
                    CustomVideoPlayer(player: player)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .edgesIgnoringSafeArea(.all)
                        .overlay(alignment: .bottom) {
                            overlayContent
                        }
                        .overlay(alignment: .trailing) {
                            VideoEngagementView(video: $video, viewModel: viewModel)
                                .padding(.trailing, 16)
                                .padding(.bottom, 16)
                        }
                }
                
                if playerManager.isLoading && !isRetrying {
                    ZStack {
                        Color.black
                        ProgressView()
                            .tint(.white)
                    }
                }
                
                if showError {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.white)
                        Text(errorMessage ?? "Failed to load video")
                            .font(.headline)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        if !isRetrying {
                            Button("Retry") {
                                retryLoading()
                            }
                            .buttonStyle(.bordered)
                            .tint(.white)
                        } else {
                            ProgressView()
                                .tint(.white)
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(12)
                }
            }
        }
        .onAppear {
            isVisible = true
            setupVideo()
        }
        .onDisappear {
            isVisible = false
            cleanup()
        }
        .onReceive(playerManager.$error) { error in
            if let error = error {
                errorMessage = error.localizedDescription
                showError = true
            } else {
                showError = false
            }
        }
        .onChange(of: viewModel.isMuted) { oldValue, newValue in
            player?.isMuted = newValue
        }
        .sheet(isPresented: $showingComments) {
            CommentsView(video: .constant(video))
        }
    }
    
    private func setupVideo() {
        guard isVisible else { return }
        
        guard let url = URL(string: video.videoUrl) else {
            errorMessage = "Invalid video URL"
            showError = true
            return
        }
        
        player = playerManager.setupPlayer(for: url)
        player?.isMuted = viewModel.isMuted
        player?.play()
    }
    
    private func cleanup() {
        playerManager.cleanup()
        player = nil
    }
    
    private func retryLoading() {
        isRetrying = true
        showError = false
        cleanup()
        
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
            setupVideo()
            isRetrying = false
        }
    }
    
    private var overlayContent: some View {
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
}

// Custom video player view to handle full screen
struct CustomVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        controller.allowsPictureInPicturePlayback = true
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
    
    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: ()) {
        uiViewController.player = nil
    }
} 