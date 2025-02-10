import SwiftUI

struct TranscriptionView: View {
    let video: Video
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let transcriptionStatus = video.transcriptionStatus {
                    switch transcriptionStatus {
                    case "completed":
                        if let transcriptionText = video.transcriptionText {
                            Text(transcriptionText)
                                .font(.body)
                                .padding()
                        } else {
                            Text("No transcription available")
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    case "pending":
                        HStack {
                            ProgressView()
                            Text("Transcription in progress...")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                    default:
                        Text("Transcription failed")
                            .foregroundColor(.red)
                            .padding()
                    }
                } else {
                    Text("No transcription available")
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
        }
        .navigationTitle("Transcription")
    }
} 