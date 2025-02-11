import SwiftUI

struct VideoRowView: View {
    let video: Video
    
    var body: some View {
        HStack {
            // Thumbnail
            AsyncImage(url: URL(string: video.thumbnailUrl ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
            }
            .frame(width: 120, height: 80)
            .cornerRadius(8)
            
            // Video details
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.headline)
                    .lineLimit(2)
                
                if let description = video.description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Text(formatDate(video.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

#Preview {
    VideoRowView(video: Video(
        id: "mockId",
        userId: "mockUserId",
        title: "Test Video",
        description: "A test video description that might be long enough to show multiple lines in the UI",
        url: "https://example.com/video.mp4",
        thumbnailUrl: nil,
        createdAt: Date()
    ))
} 