import SwiftUI
import PhotosUI
import AVKit

// Video Details Section Component
private struct VideoDetailsSection: View {
    @Binding var title: String
    @Binding var description: String
    @Binding var selectedItem: PhotosPickerItem?
    @State private var isPickerPresented = false
    
    var body: some View {
        VStack(spacing: 24) {
            if selectedItem == nil {
                PhotosPicker(selection: $selectedItem,
                           matching: .videos) {
                    VStack(spacing: 16) {
                        Image(systemName: "video.badge.plus")
                            .font(.system(size: 48))
                            .foregroundColor(.blue)
                        
                        Text("Select Video")
                            .font(.headline)
                            .foregroundColor(.blue)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(style: StrokeStyle(lineWidth: 2, dash: [8]))
                            .foregroundColor(Color.blue.opacity(0.3))
                    )
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(12)
                }
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                    Text("Video Selected")
                        .font(.headline)
                    Spacer()
                    Button(action: { selectedItem = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.title2)
                    }
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Title")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    TextField("Enter video title", text: $title)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Description")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    TextField("Enter video description (optional)", text: $description)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
            }
        }
        .padding()
    }
}

// Upload Progress Section Component
private struct UploadProgressSection: View {
    let status: String
    
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.blue)
            
            Text(status)
                .font(.headline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
        .padding(.horizontal)
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
            ScrollView {
                VStack(spacing: 24) {
                    VideoDetailsSection(
                        title: $title,
                        description: $description,
                        selectedItem: $selectedItem
                    )
                    
                    if viewModel.isUploading {
                        UploadProgressSection(status: viewModel.uploadStatus)
                    }
                    
                    if let videoId = currentVideoId, transcriptionViewModel.isTranscribing {
                        TranscriptionProgressView(viewModel: transcriptionViewModel, videoId: videoId)
                            .padding()
                            .background(Color.blue.opacity(0.05))
                            .cornerRadius(12)
                            .padding(.horizontal)
                    }
                }
            }
            .navigationTitle("Upload Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        cleanup()
                        dismiss()
                    }
                    .foregroundColor(.secondary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task {
                            if let item = selectedItem {
                                await handleVideoSelection(item)
                            }
                        }
                    }) {
                        Text("Upload")
                            .fontWeight(.semibold)
                    }
                    .disabled(selectedItem == nil || title.isEmpty || viewModel.isUploading)
                    .opacity(selectedItem == nil || title.isEmpty || viewModel.isUploading ? 0.5 : 1)
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
