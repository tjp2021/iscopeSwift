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
    var captionSettings: CaptionSettings
}

struct CaptionSettings: Codable {
    var fontSize: Double
    var captionColor: String
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
        
        // Get the translated segments if they exist
        let segments = if language == "en" {
            video.transcriptionSegments
        } else {
            video.translations?[language]?.segments
        }
        
        guard let segments = segments else {
            print("[ERROR] ExportManager - No segments found for language: \(language)")
            throw NSError(domain: "ExportManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "No captions available for selected language"])
        }
        
        let jobId = UUID().uuidString
        let now = Date()
        
        // Get caption settings from UserDefaults
        let fontSize = UserDefaults.standard.double(forKey: "caption_font_size")
        let colorComponents = UserDefaults.standard.array(forKey: "caption_color") as? [CGFloat] ?? [1.0, 1.0, 1.0] // Default to white
        
        // Convert color components to hex string for ASS/SSA format (&HAABBGGRR)
        let colorHex = String(format: "&H00%02X%02X%02X&", 
            Int(colorComponents[2] * 255),  // Blue
            Int(colorComponents[1] * 255),  // Green
            Int(colorComponents[0] * 255))  // Red
        
        let captionSettings = CaptionSettings(
            fontSize: fontSize > 0 ? fontSize : 20, // Default to 20 if not set
            captionColor: colorHex
        )
        
        // Create the export job document
        let job = ExportJob(
            id: jobId,
            userId: userId,
            videoId: video.id,
            language: language,
            status: .pending,
            createdAt: now,
            updatedAt: now,
            error: nil,
            downloadUrl: nil,
            progress: nil,
            captionSettings: captionSettings
        )
        
        // Convert job to dictionary
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let jobData = try encoder.encode(job)
        var jobDict = try JSONSerialization.jsonObject(with: jobData) as! [String: Any]
        
        // Convert dates to Firestore Timestamps
        jobDict["createdAt"] = Timestamp(date: now)
        jobDict["updatedAt"] = Timestamp(date: now)
        
        // Save to Firestore
        try await db.collection("exportJobs").document(jobId).setData(jobDict)
        
        // Notify server to start processing
        let serverRequest = [
            "jobId": jobId,
            "videoId": video.id,
            "language": language,
            "captionSettings": [
                "fontSize": captionSettings.fontSize,
                "captionColor": captionSettings.captionColor
            ]
        ] as [String: Any]
        
        guard let url = URL(string: "\(serverUrl)/start-export") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: serverRequest)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        return job
    }
    
    func getExportJob(_ jobId: String) async throws -> ExportJob? {
        print("[DEBUG] ExportManager - Fetching job: \(jobId)")
        let snapshot = try await db.collection("exportJobs").document(jobId).getDocument()
        guard var data = snapshot.data() else {
            print("[DEBUG] ExportManager - No data found for job: \(jobId)")
            return nil
        }
        
        // Convert timestamps to milliseconds since 1970
        if let createdAtTimestamp = data["createdAt"] as? Timestamp {
            data["createdAt"] = createdAtTimestamp.dateValue().timeIntervalSince1970 * 1000
        }
        if let updatedAtTimestamp = data["updatedAt"] as? Timestamp {
            data["updatedAt"] = updatedAtTimestamp.dateValue().timeIntervalSince1970 * 1000
        }
        
        // Safely extract caption settings
        let captionSettingsData = data["captionSettings"] as? [String: Any] ?? [:]
        let fontSize = captionSettingsData["fontSize"] as? Double ?? 20
        let captionColor = captionSettingsData["captionColor"] as? String ?? ""
        
        // Convert to JSON and decode using our Codable implementation
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data)
            var job = try decoder.decode(ExportJob.self, from: jsonData)
            job.captionSettings = CaptionSettings(
                fontSize: fontSize,
                captionColor: captionColor
            )
            return job
        } catch {
            print("[ERROR] ExportManager - Failed to decode job data: \(error)")
            return nil
        }
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
                    
                    guard var data = snapshot?.data() else {
                        print("[ERROR] ExportManager - No data in snapshot for job: \(jobId)")
                        return
                    }
                    
                    print("[DEBUG] ExportManager - Received Firestore update for job: \(jobId)")
                    print("[DEBUG] ExportManager - Raw data: \(data)")
                    
                    // Handle NaN progress value
                    if let progress = data["progress"] as? Double, progress.isNaN {
                        data["progress"] = nil
                    }
                    
                    // Convert timestamps to milliseconds since 1970
                    if let createdAtTimestamp = data["createdAt"] as? Timestamp {
                        data["createdAt"] = createdAtTimestamp.dateValue().timeIntervalSince1970 * 1000
                    }
                    if let updatedAtTimestamp = data["updatedAt"] as? Timestamp {
                        data["updatedAt"] = updatedAtTimestamp.dateValue().timeIntervalSince1970 * 1000
                    }
                    
                    // Safely extract caption settings
                    let captionSettingsData = data["captionSettings"] as? [String: Any] ?? [:]
                    let fontSize = captionSettingsData["fontSize"] as? Double ?? 20
                    let captionColor = captionSettingsData["captionColor"] as? String ?? ""
                    
                    // Convert to JSON and decode using our Codable implementation
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .millisecondsSince1970
                    
                    do {
                        let jsonData = try JSONSerialization.data(withJSONObject: data)
                        var job = try decoder.decode(ExportJob.self, from: jsonData)
                        job.captionSettings = CaptionSettings(
                            fontSize: fontSize,
                            captionColor: captionColor
                        )
                        continuation.yield(job)
                    } catch {
                        print("[ERROR] ExportManager - Failed to decode job update: \(error)")
                    }
                }
            
            continuation.onTermination = { @Sendable _ in
                print("[DEBUG] ExportManager - Stopping observation for job: \(jobId)")
                listener.remove()
            }
        }
    }
} 