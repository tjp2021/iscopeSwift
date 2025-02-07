import SwiftUI
import PhotosUI
import AVKit

struct UploadVideoView: View {
    @StateObject private var viewModel = UploadViewModel()
    @Environment(\.dismiss) private var dismiss
    
    @State private var title = ""
    @State private var description = ""
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isShowingPreview = false
    @State private var previewURL: URL? = nil
    
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
                    if !alertMessage.contains("Error") {
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
                await MainActor.run {
                    alertMessage = "Error loading video: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }
    
    private func handleUpload() async {
        guard let item = selectedItem else { return }
        
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw NSError(domain: "VideoLoad", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not load video data"])
            }
            
            let fileName = "\(UUID().uuidString).mp4"
            try await viewModel.uploadVideo(videoData: data, fileName: fileName, title: title, description: description)
            
            await MainActor.run {
                alertMessage = "Video uploaded successfully!"
                showAlert = true
            }
        } catch {
            await MainActor.run {
                alertMessage = "Error uploading video: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }
} 