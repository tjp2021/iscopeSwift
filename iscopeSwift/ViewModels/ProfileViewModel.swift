import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
class ProfileViewModel: ObservableObject {
    @Published var profileImage: UIImage?
    @Published var profileImageUrl: String?
    @Published var isLoading = false
    
    static let shared = ProfileViewModel()
    private let db = Firestore.firestore()
    
    func loadProfileImage() {
        Task { [weak self] in
            guard let self = self else { return }
            guard let userId = Auth.auth().currentUser?.uid else { return }
            
            self.isLoading = true
            defer { self.isLoading = false }
            
            do {
                let userDoc = try await db.collection("users").document(userId).getDocument()
                if let userData = userDoc.data(),
                   let imageUrl = userData["profileImageUrl"] as? String,
                   let url = URL(string: imageUrl) {
                    
                    self.profileImageUrl = imageUrl
                    
                    let session = URLSession.shared
                    let (data, _) = try await session.data(from: url)
                    
                    if let image = UIImage(data: data) {
                        self.profileImage = image
                    }
                }
            } catch {
                print("[ProfileViewModel] Error loading profile image: \(error)")
            }
        }
    }
    
    func updateProfileImage(_ image: UIImage, url: String) {
        self.profileImage = image
        self.profileImageUrl = url
    }
} 