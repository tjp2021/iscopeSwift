import SwiftUI

struct VideoRowView: View {
    let video: Video
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(video.title)
                .font(.headline)
            Text(video.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
            
            HStack(spacing: 16) {
                Label("\(video.viewCount)", systemImage: "eye")
                    .foregroundColor(.secondary)
                Label("\(video.likeCount)", systemImage: "heart")
                    .foregroundColor(.secondary)
                Label("\(video.commentCount)", systemImage: "bubble.right")
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(video.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    VideoRowView(video: Video(
        id: "test",
        title: "Test Video",
        description: "This is a test video description that might be a bit longer to test the line limit.",
        videoUrl: "",
        creatorId: "test_user",
        createdAt: Date(),
        likeCount: 123,
        commentCount: 45,
        isLiked: false,
        viewCount: 678
    ))
    .padding()
} 