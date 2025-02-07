import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// Import network response types
struct SettingsProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var authViewModel: AuthViewModel
    @StateObject private var viewModel = VideoFeedViewModel()
    @State private var username = ""
    @State private var email = ""
    @State private var showImagePicker = false
    @State private var profileImage: UIImage?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isSaving = false
    @State private var showPasswordChange = false
    @State private var showSuccessAlert = false
    
    private let db = Firestore.firestore()
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    // Profile Picture
                    HStack {
                        if let profileImage = profileImage {
                            Image(uiImage: profileImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .frame(width: 80, height: 80)
                                .foregroundColor(.gray)
                        }
                        
                        Button("Change Profile Picture") {
                            showImagePicker = true
                        }
                    }
                    .padding(.vertical, 8)
                    
                    // Username
                    TextField("Username", text: $username)
                    
                    // Email
                    TextField("Email", text: $email)
                }
                
                Section {
                    Button("Change Password") {
                        showPasswordChange = true
                    }
                }
                
                Section {
                    #if DEBUG
                    Button {
                        Task {
                            print("[SettingsProfileView] Generating test data")
                            do {
                                try await viewModel.seedTestData()
                            } catch {
                                print("[SettingsProfileView] Error generating test data: \(error)")
                            }
                        }
                    } label: {
                        Label("Generate Test Data", systemImage: "doc.badge.plus")
                    }
                    #endif
                    
                    Button(role: .destructive) {
                        Task {
                            do {
                                try await authViewModel.signOut()
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                                showError = true
                            }
                        }
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            do {
                                try await saveProfile()
                            } catch {
                                errorMessage = error.localizedDescription
                                showError = true
                            }
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(image: $profileImage)
            }
            .sheet(isPresented: $showPasswordChange) {
                PasswordChangeView()
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .alert("Success", isPresented: $showSuccessAlert) {
                Button("OK", role: .cancel) { 
                    dismiss()
                }
            } message: {
                Text("Profile updated successfully")
            }
            .onAppear {
                loadUserProfile()
            }
        }
    }
    
    private func loadUserProfile() {
        guard let user = Auth.auth().currentUser else { return }
        
        email = user.email ?? ""
        
        // Fetch user profile from Firestore
        Task {
            do {
                let userDoc = try await db.collection("users").document(user.uid).getDocument()
                if let userData = userDoc.data() {
                    username = userData["username"] as? String ?? ""
                    if let profileImageUrl = userData["profileImageUrl"] as? String,
                       let url = URL(string: profileImageUrl) {
                        // Download and set profile image
                        let (data, _) = try await URLSession.shared.data(from: url)
                        profileImage = UIImage(data: data)
                    }
                }
            } catch {
                print("[SettingsProfileView] Error loading profile: \(error)")
                errorMessage = "Failed to load profile"
                showError = true
            }
        }
    }
    
    private func saveProfile() async throws {
        guard let user = Auth.auth().currentUser else { return }
        
        isSaving = true
        defer { isSaving = false }
        
        var updates: [String: Any] = [
            "username": username
        ]
        
        // Update email if changed
        if email != user.email {
            try await updateUserEmail(user: user, newEmail: email)
        }
        
        // Upload profile image if changed
        if let newImage = profileImage,
           let imageData = newImage.jpegData(compressionQuality: 0.7) {
            // Get pre-signed URL
            let serverUrl = "http://localhost:3000/generate-profile-url"
            var request = URLRequest(url: URL(string: serverUrl)!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body = ["fileName": "\(user.uid).jpg"]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(PresignedUrlResponse.self, from: data)
            
            // Upload to S3
            var uploadRequest = URLRequest(url: URL(string: response.uploadURL)!)
            uploadRequest.httpMethod = "PUT"
            uploadRequest.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
            
            let (_, uploadResponse) = try await URLSession.shared.upload(for: uploadRequest, from: imageData)
            guard let httpResponse = uploadResponse as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }
            
            // Store S3 URL in updates
            updates["profileImageUrl"] = "https://iscope.s3.us-east-2.amazonaws.com/\(user.uid).jpg"
        }
        
        // Update Firestore
        try await db.collection("users").document(user.uid).setData(updates, merge: true)
        showSuccessAlert = true
    }
    
    @available(*, deprecated)
    private func updateUserEmail(user: User, newEmail: String) async throws {
        try await user.updateEmail(to: newEmail)
    }
}

struct PasswordChangeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    @State private var isChanging = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Current Password", text: $currentPassword)
                    SecureField("New Password", text: $newPassword)
                    SecureField("Confirm New Password", text: $confirmPassword)
                }
                
                Section {
                    Button {
                        Task {
                            await changePassword()
                        }
                    } label: {
                        if isChanging {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Change Password")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isChanging || !isValidForm)
                }
            }
            .navigationTitle("Change Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .alert("Success", isPresented: $showSuccess) {
                Button("OK", role: .cancel) { 
                    dismiss()
                }
            } message: {
                Text("Password changed successfully")
            }
        }
    }
    
    private var isValidForm: Bool {
        !currentPassword.isEmpty &&
        !newPassword.isEmpty &&
        !confirmPassword.isEmpty &&
        newPassword == confirmPassword &&
        newPassword.count >= 6
    }
    
    private func changePassword() async {
        guard let user = Auth.auth().currentUser else { return }
        
        isChanging = true
        defer { isChanging = false }
        
        do {
            // Reauthenticate user
            let credential = EmailAuthProvider.credential(
                withEmail: user.email ?? "",
                password: currentPassword
            )
            try await user.reauthenticate(with: credential)
            
            // Change password
            try await user.updatePassword(to: newPassword)
            showSuccess = true
        } catch {
            print("[PasswordChangeView] Error changing password: \(error)")
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// Image Picker struct for profile picture selection
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
} 