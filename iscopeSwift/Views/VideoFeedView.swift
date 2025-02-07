import SwiftUI
import FirebaseFirestore
import AVKit
import Combine

struct VideoFeedView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @StateObject private var viewModel = VideoFeedViewModel()
    @State private var showingUploadSheet = false
    @State private var showingMyVideosSheet = false
    @State private var showError = false
    @State private var currentIndex = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach($viewModel.videos) { $video in
                            VideoPageView(video: $video, viewModel: viewModel)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .id(video.id)
                        }
                        
                        if viewModel.isLoadingMore {
                            ProgressView()
                                .tint(.white)
                                .frame(height: 44)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .background(Color.black)
                .refreshable {
                    await viewModel.refreshVideos()
                }
                .onChange(of: currentIndex) { _, newValue in
                    if newValue == viewModel.videos.count - 2 {
                        Task {
                            await viewModel.fetchMoreVideos()
                        }
                    }
                }
                
                if viewModel.videos.isEmpty && !viewModel.isRefreshing {
                    VStack(spacing: 16) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.white)
                        Text("No videos available")
                            .font(.headline)
                            .foregroundColor(.white)
                        Button("Refresh") {
                            Task {
                                await viewModel.refreshVideos()
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }
                }
                
                if viewModel.isRefreshing {
                    ProgressView()
                        .tint(.white)
                }
                
                // Bottom toolbar with buttons
                VStack {
                    Spacer()
                    HStack(spacing: 30) {
                        Button(action: {
                            Task {
                                do {
                                    try await authViewModel.signOut()
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
                            showingMyVideosSheet = true
                        } label: {
                            VStack {
                                Image(systemName: "person.crop.rectangle.stack")
                                    .foregroundColor(.white)
                                    .font(.system(size: 24))
                                    .frame(width: 44, height: 44)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                                Text("My Videos")
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
        .sheet(isPresented: $showingMyVideosSheet) {
            MyVideosView()
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
                                .padding(.bottom, 100)
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
        .navigationBarItems(trailing: 
            Button {
                print("[VideoPlayerView] Dismiss button tapped")
                player?.pause()
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        )
        .onAppear {
            print("[VideoPlayerView] View appeared")
            if let url = URL(string: video.videoUrl) {
                print("[VideoPlayerView] Creating player with URL: \(video.videoUrl)")
                player = AVPlayer(url: url)
                player?.play()
            } else {
                print("[VideoPlayerView] ❌ Failed to create URL from: \(video.videoUrl)")
            }
        }
        .onChange(of: player) { oldValue, newValue in
            if newValue != nil {
                print("[VideoPlayerView] Player initialized for video: \(video.title)")
            }
        }
        .onDisappear {
            print("[VideoPlayerView] View disappeared - cleaning up player")
            player?.pause()
            player = nil
        }
    }
} 
