import SwiftUI

struct TranscriptionTestView: View {
    @StateObject private var viewModel = TranscriptionViewModel()
    @State private var videoUrl: String = ""
    @State private var showingUrlInput = false
    
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
            
            VStack(spacing: 16) {
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
                
                Button(action: {
                    showingUrlInput = true
                }) {
                    Text("Test Real Video")
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .disabled(viewModel.isTranscribing)
            }
        }
        .padding()
        .sheet(isPresented: $showingUrlInput) {
            NavigationStack {
                Form {
                    Section(header: Text("Video URL")) {
                        TextField("Enter S3 video URL", text: $videoUrl)
                            .autocapitalization(.none)
                            .keyboardType(.URL)
                    }
                }
                .navigationTitle("Enter Video URL")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showingUrlInput = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Start") {
                            showingUrlInput = false
                            Task {
                                do {
                                    try await viewModel.testRealTranscription(videoUrl: videoUrl)
                                } catch {
                                    print("Real test failed:", error)
                                }
                            }
                        }
                        .disabled(videoUrl.isEmpty)
                    }
                }
            }
        }
    }
} 