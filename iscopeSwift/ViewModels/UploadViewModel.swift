import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import AVFoundation

// Import network response types
@MainActor
class UploadViewModel: ObservableObject {
    private let db = Firestore.firestore()
    @Published var isUploading = false
    @Published var uploadProgress: Double = 0
    
    // Step 1: Ask our server for a pre-signed URL
    func fetchPresignedUrl(fileName: String) async throws -> (uploadURL: String, videoKey: String) {
        let serverUrl = "http://localhost:3000/generate-presigned-url"
        
        guard let url = URL(string: serverUrl) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["fileName": fileName]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        let json = try JSONDecoder().decode(PresignedUrlResponse.self, from: data)
        return (json.uploadURL, json.videoKey)
    }
    
    // Step 2: Upload to S3 using the pre-signed URL
    func uploadToS3(presignedUrl: String, videoData: Data) async throws -> Bool {
        guard let url = URL(string: presignedUrl) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
        
        let (_, response) = try await URLSession.shared.upload(for: request, from: videoData)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        return true
    }
    
    // Step 3: Store video metadata in Firestore
    func storeVideoMetadata(videoKey: String, title: String, description: String) async throws {
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
            createdAt: Date()
        )
        
        try db.collection("videos").document(videoId).setData(from: video)
    }
    
    // Main upload function that coordinates all steps
    func uploadVideo(videoData: Data, fileName: String, title: String, description: String) async throws {
        isUploading = true
        uploadProgress = 0
        
        do {
            // Step 1: Get pre-signed URL
            let (presignedUrl, videoKey) = try await fetchPresignedUrl(fileName: fileName)
            
            uploadProgress = 0.3
            
            // Step 2: Upload to S3
            let uploadSuccess = try await uploadToS3(presignedUrl: presignedUrl, videoData: videoData)
            guard uploadSuccess else {
                throw NSError(domain: "Upload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to upload to S3"])
            }
            
            uploadProgress = 0.7
            
            // Step 3: Store metadata
            try await storeVideoMetadata(videoKey: videoKey, title: title, description: description)
            
            uploadProgress = 1.0
        } catch {
            isUploading = false
            uploadProgress = 0
            throw error
        }
        
        isUploading = false
    }
} 