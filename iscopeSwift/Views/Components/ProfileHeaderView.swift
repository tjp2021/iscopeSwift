import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ProfileHeaderView: View {
    let totalVideos: Int
    let totalViews: Int
    @StateObject private var profileViewModel = ProfileViewModel.shared
    
    var body: some View {
        VStack(spacing: 16) {
            // Profile Image
            if let profileImage = profileViewModel.profileImage {
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
            await profileViewModel.loadProfileImage()
        }
    }
}

#Preview {
    ProfileHeaderView(totalVideos: 5, totalViews: 1234)
} 