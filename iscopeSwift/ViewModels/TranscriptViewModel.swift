import Foundation

@MainActor
class TranscriptViewModel: ObservableObject {
    @Published var segments: [TranscriptionSegment]
    
    init(segments: [TranscriptionSegment]) {
        self.segments = segments
    }
} 