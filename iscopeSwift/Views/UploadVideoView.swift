import SwiftUI
import PhotosUI
import AVKit

struct UploadVideoView: View {
    @StateObject private var viewModel = UploadViewModel()
    @StateObject private var transcriptionViewModel = TranscriptionViewModel()
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var feedViewModel: VideoFeedViewModel
    
    @State private var title = ""
    @State private var description = ""
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isShowingPreview = false
    @State private var previewURL: URL? = nil
    @State private var currentVideoId: String? = nil
    @State private var shouldDismiss = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Video Details")) {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description)
                }
                
                Section(header: Text("Video Selection")) {
                    PhotosPicker(selection: $selectedItem, matching: .videos) {
                        HStack {
                            Image(systemName: "video.fill")
                            Text(selectedItem == nil ? "Select Video" : "Change Video")
                        }
                    }
                    
                    if let previewURL = previewURL {
                        Button("Preview Video") {
                            isShowingPreview = true
                        }
                        .sheet(isPresented: $isShowingPreview) {
                            VideoPlayer(player: AVPlayer(url: previewURL))
                                .ignoresSafeArea()
                        }
                    }
                }
                
                if viewModel.isUploading {
                    Section {
                        ProgressView("Uploading...", value: viewModel.uploadProgress, total: 1.0)
                    }
                }
                
                if let videoId = currentVideoId, transcriptionViewModel.isTranscribing {
                    Section {
                        TranscriptionProgressView(viewModel: transcriptionViewModel, videoId: videoId)
                    }
                }
            }
            .navigationTitle("Upload Video")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Upload") {
                        Task {
                            await handleUpload()
                        }
                    }
                    .disabled(selectedItem == nil || title.isEmpty || viewModel.isUploading)
                }
            }
            .alert("Upload Status", isPresented: $showAlert) {
                Button("OK") {
                    if shouldDismiss {
                        dismiss()
                    }
                }
            } message: {
                Text(alertMessage)
            }
            .onChange(of: selectedItem) { oldValue, newValue in
                handleSelectedVideo()
            }
        }
        .onDisappear {
            // Cleanup TranscriptionViewModel
            transcriptionViewModel.cleanupResources()
        }
    }
    
    private func handleSelectedVideo() {
        guard let item = selectedItem else { return }
        
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw NSError(domain: "VideoLoad", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not load video data"])
                }
                
                // Create a temporary file for preview
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
                try data.write(to: tempURL)
                
                await MainActor.run {
                    self.previewURL = tempURL
                }
            } catch {
                print("Preview error: \(error.localizedDescription)")
                await MainActor.run {
                    alertMessage = "Error loading video preview: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }
    
    private func handleUpload() async {
        guard let item = selectedItem else { return }
        
        do {
            let (videoUrl, videoId) = try await viewModel.uploadVideo(item: item, title: title, description: description)
            currentVideoId = videoId
            
            // Start transcription process
            Task {
                do {
                    try await transcriptionViewModel.startTranscription(videoUrl: videoUrl, videoId: videoId)
                } catch {
                    print("Transcription error: \(error)")
                    alertMessage = "Error during transcription: \(error.localizedDescription)"
                    showAlert = true
                    return
                }
            }
            
            // Refresh the feed after successful upload
            await feedViewModel.refreshVideos()
            
            alertMessage = "Video uploaded successfully! Transcription in progress..."
            showAlert = true
            shouldDismiss = true
            
        } catch {
            alertMessage = "Error uploading video: \(error.localizedDescription)"
            showAlert = true
        }
    }
} 