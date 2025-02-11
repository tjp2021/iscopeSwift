import SwiftUI
import PhotosUI
import AVKit

// Video Details Section Component
private struct VideoDetailsSection: View {
    @Binding var title: String
    @Binding var description: String
    @Binding var selectedItem: PhotosPickerItem?
    
    var body: some View {
        Section(header: Text("Video Details")) {
            TextField("Title", text: $title)
            TextField("Description", text: $description)
            
            PhotosPicker(selection: $selectedItem,
                       matching: .videos) {
                Label("Select Video", systemImage: "video")
            }
        }
    }
}

// Upload Progress Section Component
private struct UploadProgressSection: View {
    let progress: Double
    
    var body: some View {
        Section {
            ProgressView(value: progress) {
                Text("Uploading... \(Int(progress * 100))%")
            }
        }
    }
}

struct UploadVideoView: View {
    @StateObject private var viewModel = UploadViewModel()
    @StateObject private var transcriptionViewModel = TranscriptionViewModel()
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var feedViewModel: VideoFeedViewModel
    
    @State private var title = ""
    @State private var description = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isShowingPreview = false
    @State private var previewURL: URL? = nil
    @State private var currentVideoId: String? = nil
    @State private var shouldDismiss = false
    
    var body: some View {
        NavigationView {
            Form {
                VideoDetailsSection(
                    title: $title,
                    description: $description,
                    selectedItem: $selectedItem
                )
                
                if viewModel.isUploading {
                    UploadProgressSection(progress: viewModel.uploadProgress)
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
                        cleanup()
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Upload") {
                        Task {
                            if let item = selectedItem {
                                await handleVideoSelection(item)
                            }
                        }
                    }
                    .disabled(selectedItem == nil || title.isEmpty || viewModel.isUploading)
                }
            }
            .alert("Upload Status", isPresented: $showAlert) {
                Button("OK") {
                    if shouldDismiss {
                        cleanup()
                        dismiss()
                    }
                }
            } message: {
                Text(alertMessage)
            }
            .onChange(of: selectedItem) { _, newItem in
                guard let item = newItem else { return }
                handleVideoSelection(item)
            }
        }
    }
    
    private func handleVideoSelection(_ item: PhotosPickerItem) {
        guard !title.isEmpty else {
            alertMessage = "Please enter a title first"
            showAlert = true
            selectedItem = nil
            return
        }
        
        // Start upload process
        Task {
            do {
                let (_, videoId) = try await viewModel.uploadVideo(
                    item: item,
                    title: title,
                    description: description
                )
                currentVideoId = videoId
                
                // Start transcription process
                try await transcriptionViewModel.startTranscription(
                    videoUrl: "https://iscope.s3.us-east-2.amazonaws.com/videos/\(videoId)",
                    videoId: videoId
                )
                
                // Refresh the video feed to include the new video
                await feedViewModel.refreshVideos()
                
                alertMessage = "Video uploaded successfully! Transcription in progress..."
                showAlert = true
                
                // Dismiss the upload sheet after successful upload
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    dismiss()
                }
            } catch {
                print("Transcription error: \(error)")
                alertMessage = "Error during transcription: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }
    
    private func cleanup() {
        // Just reset local state
        selectedItem = nil
        title = ""
        description = ""
        currentVideoId = nil
    }
} 
