import SwiftUI

struct TranscriptionTestView: View {
    @StateObject private var viewModel = TranscriptionViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Transcription Test")
                .font(.title)
            
            if viewModel.isTranscribing {
                ProgressView()
                    .progressViewStyle(.circular)
            }
            
            if let status = viewModel.transcriptionStatus {
                Text(status)
                    .multilineTextAlignment(.center)
                    .padding()
            }
            
            if let text = viewModel.transcriptionText {
                VStack(alignment: .leading) {
                    Text("Transcribed Text:")
                        .font(.headline)
                    ScrollView {
                        Text(text)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
                .padding()
            }
            
            if let error = viewModel.error {
                Text("Error: \(error.localizedDescription)")
                    .foregroundColor(.red)
                    .padding()
            }
            
            Button(action: {
                Task {
                    do {
                        try await viewModel.testTranscription()
                    } catch {
                        print("Test failed:", error)
                    }
                }
            }) {
                Text("Start Test Transcription")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(viewModel.isTranscribing)
        }
        .padding()
    }
} 