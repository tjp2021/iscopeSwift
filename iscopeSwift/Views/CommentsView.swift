import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import Foundation

@MainActor
class CommentsViewModel: ObservableObject {
    @Published var comments: [Comment] = []
    @Published var newComment: String = ""
    @Published var isLoading = false
    @Published var error: String?
    
    private let db = Firestore.firestore()
    private let videoId: String
    
    init(videoId: String) {
        self.videoId = videoId
    }
    
    @MainActor
    func fetchComments() async {
        guard !isLoading else { return }
        isLoading = true
        
        do {
            let snapshot = try await db.collection("videos")
                .document(videoId)
                .collection("comments")
                .order(by: "createdAt", descending: true)
                .getDocuments()
            
            comments = snapshot.documents.compactMap { Comment.from($0) }
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    @MainActor
    func addComment() async {
        guard !newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let userId = Auth.auth().currentUser?.uid else { return }
        
        let commentText = newComment
        newComment = ""
        
        do {
            let ref = db.collection("videos").document(videoId)
            
            let _ = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                // Add comment
                let commentRef = ref.collection("comments").document()
                
                // Get the document first - if this fails, it will set the error pointer
                guard let videoDoc = try? transaction.getDocument(ref),
                      let currentCount = videoDoc.data()?["commentCount"] as? Int else {
                    if let errorPointer = errorPointer {
                        errorPointer.pointee = NSError(
                            domain: "CommentsViewModel",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to read video document"]
                        )
                    }
                    return nil
                }
                
                // If we get here, document read was successful
                transaction.setData([
                    "text": commentText,
                    "userId": userId,
                    "userDisplayName": Auth.auth().currentUser?.displayName ?? "Anonymous",
                    "createdAt": FieldValue.serverTimestamp(),
                    "likeCount": 0
                ], forDocument: commentRef)
                
                transaction.updateData(["commentCount": currentCount + 1], forDocument: ref)
                return nil
            })
            
            // Refresh comments
            await fetchComments()
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    @MainActor
    func deleteComment(_ comment: Comment) async {
        do {
            let ref = db.collection("videos").document(videoId)
            let commentRef = ref.collection("comments").document(comment.id)
            
            let _ = try await db.runTransaction({ (transaction, errorPointer) -> Any? in
                // Get the document first - if this fails, it will set the error pointer
                guard let videoDoc = try? transaction.getDocument(ref),
                      let currentCount = videoDoc.data()?["commentCount"] as? Int else {
                    if let errorPointer = errorPointer {
                        errorPointer.pointee = NSError(
                            domain: "CommentsViewModel",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to read video document"]
                        )
                    }
                    return nil
                }
                
                // Delete comment and update count
                transaction.deleteDocument(commentRef)
                transaction.updateData(["commentCount": max(0, currentCount - 1)], forDocument: ref)
                return nil
            })
            
            // Remove comment from local state
            comments.removeAll { $0.id == comment.id }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct CommentsView: View {
    let video: Video
    @StateObject private var viewModel: CommentsViewModel
    @Environment(\.dismiss) private var dismiss
    
    init(video: Video) {
        self.video = video
        _viewModel = StateObject(wrappedValue: CommentsViewModel(videoId: video.id ?? ""))
    }
    
    var body: some View {
        NavigationView {
            VStack {
                if viewModel.isLoading {
                    ProgressView()
                } else {
                    List {
                        ForEach(viewModel.comments) { comment in
                            HStack(alignment: .top, spacing: 12) {
                                // Profile Image
                                Circle()
                                    .fill(Color.gray.opacity(0.2))
                                    .overlay(
                                        Text(String(comment.userDisplayName.prefix(1)).uppercased())
                                            .foregroundColor(.gray)
                                    )
                                    .frame(width: 40, height: 40)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    // Username/Email
                                    Text(comment.userDisplayName)
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                    
                                    // Comment text
                                    Text(comment.text)
                                        .font(.body)
                                }
                                
                                Spacer()
                                
                                // Delete button (only show for comment owner)
                                if comment.userId == Auth.auth().currentUser?.uid {
                                    Button(action: {
                                        Task {
                                            await viewModel.deleteComment(comment)
                                        }
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.gray)
                                            .imageScale(.small)
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .listStyle(PlainListStyle())
                }
                
                // Comment input
                HStack {
                    TextField("Add a comment...", text: $viewModel.newComment)
                        .textFieldStyle(.roundedBorder)
                    
                    Button("Post") {
                        Task {
                            await viewModel.addComment()
                        }
                    }
                    .disabled(viewModel.newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") {
                dismiss()
            })
            .task {
                await viewModel.fetchComments()
            }
            .alert("Error", isPresented: .constant(viewModel.error != nil)) {
                Button("OK", role: .cancel) {
                    viewModel.error = nil
                }
            } message: {
                if let error = viewModel.error {
                    Text(error)
                }
            }
        }
    }
} 