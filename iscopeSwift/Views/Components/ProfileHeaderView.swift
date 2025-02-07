import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ProfileHeaderView: View {
    let totalVideos: Int
    let totalViews: Int
    @State private var profileImageUrl: String?
    @State private var profileImage: UIImage?
    
    var body: some View {
        VStack(spacing: 16) {
            // Profile Image
            if let profileImage = profileImage {
                Image(uiImage: profileImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .foregroundColor(.gray)
            }
            
            // User Email
            if let email = Auth.auth().currentUser?.email {
                Text(email)
                    .font(.headline)
            }
            
            // Stats Row
            HStack(spacing: 32) {
                VStack {
                    Text("\(totalVideos)")
                        .font(.headline)
                    Text("Videos")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                VStack {
                    Text("\(totalViews)")
                        .font(.headline)
                    Text("Views")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .task {
            await loadProfileImage()
        }
    }
    
    private func loadProfileImage() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            let db = Firestore.firestore()
            let userDoc = try await db.collection("users").document(userId).getDocument()
            if let userData = userDoc.data(),
               let imageUrl = userData["profileImageUrl"] as? String,
               let url = URL(string: imageUrl) {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    self.profileImage = image
                }
            }
        } catch {
            print("[ProfileHeaderView] Error loading profile image: \(error)")
        }
    }
}

#Preview {
    ProfileHeaderView(totalVideos: 5, totalViews: 1234)
} 