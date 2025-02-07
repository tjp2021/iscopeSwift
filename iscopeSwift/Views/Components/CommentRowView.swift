import SwiftUI
import FirebaseAuth

struct CommentRowView: View {
    let comment: Comment
    let onDelete: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Profile Image
            Circle()
                .fill(Color.gray.opacity(0.2))
                .overlay(
                    Text(String((comment.userEmail ?? "").prefix(1)).uppercased())
                        .foregroundColor(.gray)
                )
                .frame(width: 40, height: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                // Email
                if let email = comment.userEmail {
                    Text(email)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                
                // Comment text
                Text(comment.text)
                    .font(.body)
            }
            
            Spacer()
            
            // Delete button (only show for comment owner)
            if comment.userId == Auth.auth().currentUser?.uid {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .imageScale(.large)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(PlainButtonStyle()) // This prevents tap propagation
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle()) // This makes the whole row tappable
    }
} 