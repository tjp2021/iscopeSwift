import Foundation
import FirebaseFirestore
import FirebaseAuth

enum ExportStatus: String, Codable {
    case pending
    case processing
    case completed
    case failed
}

struct ExportJob: Codable {
    let id: String
    let userId: String
    let videoId: String
    let language: String
    var status: ExportStatus
    let createdAt: Date
    var updatedAt: Date
    var error: String?
    var downloadUrl: String?
    var progress: Int?
    let captionSettings: CaptionSettings
}

struct CaptionSettings: Codable {
    let fontSize: Double
    let captionColor: String
    let verticalPosition: Double
}

@MainActor
class ExportManager: ObservableObject {
    static let shared = ExportManager()
    
    private let db = Firestore.firestore()
    private let serverUrl = "http://localhost:3001/api"
    
    private init() {}
    
    func createExportJob(for video: Video, language: String) async throws -> ExportJob {
        print("[DEBUG] ExportManager - Creating new export job")
        guard let userId = Auth.auth().currentUser?.uid else {
            print("[ERROR] ExportManager - No authenticated user")
            throw NSError(domain: "ExportManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let jobId = UUID().uuidString
        let now = Date()
        
        // Get caption settings from UserDefaults
        let fontSize = UserDefaults.standard.double(forKey: "caption_font_size")
        let colorComponents = UserDefaults.standard.array(forKey: "caption_color") as? [CGFloat] ?? [1.0, 1.0, 1.0] // Default to white
        let verticalPosition = UserDefaults.standard.double(forKey: "caption_vertical_position")
        
        // Convert color components to hex string for ASS/SSA format (&HAABBGGRR)
        let colorHex = String(format: "&H00%02X%02X%02X&", 
            Int(colorComponents[2] * 255),  // Blue
            Int(colorComponents[1] * 255),  // Green
            Int(colorComponents[0] * 255))  // Red
        
        let captionSettings = CaptionSettings(
            fontSize: fontSize > 0 ? fontSize : 20, // Default to 20 if not set
            captionColor: colorHex,
            verticalPosition: verticalPosition > 0 ? verticalPosition : 0.8 // Default to 0.8 if not set
        )
        
        let job = ExportJob(
            id: jobId,
            userId: userId,
            videoId: video.id,
            language: language,
            status: .pending,
            createdAt: now,
            updatedAt: now,
            captionSettings: captionSettings
        )
        
        print("[DEBUG] ExportManager - Creating Firestore document for job: \(jobId)")
        // Create the job in Firestore
        try await db.collection("exportJobs").document(jobId).setData([
            "id": job.id,
            "userId": job.userId,
            "videoId": job.videoId,
            "language": job.language,
            "status": job.status.rawValue,
            "createdAt": job.createdAt,
            "updatedAt": job.updatedAt,
            "captionSettings": [
                "fontSize": captionSettings.fontSize,
                "captionColor": captionSettings.captionColor,
                "verticalPosition": captionSettings.verticalPosition
            ]
        ])
        
        // Trigger the export process on the server
        guard let url = URL(string: "\(serverUrl)/export/process/\(jobId)") else {
            print("[ERROR] ExportManager - Invalid server URL")
            throw NSError(domain: "ExportManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"])
        }
        
        print("[DEBUG] ExportManager - Sending request to server: \(url)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "videoId": video.id,
            "language": language
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            print("[ERROR] ExportManager - Server request failed with status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            throw NSError(domain: "ExportManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to start export process"])
        }
        
        print("[DEBUG] ExportManager - Job created successfully")
        return job
    }
    
    func getExportJob(_ jobId: String) async throws -> ExportJob? {
        print("[DEBUG] ExportManager - Fetching job: \(jobId)")
        let snapshot = try await db.collection("exportJobs").document(jobId).getDocument()
        guard let data = snapshot.data() else {
            print("[DEBUG] ExportManager - No data found for job: \(jobId)")
            return nil
        }
        
        // Safely extract caption settings
        let captionSettingsData = data["captionSettings"] as? [String: Any] ?? [:]
        let fontSize = captionSettingsData["fontSize"] as? Double ?? 20
        let captionColor = captionSettingsData["captionColor"] as? String ?? ""
        let verticalPosition = captionSettingsData["verticalPosition"] as? Double ?? 0.8
        
        let job = ExportJob(
            id: data["id"] as? String ?? "",
            userId: data["userId"] as? String ?? "",
            videoId: data["videoId"] as? String ?? "",
            language: data["language"] as? String ?? "",
            status: ExportStatus(rawValue: data["status"] as? String ?? "") ?? .failed,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date(),
            error: data["error"] as? String,
            downloadUrl: data["downloadUrl"] as? String,
            progress: data["progress"] as? Int,
            captionSettings: CaptionSettings(
                fontSize: fontSize,
                captionColor: captionColor,
                verticalPosition: verticalPosition
            )
        )
        print("[DEBUG] ExportManager - Job fetched: status=\(job.status.rawValue), progress=\(job.progress ?? -1)")
        return job
    }
    
    func observeExportJob(_ jobId: String) -> AsyncStream<ExportJob> {
        print("[DEBUG] ExportManager - Starting observation for job: \(jobId)")
        return AsyncStream { continuation in
            let listener = db.collection("exportJobs").document(jobId)
                .addSnapshotListener { snapshot, error in
                    if let error = error {
                        print("[ERROR] ExportManager - Listener error: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let data = snapshot?.data() else {
                        print("[ERROR] ExportManager - No data in snapshot for job: \(jobId)")
                        return
                    }
                    
                    print("[DEBUG] ExportManager - Received Firestore update for job: \(jobId)")
                    print("[DEBUG] ExportManager - Raw data: \(data)")
                    
                    // Safely extract caption settings
                    let captionSettingsData = data["captionSettings"] as? [String: Any] ?? [:]
                    let fontSize = captionSettingsData["fontSize"] as? Double ?? 20
                    let captionColor = captionSettingsData["captionColor"] as? String ?? ""
                    let verticalPosition = captionSettingsData["verticalPosition"] as? Double ?? 0.8
                    
                    let job = ExportJob(
                        id: data["id"] as? String ?? "",
                        userId: data["userId"] as? String ?? "",
                        videoId: data["videoId"] as? String ?? "",
                        language: data["language"] as? String ?? "",
                        status: ExportStatus(rawValue: data["status"] as? String ?? "") ?? .failed,
                        createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                        updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date(),
                        error: data["error"] as? String,
                        downloadUrl: data["downloadUrl"] as? String,
                        progress: data["progress"] as? Int,
                        captionSettings: CaptionSettings(
                            fontSize: fontSize,
                            captionColor: captionColor,
                            verticalPosition: verticalPosition
                        )
                    )
                    
                    print("[DEBUG] ExportManager - Parsed job update: status=\(job.status.rawValue), progress=\(job.progress ?? -1)")
                    continuation.yield(job)
                }
            
            continuation.onTermination = { @Sendable _ in
                print("[DEBUG] ExportManager - Stopping observation for job: \(jobId)")
                listener.remove()
            }
        }
    }
} 