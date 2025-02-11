import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct VideoEngagementView: View {
    @ObservedObject var viewModel: VideoEngagementViewModel
    let video: Video
    @State private var showingTranscription = false
    
    var body: some View {
        HStack(spacing: 20) {
            Button(action: {
                viewModel.handleLikeAction(for: video)
            }) {
                Image(systemName: viewModel.isVideoLiked(video) ? "heart.fill" : "heart")
                    .foregroundColor(viewModel.isVideoLiked(video) ? .red : .gray)
            }
            
            Button(action: {
                showingTranscription.toggle()
            }) {
                Image(systemName: "captions.bubble")
                    .foregroundColor(.gray)
            }
            .sheet(isPresented: $showingTranscription) {
                TranscriptionView(video: video)
            }
        }
        .padding()
    }
} 