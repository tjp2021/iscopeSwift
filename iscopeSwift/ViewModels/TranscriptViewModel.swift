import Foundation
import AVKit

@MainActor
class TranscriptViewModel: ObservableObject {
    @Published var segments: [TranscriptionSegment]
    @Published var currentTime: Double = 0
    
    private weak var player: AVPlayer?
    private var timeObserverToken: Any?
    
    init(segments: [TranscriptionSegment], player: AVPlayer? = nil) {
        self.segments = segments
        self.player = player
        setupTimeObserver()
    }
    
    private func setupTimeObserver() {
        guard let player = player else { return }
        
        // Observe time updates every 0.1 seconds
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
        }
    }
    
    func jumpToTime(_ time: Double) {
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
    }
    
    func isCurrentSegment(_ segment: TranscriptionSegment) -> Bool {
        return currentTime >= segment.startTime && currentTime <= segment.endTime
    }
    
    deinit {
        if let player = player, let timeObserverToken = timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
        }
    }
} 