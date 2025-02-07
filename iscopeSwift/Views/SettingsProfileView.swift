import SwiftUI
import FirebaseAuth

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
                        // TODO: Implement password change
                    }
                }
                
                Section {
                    #if DEBUG
                    Button {
                        Task {
                            print("[SettingsProfileView] Generating test data")
                            await viewModel.seedTestData()
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
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(image: $profileImage)
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                if let user = Auth.auth().currentUser {
                    email = user.email ?? ""
                    // TODO: Fetch username and profile picture from Firestore
                }
            }
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