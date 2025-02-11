import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers

// Import network response types
@MainActor
class UploadViewModel: ObservableObject {
    private let db = Firestore.firestore()
    @Published var isUploading = false
    @Published var uploadProgress: Double = 0
    
    // Single source of truth for server URL
    #if targetEnvironment(simulator)
    private let serverBaseUrl = "http://127.0.0.1:3001"  // Use IP instead of localhost for simulator
    #else
    private let serverBaseUrl = "http://localhost:3001"   // Use localhost for real device
    #endif
    
    // Step 1: Ask our server for a pre-signed URL
    func fetchPresignedUrl(fileName: String) async throws -> (uploadURL: String, videoKey: String) {
        let serverUrl = "\(serverBaseUrl)/generate-presigned-url"
        
        print("🔄 Attempting server connection to: \(serverUrl)")
        
        do {
            guard let url = URL(string: serverUrl) else {
                print("❌ Invalid URL: \(serverUrl)")
                throw URLError(.badURL)
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body = ["fileName": fileName]
            let jsonData = try JSONSerialization.data(withJSONObject: body)
            request.httpBody = jsonData
            
            print("📤 Request body: \(String(data: jsonData, encoding: .utf8) ?? "nil")")
            
            print("📤 Sending request to server...")
            let (data, response) = try await URLSession.shared.data(for: request)
            print("📥 Received response from server")
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid response type")
                throw URLError(.badServerResponse)
            }
            
            print("📡 Server responded with status: \(httpResponse.statusCode)")
            print("📡 Response headers: \(httpResponse.allHeaderFields)")
            
            // Print raw response data for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                print("📥 Raw response: \(responseString)")
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                if let errorText = String(data: data, encoding: .utf8) {
                    print("❌ Server error response: \(errorText)")
                }
                throw URLError(.badServerResponse)
            }
            
            // Define the expected response structure
            struct PresignedUrlResponse: Codable {
                let uploadURL: String
                let videoKey: String
                
                enum CodingKeys: String, CodingKey {
                    case uploadURL = "uploadURL"
                    case videoKey = "videoKey"
                }
            }
            
            do {
                let decoder = JSONDecoder()
                let json = try decoder.decode(PresignedUrlResponse.self, from: data)
                print("✅ Successfully decoded server response: \(json)")
                return (json.uploadURL, json.videoKey)
            } catch {
                print("❌ JSON Decoding error: \(error)")
                print("❌ Failed to decode data: \(String(data: data, encoding: .utf8) ?? "nil")")
                throw error
            }
        } catch {
            print("❌ Error in fetchPresignedUrl: \(error.localizedDescription)")
            if let urlError = error as? URLError {
                print("🔍 URL Error Code: \(urlError.code.rawValue)")
                print("🔍 URL Error Description: \(urlError.localizedDescription)")
            } else if let decodingError = error as? DecodingError {
                print("🔍 Decoding Error: \(decodingError)")
            }
            throw error
        }
    }
    
    // Step 2: Upload to S3 using the pre-signed URL
    func uploadToS3(presignedUrl: String, videoData: Data) async throws -> Bool {
        guard let url = URL(string: presignedUrl) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
        
        // Create upload task with progress tracking
        return try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.uploadTask(with: request, from: videoData) { _, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                
                continuation.resume(returning: true)
            }
            
            // Track upload progress
            let observation = task.progress.observe(\.fractionCompleted) { progress, _ in
                Task { @MainActor in
                    // Update progress between 30% and 70%
                    self.uploadProgress = 0.3 + (progress.fractionCompleted * 0.4)
                }
            }
            
            // Start the upload
            task.resume()
            
            // Store observation to prevent deallocation
            objc_setAssociatedObject(task, "progressObservation", observation, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    // Step 3: Store video metadata in Firestore
    func storeVideoMetadata(videoKey: String, title: String, description: String) async throws -> String {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let videoId = UUID().uuidString
        // Updated S3 bucket URL with correct region and bucket name
        let s3URL = "https://iscope.s3.us-east-2.amazonaws.com/\(videoKey)"
        
        let video = Video(
            id: videoId,
            title: title,
            description: description,
            videoUrl: s3URL,
            creatorId: userId,
            createdAt: Date(),
            transcriptionStatus: "pending",  // Set initial status
            transcriptionText: nil          // No text yet
        )
        
        try db.collection("videos").document(videoId).setData(from: video)
        return videoId
    }
    
    // Step 4: Notify server to start transcription
    private func notifyTranscriptionServer(videoUrl: String, videoId: String) async throws {
        let serverUrl = "\(serverBaseUrl)/start-transcription"
        
        print("Starting transcription at: \(serverUrl)")
        
        guard let url = URL(string: serverUrl) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "videoUrl": videoUrl,
            "videoId": videoId
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            if let errorText = String(data: data, encoding: .utf8) {
                print("❌ Server error response: \(errorText)")
            }
            throw URLError(.badServerResponse)
        }
        
        // Decode and handle the response
        let decoder = JSONDecoder()
        let result = try decoder.decode(TranscriptionResponse.self, from: data)
        print("✅ Transcription started: \(result.status)")
    }
    
    // Response model for transcription
    private struct TranscriptionResponse: Codable {
        let jobId: String
        let status: String
        let transcriptUrl: String
        let text: String
    }
    
    // Main upload function that coordinates all steps
    func uploadVideo(item: PhotosPickerItem, title: String, description: String) async throws -> (videoUrl: String, videoId: String) {
        isUploading = true
        uploadProgress = 0
        
        do {
            print("Starting video upload process...")
            
            // Load video data directly from PhotosPickerItem
            print("Loading video data...")
            guard let videoData = try await item.loadTransferable(type: Data.self) else {
                print("❌ Failed to load video data from PhotosPickerItem")
                throw NSError(domain: "Upload", code: -1, 
                    userInfo: [NSLocalizedDescriptionKey: "Could not load video data"])
            }
            
            print("✅ Successfully loaded video data")
            print("Video data size: \(videoData.count) bytes")
            
            // Create temporary files with unique names
            let temporaryDirectory = FileManager.default.temporaryDirectory
            let inputFile = temporaryDirectory.appendingPathComponent("input-\(UUID().uuidString).mp4")
            let outputFile = temporaryDirectory.appendingPathComponent("output-\(UUID().uuidString).mp4")
            
            // Write the video data to the temporary input file
            print("Writing video to temporary file...")
            try videoData.write(to: inputFile)
            
            // Create AVAsset from the temporary file
            let asset = AVAsset(url: inputFile)
            
            // Start video data access in the background
            print("Loading video asset...")
            _ = try await asset.load(.isPlayable)
            
            // Export the video with compression
            print("Exporting video with compression...")
            let exporter = try await exportVideoToMP4(asset: asset, outputURL: outputFile)
            
            // Read the compressed video data
            let compressedVideoData = try Data(contentsOf: outputFile)
            print("Compressed video data size: \(compressedVideoData.count) bytes")
            
            // Clean up temporary files
            try? FileManager.default.removeItem(at: inputFile)
            try? FileManager.default.removeItem(at: outputFile)
            
            let fileName = "\(UUID().uuidString).mp4"
            
            // Step 1: Get pre-signed URL
            print("Fetching presigned URL...")
            let (presignedUrl, videoKey) = try await fetchPresignedUrl(fileName: fileName)
            print("Got presigned URL: \(presignedUrl)")
            
            uploadProgress = 0.3
            
            // Step 2: Upload to S3
            print("Uploading to S3...")
            let uploadSuccess = try await uploadToS3(presignedUrl: presignedUrl, videoData: compressedVideoData)
            guard uploadSuccess else {
                print("Failed to upload to S3")
                throw NSError(domain: "Upload", code: -1, 
                    userInfo: [NSLocalizedDescriptionKey: "Failed to upload to S3"])
            }
            print("Successfully uploaded to S3")
            
            uploadProgress = 0.7
            
            // Step 3: Store metadata
            print("Storing metadata...")
            let videoId = try await storeVideoMetadata(videoKey: videoKey, title: title, description: description)
            print("Stored metadata with videoId: \(videoId)")
            
            uploadProgress = 0.9
            
            // Step 4: Notify server to start transcription
            print("Notifying server for transcription...")
            let s3URL = "https://iscope.s3.us-east-2.amazonaws.com/\(videoKey)"
            try await notifyTranscriptionServer(videoUrl: s3URL, videoId: videoId)
            print("Transcription process started")
            
            uploadProgress = 1.0
            isUploading = false
            
            return (videoUrl: s3URL, videoId: videoId)
        } catch {
            print("Upload error: \(error.localizedDescription)")
            print("Error details: \(String(describing: error))")
            isUploading = false
            uploadProgress = 0
            throw error
        }
    }
    
    // Helper function to export video to MP4 format with compression
    private func exportVideoToMP4(asset: AVAsset, outputURL: URL) async throws -> AVAssetExportSession {
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetMediumQuality) else {
            throw NSError(domain: "Export", code: -1, 
                userInfo: [NSLocalizedDescriptionKey: "Could not create export session"])
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        print("Starting video export...")
        await exportSession.export()
        print("Export completed with status: \(exportSession.status.rawValue)")
        
        if let error = exportSession.error {
            print("Export error: \(error.localizedDescription)")
            throw error
        }
        
        return exportSession
    }
    
    // Test server connectivity
    func testServerConnection() async throws {
        let testUrl = "\(serverBaseUrl)/test"
        print("🔄 Testing server connection at: \(testUrl)")
        
        guard let url = URL(string: testUrl) else {
            print("❌ Invalid test URL")
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Invalid response type")
                throw URLError(.badServerResponse)
            }
            
            print("📡 Server test response status: \(httpResponse.statusCode)")
            
            if let responseText = String(data: data, encoding: .utf8) {
                print("📥 Server response: \(responseText)")
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }
        } catch {
            print("❌ Server test failed: \(error.localizedDescription)")
            throw error
        }
    }
} 