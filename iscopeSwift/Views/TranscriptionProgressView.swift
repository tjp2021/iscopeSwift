import SwiftUI

struct TranscriptionProgressView: View {
    @ObservedObject var viewModel: TranscriptionViewModel
    let videoId: String
    
    var body: some View {
        VStack(spacing: 20) {
            if viewModel.isTranscribing {
                ProgressView(value: viewModel.transcriptionProgress) {
                    Text(viewModel.transcriptionStatus ?? "Processing...")
                        .font(.headline)
                } currentValueLabel: {
                    Text("\(Int(viewModel.transcriptionProgress * 100))%")
                        .font(.subheadline)
                }
                .progressViewStyle(.linear)
                .padding()
                
                if let error = viewModel.error {
                    Text(error.localizedDescription)
                        .foregroundColor(.red)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .padding()
                }
                
                if viewModel.transcriptionProgress == 1.0 {
                    Text("✅ Transcription completed!")
                        .font(.headline)
                        .foregroundColor(.green)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 5)
    }
} 