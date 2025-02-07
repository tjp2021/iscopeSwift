import SwiftUI
import AVKit

struct VideoGridItem: View {
    let video: Video
    @State private var thumbnail: UIImage?
    @State private var isLoadingThumbnail = true
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black
                
                if isLoadingThumbnail {
                    ProgressView()
                }
                
                // Thumbnail
                if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
                
                // Overlays
                VStack {
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