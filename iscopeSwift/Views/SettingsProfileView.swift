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
                    
                    NavigationLink {
                        TranscriptionTestView()
                    } label: {
                        Label("Test Transcription", systemImage: "waveform")
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
    
    private func processImage(_ image: UIImage) -> Data? {
        print("[SettingsProfileView] 🔍 STEP 1: Starting image processing")
        
        do {
            // Just resize to a tiny size since it's only for profile picture
            let size = CGSize(width: 200, height: 200)
            
            print("[SettingsProfileView] 🔍 STEP 2: Creating image context")
            UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
            defer { 
                print("[SettingsProfileView] 🔍 STEP 3: Ending image context")
                UIGraphicsEndImageContext() 
            }
            
            // Simple draw with white background
            print("[SettingsProfileView] 🔍 STEP 4: Drawing white background")
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            
            print("[SettingsProfileView] 🔍 STEP 5: Drawing image")
            image.draw(in: CGRect(origin: .zero, size: size))
            
            print("[SettingsProfileView] 🔍 STEP 6: Getting image from context")
            guard let resizedImage = UIGraphicsGetImageFromCurrentImageContext() else {
                print("[SettingsProfileView] ❌ FATAL: Failed to get image from context")
                return nil
            }
            
            print("[SettingsProfileView] 🔍 STEP 7: Converting to JPEG")
            guard let imageData = resizedImage.jpegData(compressionQuality: 0.5) else {
                print("[SettingsProfileView] ❌ FATAL: Failed to convert to JPEG")
                return nil
            }
            
            print("[SettingsProfileView] ✅ SUCCESS: Image processed, size: \(imageData.count) bytes")
            return imageData
            
        } catch {
            print("[SettingsProfileView] ❌ FATAL ERROR in processImage: \(error)")
            return nil
        }
    }
    
    private func saveProfile() async throws {
        print("[SettingsProfileView] 🔄 Starting profile save")
        
        guard let user = Auth.auth().currentUser else {
            print("[SettingsProfileView] ❌ No authenticated user")
            throw URLError(.userAuthenticationRequired)
        }
        
        isSaving = true
        defer { isSaving = false }
        
        var updates: [String: Any] = ["username": username]
        
        if email != user.email {
            try await updateUserEmail(user: user, newEmail: email)
        }
        
        if let newImage = profileImage {
            guard let imageData = processImage(newImage) else {
                throw URLError(.cannotDecodeContentData)
            }
            
            print("[SettingsProfileView] 📡 Getting pre-signed URL...")
            let serverUrl = "http://localhost:3000/generate-presigned-url"
            var request = URLRequest(url: URL(string: serverUrl)!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Add type and path info to distinguish from video uploads
            let fileName = "\(user.uid).jpg"  // No need for profiles/ prefix, server handles it
            let requestBody: [String: Any] = [
                "fileName": fileName,
                "contentType": "image/jpeg",
                "isProfile": true
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            let (data, urlResponse) = try await URLSession.shared.data(for: request)
            print("[SettingsProfileView] 📡 Pre-signed URL Response: \(String(data: data, encoding: .utf8) ?? "nil")")
            
            guard let httpUrlResponse = urlResponse as? HTTPURLResponse,
                  (200...299).contains(httpUrlResponse.statusCode) else {
                print("[SettingsProfileView] ❌ Failed to get pre-signed URL: \(urlResponse)")
                throw URLError(.badServerResponse)
            }
            
            let presignedUrl = try JSONDecoder().decode(PresignedUrlResponse.self, from: data)
            print("[SettingsProfileView] 📡 Got pre-signed URL: \(presignedUrl.uploadURL)")
            
            // Upload to S3
            print("[SettingsProfileView] 📡 Starting S3 upload...")
            var s3Request = URLRequest(url: URL(string: presignedUrl.uploadURL)!)
            s3Request.httpMethod = "PUT"
            
            // Must use lowercase header names to match AWS SDK signature calculation
            s3Request.setValue("image/jpeg", forHTTPHeaderField: "content-type")
            
            print("[SettingsProfileView] 📡 S3 Request Headers: \(s3Request.allHTTPHeaderFields ?? [:])")
            print("[SettingsProfileView] 📡 S3 Request URL: \(presignedUrl.uploadURL)")
            let (_, uploadResponse) = try await URLSession.shared.upload(for: s3Request, from: imageData)
            guard let httpResponse = uploadResponse as? HTTPURLResponse else {
                print("[SettingsProfileView] ❌ Invalid S3 response type")
                throw URLError(.badServerResponse)
            }
            
            print("[SettingsProfileView] 📡 S3 Response Status: \(httpResponse.statusCode)")
            print("[SettingsProfileView] 📡 S3 Response Headers: \(httpResponse.allHeaderFields)")
            
            if !(200...299).contains(httpResponse.statusCode) {
                // Get the actual error message from S3
                if let errorData = try? await URLSession.shared.data(for: s3Request).0 {
                    print("[SettingsProfileView] ❌ S3 Error Response Body: \(String(data: errorData, encoding: .utf8) ?? "nil")")
                }
                print("[SettingsProfileView] ❌ S3 upload failed with status: \(httpResponse.statusCode)")
                throw URLError(.badServerResponse)
            }
            
            // Use the key from the server response to build the URL
            let s3Url = "https://iscope.s3.us-east-2.amazonaws.com/\(presignedUrl.imageKey)"
            print("[SettingsProfileView] ✅ S3 upload successful, URL: \(s3Url)")
            updates["profileImageUrl"] = s3Url
            
            // Update Firestore
            try await db.collection("users").document(user.uid).setData(updates, merge: true)
            
            // Update the shared profile view model
            ProfileViewModel.shared.updateProfileImage(newImage, url: s3Url)
            
            showSuccessAlert = true
        }
        
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
        picker.allowsEditing = true // Use built-in editing instead of background removal
        picker.sourceType = .photoLibrary
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
            print("[ImagePicker] Picked image with keys: \(info.keys)")
            
            // Use edited image if available, otherwise use original
            if let editedImage = info[.editedImage] as? UIImage {
                print("[ImagePicker] Using edited image: size=\(editedImage.size), scale=\(editedImage.scale)")
                parent.image = editedImage
            } else if let originalImage = info[.originalImage] as? UIImage {
                print("[ImagePicker] Using original image: size=\(originalImage.size), scale=\(originalImage.scale)")
                parent.image = originalImage
            } else {
                print("[ImagePicker] ❌ No valid image found in picker response")
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            print("[ImagePicker] Picker cancelled")
            parent.dismiss()
        }
    }
} 