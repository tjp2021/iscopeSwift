import SwiftUI
import AVKit

struct VideoGridItem: View {
    let video: Video
    @State private var thumbnail: UIImage?
    @State private var isLoadingThumbnail = true
    @State private var duration: Double?
    @State private var isPressed = false
    
    var formattedDuration: String {
        guard let duration = duration else { return "" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black
                
                if isLoadingThumbnail {
                    ProgressView()
                        .tint(.white)
                }
                
                // Thumbnail
                if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
                
                // Play Icon Overlay
                Image(systemName: "play.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.5), radius: 3)
                    .opacity(isPressed ? 1 : 0)
                
                // Overlays
                VStack {
                    // Duration overlay (top right)
                    HStack {
                        Spacer()
                        if let _ = duration {
                            Text(formattedDuration)
                                .font(.caption2)
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.6))
                                .cornerRadius(4)
                                .padding(4)
                        }
                    }
                    
                    Spacer()
                    
                    // Bottom overlay with view count
                    HStack {
                        Image(systemName: "eye.fill")
                            .font(.caption2)
                        Text("\(video.viewCount)")
                            .font(.caption2)
                        Spacer()
                    }
                    .foregroundColor(.white)
                    .padding(4)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [.clear, .black.opacity(0.7)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .onAppear {
            generateThumbnail()
            fetchDuration()
        }
        .pressAction {
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = true
            }
        } onRelease: {
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = false
            }
        }
    }
    
    private func generateThumbnail() {
        guard let videoUrl = URL(string: video.videoUrl) else { return }
        
        let asset = AVURLAsset(url: videoUrl)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        // Generate thumbnail at 0.1 seconds
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        
        Task {
            do {
                let cgImage = try await imageGenerator.image(at: time).image
                thumbnail = UIImage(cgImage: cgImage)
                isLoadingThumbnail = false
            } catch {
                print("Error generating thumbnail: \(error)")
                isLoadingThumbnail = false
            }
        }
    }
    
    private func fetchDuration() {
        guard let videoUrl = URL(string: video.videoUrl) else { return }
        
        let asset = AVURLAsset(url: videoUrl)
        Task {
            do {
                let duration = try await asset.load(.duration)
                await MainActor.run {
                    self.duration = duration.seconds
                }
            } catch {
                print("Error fetching duration: \(error)")
            }
        }
    }
}

// Helper view modifier for press gesture
struct PressAction: ViewModifier {
    var onPress: () -> Void
    var onRelease: () -> Void
    
    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        onPress()
                    }
                    .onEnded { _ in
                        onRelease()
                    }
            )
    }
}

extension View {
    func pressAction(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        modifier(PressAction(onPress: onPress, onRelease: onRelease))
    }
}

#Preview {
    VideoGridItem(video: Video(
        id: "test",
        title: "Test Video",
        description: "Test Description",
        videoUrl: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
        creatorId: "test",
        createdAt: Date(),
        likeCount: 0,
        commentCount: 0,
        isLiked: false,
        viewCount: 123
    ))
    .frame(width: 150, height: 150)
} 