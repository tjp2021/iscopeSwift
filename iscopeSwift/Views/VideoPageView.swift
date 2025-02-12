import SwiftUI
import AVKit
import Combine
import FirebaseFirestore

// Add CaptionManager before VideoPlayerManager
class CaptionManager: ObservableObject {
    @Published var currentText: String = ""
    @Published var currentLanguage: String = "en"
    private var originalSegments: [TranscriptionSegment] = []
    private var translatedSegments: [TranscriptionSegment] = []
    
    func updateSegments(_ segments: [TranscriptionSegment]?, translations: [String: TranslationData]? = nil) {
        print("[DEBUG] Updating segments")
        print("[DEBUG] Original segments count: \(segments?.count ?? 0)")
        self.originalSegments = segments ?? []
        if let currentTranslation = translations?[currentLanguage],
           currentTranslation.status == .completed,
           let translatedSegs = currentTranslation.segments {
            print("[DEBUG] Found translation for language: \(currentLanguage)")
            print("[DEBUG] Translated segments count: \(translatedSegs.count)")
            self.translatedSegments = translatedSegs
        } else {
            print("[DEBUG] No translation found for language: \(currentLanguage)")
            self.translatedSegments = []
        }
    }
    
    func updateLanguage(_ language: String, translations: [String: TranslationData]?) {
        print("[DEBUG] Updating language to: \(language)")
        print("[DEBUG] Available translations: \(translations?.keys.joined(separator: ", ") ?? "none")")
        currentLanguage = language
        if language == "en" {
            print("[DEBUG] Setting English (original) segments")
            translatedSegments = []
        } else if let translation = translations?[language],
                  translation.status == .completed,
                  let segments = translation.segments {
            print("[DEBUG] Found \(segments.count) translated segments for \(language)")
            translatedSegments = segments
        } else {
            print("[DEBUG] No translation segments found for \(language)")
            translatedSegments = []
        }
    }
    
    func updateForTime(_ time: Double) {
        let segments = translatedSegments.isEmpty ? originalSegments : translatedSegments
        if let segment = segments.first(where: { time >= $0.startTime && time <= $0.endTime }) {
            if currentText != segment.text {
                print("[DEBUG] Updating caption text for time \(time)")
                print("[DEBUG] Using \(translatedSegments.isEmpty ? "original" : "translated") segments")
                print("[DEBUG] New text: \(segment.text)")
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
        cleanup()
        
        self.captionManager = captionManager
        
        let playerItem = AVPlayerItem(url: url)
        playerItem.automaticallyPreservesTimeOffsetFromLive = true
        let newPlayer = AVPlayer(playerItem: playerItem)
        
        // Enable background audio
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        } catch {
            self.error = error
        }
        
        // Add time observer for captions
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
            self?.captionManager?.updateForTime(time.seconds)
        }
        
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
    @StateObject private var translationViewModel = TranslationViewModel()
    @ObservedObject var captionSettings: CaptionSettingsViewModel
    @Binding var video: Video
    
    var body: some View {
        GeometryReader { geometry in
            VStack {
                // Add top safe zone
                let safeZone = geometry.size.height * 0.15 // 15% padding top and bottom
                let availableHeight = geometry.size.height - (safeZone * 2)
                let adjustedPosition = (availableHeight * captionSettings.verticalPosition) + safeZone
                
                Spacer()
                    .frame(height: adjustedPosition)
                
                // Caption text
                if !captionManager.currentText.isEmpty {
                    Text(captionManager.currentText)
                        .font(.system(size: captionSettings.fontSize, weight: .semibold))
                        .foregroundColor(captionSettings.captionColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.black.opacity(0.75))
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                        )
                        .padding(.horizontal)
                }
                
                Spacer()
                
                // Bottom controls row with language selector
                HStack {
                    // Translation loading indicator
                    if translationViewModel.isTranslating {
                        HStack {
                            ProgressView()
                                .tint(.white)
                            Text("Translating...")
                                .foregroundColor(.white)
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(8)
                    }
                    
                    Spacer()
                    
                    // Language selector
                    Menu {
                        ForEach(translationViewModel.availableLanguages, id: \.self) { language in
                            Button(action: {
                                Task {
                                    if language != "en" {
                                        do {
                                            try await translationViewModel.translate(video: video, to: language)
                                            // Fetch the updated video data from Firestore to get the new translations
                                            if let updatedVideo = try await fetchUpdatedVideo(video.id) {
                                                video = updatedVideo
                                                captionManager.updateLanguage(language, translations: updatedVideo.translations)
                                            }
                                        } catch {
                                            print("[DEBUG] Translation error: \(error.localizedDescription)")
                                        }
                                    } else {
                                        captionManager.updateLanguage(language, translations: video.translations)
                                    }
                                }
                            }) {
                                HStack {
                                    Text(languageName(for: language))
                                    if captionManager.currentLanguage == language {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "globe")
                            Text(languageName(for: captionManager.currentLanguage))
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(8)
                    }
                    .disabled(translationViewModel.isTranslating)
                }
                .padding(.horizontal)
            }
        }
    }
    
    private func languageName(for code: String) -> String {
        switch code {
        case "en": return "English"
        case "es": return "Spanish"
        case "fr": return "French"
        case "de": return "German"
        case "it": return "Italian"
        case "pt": return "Portuguese"
        case "ru": return "Russian"
        case "ja": return "Japanese"
        case "ko": return "Korean"
        case "zh": return "Chinese"
        default: return code.uppercased()
        }
    }
    
    // Add this helper function to CaptionsOverlay
    private func fetchUpdatedVideo(_ videoId: String) async throws -> Video? {
        let db = Firestore.firestore()
        let docSnapshot = try await db.collection("videos").document(videoId).getDocument()
        if var data = docSnapshot.data() {
            // Convert Firestore Timestamp to milliseconds since 1970
            if let createdAtTimestamp = data["createdAt"] as? Timestamp {
                data["createdAt"] = createdAtTimestamp.dateValue().timeIntervalSince1970 * 1000
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            let jsonData = try JSONSerialization.data(withJSONObject: data)
            return try decoder.decode(Video.self, from: jsonData)
        }
        return nil
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
    @StateObject private var captionSettings = CaptionSettingsViewModel()
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
    @State private var showingCaptionSettings = false
    @State private var showingTranscript = false
    
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
                            
                            // Transcript Button
                            if let segments = video.transcriptionSegments, !segments.isEmpty {
                                Button(action: {
                                    showingTranscript = true
                                }) {
                                    VStack {
                                        Image(systemName: "doc.text")
                                            .font(.system(size: 30))
                                            .foregroundColor(.white)
                                        Text("Transcript")
                                            .font(.caption)
                                            .foregroundColor(.white)
                                    }
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
                            
                            // Move Captions Button to bottom controls
                            
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
                
                // Add bottom controls overlay
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        
                        // Captions Button
                        Button(action: {
                            showingCaptionSettings = true
                        }) {
                            HStack {
                                Image(systemName: showCaptions ? "captions.bubble.fill" : "captions.bubble")
                                    .font(.system(size: 24))
                                Text(showCaptions ? "CC" : "CC")
                                    .font(.system(size: 16, weight: .medium))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.75))
                            .cornerRadius(8)
                            .foregroundColor(.white)
                        }
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
                }
                
                // Captions Overlay
                if showCaptions && video.transcriptionSegments?.isEmpty == false {
                    VStack {
                        Spacer()
                        CaptionsOverlay(
                            captionManager: captionManager,
                            captionSettings: captionSettings,
                            video: $video
                        )
                            .padding(.bottom, 100)
                    }
                }
            }
        }
        .background(Color.black)
        .onAppear {
            isVisible = true
            captionManager.updateSegments(video.transcriptionSegments, translations: video.translations)
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
            print("[DEBUG] Mute state changed to: \(isMuted)")
            player?.isMuted = isMuted
        }
        .onChange(of: isVisible) { _, visible in
            if visible {
                print("[DEBUG] Video became visible, current mute state: \(viewModel.isMuted)")
                setupVideo()
            } else {
                cleanup()
            }
        }
        .onChange(of: video.transcriptionSegments) { _, newSegments in
            captionManager.updateSegments(newSegments, translations: video.translations)
        }
        .onChange(of: video.translations) { _, newTranslations in
            captionManager.updateSegments(video.transcriptionSegments, translations: newTranslations)
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
        .sheet(isPresented: $showingCaptionSettings) {
            CaptionSettingsView(showCaptions: $showCaptions, viewModel: captionSettings)
        }
        .sheet(isPresented: $showingTranscript) {
            if let segments = video.transcriptionSegments {
                TranscriptView(segments: segments, player: player)
            }
        }
    }
    
    private func setupVideo() {
        guard isVisible else { return }
        
        cleanup()
        
        print("[DEBUG] Setting up video - URL: \(video.url)")
        
        guard !video.url.isEmpty else {
            print("[ERROR] Video URL is empty for video ID: \(video.id)")
            errorMessage = "Video URL is empty"
            showError = true
            return
        }
        
        guard let url = URL(string: video.url) else {
            print("[ERROR] Invalid video URL format: \(video.url)")
            errorMessage = "Invalid video URL"
            showError = true
            return
        }
        
        guard viewModel.isOnline else {
            print("[ERROR] No network connection while trying to play video: \(video.url)")
            errorMessage = "No internet connection. Please check your network settings."
            showError = true
            return
        }
        
        DispatchQueue.main.async { [self] in
            print("[DEBUG] Creating player for URL: \(url)")
            player = playerManager.setupPlayer(for: url, captionManager: captionManager)
            player?.isMuted = viewModel.isMuted
            print("[DEBUG] Setting initial mute state: \(viewModel.isMuted)")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                print("[DEBUG] Starting playback for URL: \(url)")
                player?.play()
            }
        }
    }
    
    private func cleanup() {
        print("[DEBUG] Cleaning up video player")
        player?.pause()
        player = nil
        playerManager.cleanup()
    }
    
    private func retryVideo() {
        print("[DEBUG] Retrying video playback")
        isRetrying = true
        errorMessage = nil
        showError = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
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
        controller.showsPlaybackControls = true
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = true
        
        player.actionAtItemEnd = .none
        
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