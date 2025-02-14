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
            VStack(spacing: 0) {
                // Header Section
                VStack(spacing: 16) {
                    Image(systemName: "square.and.arrow.up.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue)
                        .padding(.top, 20)
                    
                    Text("Export Video with Subtitles")
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    // Language Info
                    HStack(spacing: 8) {
                        Image(systemName: "captions.bubble.fill")
                            .foregroundStyle(.blue)
                        Text(languageName(for: currentLanguage))
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(20)
                }
                .padding(.bottom, 32)
                
                // Status Section
                if let job = exportJob {
                    VStack(spacing: 24) {
                        switch job.status {
                        case .pending:
                            exportStatusView(
                                icon: "clock.fill",
                                title: "Preparing Export",
                                message: "Setting up your video export...",
                                showProgress: true,
                                progress: nil
                            )
                            
                        case .processing:
                            exportStatusView(
                                icon: "gear.circle.fill",
                                title: "Processing Video",
                                message: "Adding subtitles to your video...",
                                showProgress: true,
                                progress: job.progress.map { Double($0) / 100.0 }
                            )
                            
                        case .completed:
                            exportStatusView(
                                icon: "checkmark.circle.fill",
                                title: "Export Complete!",
                                message: "Your video is ready to download",
                                showProgress: false
                            )
                            
                            if let url = job.downloadUrl {
                                Link(destination: URL(string: url)!) {
                                    HStack {
                                        Image(systemName: "arrow.down.circle.fill")
                                        Text("Download Video")
                                    }
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .cornerRadius(12)
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 8)
                                
                                Button("Done") {
                                    dismiss()
                                }
                                .font(.headline)
                                .foregroundColor(.blue)
                                .padding(.top, 8)
                            }
                            
                        case .failed:
                            exportStatusView(
                                icon: "exclamationmark.circle.fill",
                                title: "Export Failed",
                                message: job.error ?? "An error occurred during export",
                                showProgress: false,
                                isError: true
                            )
                        }
                    }
                    .padding(.horizontal)
                } else {
                    // Initial Export Button
                    Button(action: startExport) {
                        HStack(spacing: 12) {
                            if isExporting {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(isExporting ? "Starting Export..." : "Export Video")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isExporting ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isExporting)
                    .padding(.horizontal, 20)
                }
                
                if let error = error {
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                }
                
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(leading: Button("Cancel") {
                dismiss()
            }
            .disabled(isExporting))
        }
    }
    
    private func exportStatusView(
        icon: String,
        title: String,
        message: String,
        showProgress: Bool,
        progress: Double? = nil,
        isError: Bool = false
    ) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(isError ? .red : .blue)
            
            Text(title)
                .font(.headline)
                .foregroundColor(isError ? .red : .primary)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if showProgress {
                if let progress = progress {
                    VStack(spacing: 8) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(.blue)
                        Text("\(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                } else {
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding()
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 2)
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