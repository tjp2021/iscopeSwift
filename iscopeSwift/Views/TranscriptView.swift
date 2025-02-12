import SwiftUI
import AVKit

struct TranscriptView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: TranscriptViewModel
    
    init(segments: [TranscriptionSegment], player: AVPlayer?) {
        _viewModel = StateObject(wrappedValue: TranscriptViewModel(segments: segments, player: player))
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(viewModel.segments, id: \.startTime) { segment in
                        TranscriptSegmentRow(
                            segment: segment,
                            isCurrentSegment: viewModel.isCurrentSegment(segment),
                            onTap: {
                                viewModel.jumpToTime(segment.startTime)
                            }
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct TranscriptSegmentRow: View {
    let segment: TranscriptionSegment
    let isCurrentSegment: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                Text(timeString(from: segment.startTime))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(segment.text)
                    .font(.body)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isCurrentSegment ? Color.blue.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isCurrentSegment ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func timeString(from seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let seconds = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#if DEBUG
struct TranscriptView_Previews: PreviewProvider {
    static var previews: some View {
        TranscriptView(
            segments: [
                TranscriptionSegment(
                    text: "This is a test segment",
                    startTime: 0,
                    endTime: 5,
                    words: nil
                ),
                TranscriptionSegment(
                    text: "Another test segment",
                    startTime: 5,
                    endTime: 10,
                    words: nil
                )
            ],
            player: nil
        )
    }
}
#endif 