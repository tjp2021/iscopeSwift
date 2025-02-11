import SwiftUI
import AVKit
import Combine

// Add CaptionManager before VideoPlayerManager
class CaptionManager: ObservableObject {
    @Published var currentText: String = ""
    private var segments: [TranscriptionSegment] = []
    
    func updateSegments(_ segments: [TranscriptionSegment]?) {
        print("[CaptionManager] Updating segments: \(segments?.count ?? 0) segments")
        self.segments = segments ?? []
    }
    
    func updateForTime(_ time: Double) {
        // Find the segment that corresponds to the current time
        if let segment = segments.first(where: { time >= $0.startTime && time <= $0.endTime }) {
            if currentText != segment.text {
                print("[CaptionManager] Updating caption at time \(time): \(segment.text)")
                currentText = segment.text
            }
        } else {
            if !currentText.isEmpty {
                currentText = ""
            }
        }
    }
}

// Player Manager class to handle KVO
class VideoPlayerManager: NSObject, ObservableObject {
    @Published var isLoading = true
    @Published var error: Error?
    @Published private(set) var currentTime: Double = 0
    
    private var player: AVPlayer?
    private var playerItemContext = 0
    private var timeObserverToken: Any?
    private var cancellables = Set<AnyCancellable>()
    private var captionManager: CaptionManager?
    
    func setupPlayer(for url: URL, captionManager: CaptionManager) -> AVPlayer {
        print("[VideoPlayerManager] Starting setup for URL: \(url)")
        cleanup()
        
        self.captionManager = captionManager
        
        let playerItem = AVPlayerItem(url: url)
        print("[VideoPlayerManager] Created AVPlayerItem")
        playerItem.automaticallyPreservesTimeOffsetFromLive = true
        let newPlayer = AVPlayer(playerItem: playerItem)
        print("[VideoPlayerManager] Created AVPlayer")
        
        // Enable background audio
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            print("[VideoPlayerManager] Audio session setup successful")
        } catch {
            print("[VideoPlayerManager] Audio session setup failed: \(error)")
            self.error = error
        }
        
        // Add time observer for captions
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
            self?.captionManager?.updateForTime(time.seconds)
        }
        print("[VideoPlayerManager] Added periodic time observer")
        
        playerItem.addObserver(
            self,
            forKeyPath: #keyPath(AVPlayerItem.status),
            options: [.old, .new],
            context: &playerItemContext
        )
        print("[VideoPlayerManager] Added status observer")
        
        // Add error observer
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] notification in
            if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                print("[VideoPlayerManager] Failed to play to end: \(error)")
                self?.error = error
            }
        }
        print("[VideoPlayerManager] Added error observer")
        
        // Add playback ended observer
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            print("[VideoPlayerManager] Playback reached end, looping")
            newPlayer.seek(to: .zero)
            newPlayer.play()
        }
        print("[VideoPlayerManager] Added end of playback observer")
        
        self.player = newPlayer
        print("[VideoPlayerManager] Setup complete")
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
                print("[VideoPlayerManager] Player status changed to: \(status.rawValue)")
            } else {
                status = .unknown
                print("[VideoPlayerManager] Player status unknown (no status number)")
            }
            
            DispatchQueue.main.async { [weak self] in
                switch status {
                case .readyToPlay:
                    print("[VideoPlayerManager] Player is ready to play")
                    self?.isLoading = false
                    self?.error = nil
                    self?.player?.play()
                case .failed:
                    if let error = self?.player?.currentItem?.error {
                        print("[VideoPlayerManager] Player failed with error: \(error)")
                        self?.error = error
                    }
                    self?.isLoading = false
                case .unknown:
                    print("[VideoPlayerManager] Player status is unknown")
                    self?.isLoading = true
                    self?.error = nil
                @unknown default:
                    print("[VideoPlayerManager] Player status is in unexpected state")
                    self?.isLoading = false
                    self?.error = nil
                }
            }
        }
    }
    
    func cleanup() {
        print("[VideoPlayerManager] Starting cleanup")
        if let player = player {
            player.pause()
            print("[VideoPlayerManager] Player paused")
            
            if let timeObserverToken = timeObserverToken {
                player.removeTimeObserver(timeObserverToken)
                self.timeObserverToken = nil
                print("[VideoPlayerManager] Removed time observer")
            }
            
            player.currentItem?.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.status))
            NotificationCenter.default.removeObserver(self)
            print("[VideoPlayerManager] Removed observers")
        }
        
        player = nil
        isLoading = true
        error = nil
        currentTime = 0
        print("[VideoPlayerManager] Cleanup completed")
    }
    
    deinit {
        print("[VideoPlayerManager] Deinitializing")
        cleanup()
    }
}

#if DEBUG
// Debug overlay component
private struct DebugOverlay: View {
    let showCaptions: Bool
    let transcriptionStatus: String?
    let transcriptionText: String?
    
    var body: some View {
        VStack {
            Text("Show Captions: \(showCaptions ? "true" : "false")")
                .foregroundColor(.white)
            Text("Status: \(transcriptionStatus ?? "nil")")
                .foregroundColor(.white)
            if let text = transcriptionText {
                Text("Has Text: true (\(text.prefix(20))...)")
                    .foregroundColor(.white)
            } else {
                Text("Has Text: false")
                    .foregroundColor(.white)
            }
        }
        .padding()
        .background(Color.black.opacity(0.5))
    }
}
#endif

// Captions overlay component
private struct CaptionsOverlay: View {
    @ObservedObject var captionManager: CaptionManager
    
    var body: some View {
        if !captionManager.currentText.isEmpty {
            Text(captionManager.currentText)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.7))
                .cornerRadius(8)
                .padding(.horizontal)
                .padding(.bottom, 120)
                .transition(.opacity)
        }
    }
}

// Loading overlay component
private struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black
            ProgressView()
                .tint(.white)
        }
    }
}

// Error overlay component
private struct ErrorOverlay: View {
    let errorMessage: String?
    let isRetrying: Bool
    let retryAction: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.white)
            Text(errorMessage ?? "Failed to load video")
                .font(.headline)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            if !isRetrying {
                Button("Retry", action: retryAction)
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

// Control overlay component
private struct VideoControlsOverlay: View {
    let video: Video
    let showingComments: Bool
    let showCaptions: Bool
    let onCommentsToggle: () -> Void
    let onCaptionsToggle: () -> Void
    
    var body: some View {
        HStack(spacing: 20) {
            Button(action: onCommentsToggle) {
                VStack {
                    Image(systemName: "bubble.right")
                        .font(.system(size: 24))
                    Text("\(video.commentCount)")
                        .font(.caption)
                }
            }
            
            Button(action: onCaptionsToggle) {
                Image(systemName: showCaptions ? "captions.bubble.fill" : "captions.bubble")
                    .font(.system(size: 24))
            }
        }
        .foregroundColor(.white)
        .padding()
        .background(Color.black.opacity(0.5))
        .cornerRadius(12)
    }
}

struct VideoPageView: View {
    @Binding var video: Video
    @ObservedObject var viewModel: VideoFeedViewModel
    @StateObject private var playerManager = VideoPlayerManager()
    @StateObject private var captionManager = CaptionManager()
    @StateObject private var engagementViewModel = VideoEngagementViewModel()
    @State private var player: AVPlayer?
    @State private var showError = false
    @State private var errorMessage: String?
    @State private var isRetrying = false
    @State private var isVisible = false
    @State private var showingComments = false
    @State private var showingTranscription = false
    @State private var showCaptions = true
    @State private var showingUploadSheet = false
    @State private var showingProfile = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let player = player {
                    CustomVideoPlayer(player: player)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .edgesIgnoringSafeArea(.all)
                } else if playerManager.isLoading {
                    LoadingOverlay()
                } else if showError {
                    ErrorOverlay(
                        errorMessage: errorMessage,
                        isRetrying: isRetrying,
                        retryAction: retryVideo
                    )
                }
                
                // Engagement Side Menu
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 20) {
                            Spacer() // Add top spacer for vertical centering
                            
                            // Like Button
                            Button(action: {
                                Task {
                                    await engagementViewModel.handleLikeAction(for: video)
                                }
                            }) {
                                VStack {
                                    Image(systemName: engagementViewModel.isVideoLiked(video) ? "heart.fill" : "heart")
                                        .font(.system(size: 30))
                                        .foregroundColor(engagementViewModel.isVideoLiked(video) ? .red : .white)
                                    Text("\(video.likeCount)")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                            }
                            
                            // Comments Button
                            Button(action: {
                                showingComments.toggle()
                            }) {
                                VStack {
                                    Image(systemName: "bubble.right")
                                        .font(.system(size: 30))
                                        .foregroundColor(.white)
                                    Text("\(video.commentCount)")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                            }
                            
                            // Mute Button
                            Button(action: {
                                viewModel.isMuted.toggle()
                            }) {
                                Image(systemName: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(.white)
                            }
                            
                            // Captions Button
                            Button(action: {
                                showCaptions.toggle()
                            }) {
                                Image(systemName: showCaptions ? "captions.bubble.fill" : "captions.bubble")
                                    .font(.system(size: 30))
                                    .foregroundColor(.white)
                            }
                            
                            // Add Video Button
                            Button(action: {
                                showingUploadSheet.toggle()
                            }) {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 30))
                                    .foregroundColor(.white)
                            }
                            
                            // Profile Button
                            Button {
                                showingProfile = true
                            } label: {
                                Image(systemName: "person")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                            }
                            
                            Spacer() // Add bottom spacer for vertical centering
                        }
                        .padding(.trailing, 20)
                    }
                }
                
                // Captions Overlay
                if showCaptions {
                    VStack {
                        Spacer()
                        CaptionsOverlay(captionManager: captionManager)
                            .padding(.bottom, 100)
                    }
                }
                
                #if DEBUG
                if isVisible {
                    DebugOverlay(
                        showCaptions: showCaptions,
                        transcriptionStatus: video.transcriptionStatus,
                        transcriptionText: video.transcriptionText
                    )
                }
                #endif
            }
        }
        .background(Color.black)
        .onAppear {
            print("[VideoPageView] View appearing")
            print("[VideoPageView] Video data: id=\(video.id), url=\(video.url)")
            isVisible = true
            captionManager.updateSegments(video.transcriptionSegments)
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
        .onChange(of: viewModel.isMuted) { _, isMuted in
            player?.isMuted = isMuted
        }
        .onChange(of: video.transcriptionSegments) { _, newSegments in
            print("[VideoPageView] Transcription segments updated")
            captionManager.updateSegments(newSegments)
        }
        .sheet(isPresented: $showingComments) {
            CommentsView(video: $video)
        }
        .sheet(isPresented: $showingUploadSheet) {
            UploadVideoView()
        }
        .sheet(isPresented: $showingProfile) {
            MyVideosView()
        }
    }
    
    private func setupVideo() {
        print("[VideoPageView] Starting setupVideo() - isVisible: \(isVisible)")
        print("[VideoPageView] Video object: id=\(video.id), title=\(video.title), url=\(video.url)")
        
        guard isVisible else {
            print("[VideoPageView] Setup aborted - view not visible")
            return
        }
        
        if video.url.isEmpty {
            print("[VideoPageView] Setup failed - Empty URL string")
            errorMessage = "Video URL is empty"
            showError = true
            return
        }
        
        guard let url = URL(string: video.url) else {
            print("[VideoPageView] Setup failed - Invalid URL: \(video.url)")
            errorMessage = "Invalid video URL"
            showError = true
            return
        }
        print("[VideoPageView] Video URL validated: \(url)")
        
        // Check network connectivity
        if !viewModel.isOnline {
            print("[VideoPageView] Setup failed - No network connection")
            errorMessage = "No internet connection. Please check your network settings."
            showError = true
            return
        }
        print("[VideoPageView] Network connectivity confirmed")
        
        // Use VideoPlayerManager to set up the player
        print("[VideoPageView] Setting up player with VideoPlayerManager")
        player = playerManager.setupPlayer(for: url, captionManager: captionManager)
        player?.isMuted = viewModel.isMuted
        print("[VideoPageView] Player setup complete - isMuted: \(viewModel.isMuted)")
        player?.play()
        print("[VideoPageView] Player.play() called")
    }
    
    private func cleanup() {
        print("[VideoPageView] Starting cleanup")
        player?.pause()
        player = nil
        playerManager.cleanup()
        print("[VideoPageView] Cleanup completed")
    }
    
    private func retryVideo() {
        print("[VideoPageView] Starting video retry")
        isRetrying = true
        errorMessage = nil
        showError = false
        
        // Add slight delay to show retry animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("[VideoPageView] Executing retry after delay")
            isRetrying = false
            setupVideo()
        }
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