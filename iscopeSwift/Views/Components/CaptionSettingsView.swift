import SwiftUI

struct CaptionSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var showCaptions: Bool
    @ObservedObject var viewModel: CaptionSettingsViewModel
    
    // Predefined colors
    private let colors: [Color] = [
        .white,
        .blue,
        .green,
        .yellow,
        .red
    ]
    
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
                                .foregroundColor(viewModel.captionColor)
                                .background(Color.black.opacity(0.75))
                                .cornerRadius(8)
                        }
                    }
                    
                    Section(header: Text("Caption Color")) {
                        HStack(spacing: 12) {
                            ForEach(colors, id: \.self) { color in
                                Circle()
                                    .fill(color)
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.primary, lineWidth: viewModel.captionColor == color ? 2 : 0)
                                    )
                                    .onTapGesture {
                                        viewModel.captionColor = color
                                    }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    
                    Section(header: Text("Caption Position")) {
                        VStack {
                            Slider(value: $viewModel.verticalPosition, in: 0...1) {
                                Text("Vertical Position")
                            }
                            
                            // Position preview container
                            GeometryReader { geometry in
                                ZStack(alignment: .center) {
                                    Color.black.opacity(0.1)
                                    
                                    // Preview text positioned according to slider
                                    VStack {
                                        // Add top safe zone
                                        let safeZone = geometry.size.height * 0.15 // 15% padding top and bottom
                                        let availableHeight = geometry.size.height - (safeZone * 2)
                                        let adjustedPosition = (availableHeight * viewModel.verticalPosition) + safeZone
                                        
                                        Spacer()
                                            .frame(height: adjustedPosition)
                                        
                                        Text("Preview Text")
                                            .font(.system(size: viewModel.fontSize, weight: .semibold))
                                            .foregroundColor(viewModel.captionColor)
                                            .padding(8)
                                            .background(Color.black.opacity(0.75))
                                            .cornerRadius(8)
                                        
                                        Spacer()
                                    }
                                }
                            }
                            .frame(height: 200)
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