import SwiftUI

struct TranscriptView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: TranscriptViewModel
    
    init(segments: [TranscriptionSegment]) {
        _viewModel = StateObject(wrappedValue: TranscriptViewModel(segments: segments))
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(viewModel.segments, id: \.startTime) { segment in
                        TranscriptSegmentRow(segment: segment)
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(timeString(from: segment.startTime))
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(segment.text)
                .font(.body)
        }
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
        TranscriptView(segments: [
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
        ])
    }
}
#endif 