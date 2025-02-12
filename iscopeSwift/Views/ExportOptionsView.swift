import SwiftUI

struct ExportOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var exportManager = ExportManager.shared
    let video: Video
    let currentLanguage: String
    @State private var isExporting = false
    @State private var error: String?
    @State private var exportJob: ExportJob?
    @State private var downloadUrl: String?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Video Info
                Text("Export Video with Subtitles")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                // Language Info
                HStack {
                    Image(systemName: "captions.bubble")
                    Text("Language: \(languageName(for: currentLanguage))")
                }
                .foregroundColor(.secondary)
                
                // Status Info
                if let job = exportJob {
                    VStack(spacing: 8) {
                        switch job.status {
                        case .pending:
                            Text("Preparing export...")
                            ProgressView()
                        case .processing:
                            Text("Processing video...")
                            if let progress = job.progress {
                                VStack(spacing: 4) {
                                    ProgressView(value: Double(progress) / 100.0)
                                        .progressViewStyle(.linear)
                                    Text("\(progress)%")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                ProgressView()
                            }
                        case .completed:
                            if let url = job.downloadUrl {
                                Link("Download Video", destination: URL(string: url)!)
                                    .buttonStyle(.borderedProminent)
                            }
                        case .failed:
                            Text(job.error ?? "Export failed")
                                .foregroundColor(.red)
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
                
                // Export Button
                if exportJob == nil {
                    Button(action: startExport) {
                        if isExporting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Export Video")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isExporting)
                }
                
                if let error = error {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding()
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Export Video")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(leading: Button("Cancel") {
                dismiss()
            }
            .disabled(isExporting))
        }
    }
    
    private func startExport() {
        print("[DEBUG] ExportOptionsView - Starting export process")
        isExporting = true
        error = nil
        
        Task {
            do {
                print("[DEBUG] ExportOptionsView - Creating export job")
                let job = try await exportManager.createExportJob(for: video, language: currentLanguage)
                print("[DEBUG] ExportOptionsView - Job created with ID: \(job.id)")
                exportJob = job
                
                // Start observing the job status
                print("[DEBUG] ExportOptionsView - Starting job observation")
                for await updatedJob in exportManager.observeExportJob(job.id) {
                    print("[DEBUG] ExportOptionsView - Received job update: status=\(updatedJob.status.rawValue), progress=\(updatedJob.progress ?? -1)")
                    exportJob = updatedJob
                    if updatedJob.status == .completed || updatedJob.status == .failed {
                        print("[DEBUG] ExportOptionsView - Job finished with status: \(updatedJob.status.rawValue)")
                        break
                    }
                }
                
                isExporting = false
            } catch {
                print("[ERROR] ExportOptionsView - Export failed: \(error.localizedDescription)")
                self.error = error.localizedDescription
                isExporting = false
            }
        }
    }
    
    private func languageName(for code: String) -> String {
        switch code {
        case "en": return "English"
        case "es": return "Spanish"
        case "fr": return "French"
        case "de": return "German"
        case "it": return "Italian"
        case "pt": return "Portuguese"
        case "ru": return "Russian"
        case "ja": return "Japanese"
        case "ko": return "Korean"
        case "zh": return "Chinese"
        default: return code.uppercased()
        }
    }
} 