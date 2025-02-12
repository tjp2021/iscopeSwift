import SwiftUI

struct CaptionSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var showCaptions: Bool
    @ObservedObject var viewModel: CaptionSettingsViewModel
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle("Show Captions", isOn: $showCaptions)
                }
                
                if showCaptions {
                    Section(header: Text("Font Size")) {
                        VStack {
                            Slider(value: $viewModel.fontSize, in: 12...32, step: 1) {
                                Text("Font Size")
                            }
                            
                            // Preview text with the same styling as actual captions
                            Text("Preview Text")
                                .font(.system(size: viewModel.fontSize, weight: .semibold))
                                .padding()
                                .frame(maxWidth: .infinity)
                                .foregroundColor(.white)
                                .background(Color.black.opacity(0.75))
                                .cornerRadius(8)
                        }
                    }
                }
            }
            .navigationTitle("Caption Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
} 