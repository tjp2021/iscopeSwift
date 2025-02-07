import SwiftUI
import FirebaseAuth

struct AuthenticationView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isCreatingAccount = false
    @FocusState private var focusedField: Field?
    @State private var isLoading = false
    
    enum Field {
        case email, password, confirmPassword
    }
    
    // MARK: - Validation Functions
    
    private func validateEmail(_ email: String) -> Bool {
        let emailRegex = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    private func validatePassword(_ password: String) -> Bool {
        // At least 6 characters
        return password.count >= 6
    }
    
    private func validateForm() -> Bool {
        // Check email
        guard !email.isEmpty else {
            alertMessage = "Please enter an email"
            showAlert = true
            return false
        }
        
        guard validateEmail(email) else {
            alertMessage = "Please enter a valid email"
            showAlert = true
            return false
        }
        
        // Check password
        guard !password.isEmpty else {
            alertMessage = "Please enter a password"
            showAlert = true
            return false
        }
        
        guard validatePassword(password) else {
            alertMessage = "Password must be at least 6 characters"
            showAlert = true
            return false
        }
        
        // Additional validation for account creation
        if isCreatingAccount {
            guard password == confirmPassword else {
                alertMessage = "Passwords do not match"
                showAlert = true
                return false
            }
        }
        
        return true
    }
    
    private func handleAuthAction() {
        guard validateForm() else { return }
        
        Task {
            isLoading = true
            do {
                if isCreatingAccount {
                    try await authViewModel.createAccount(email: email, password: password)
                    print("Successfully created account and user document")
                } else {
                    try await authViewModel.signIn(email: email, password: password)
                    print("Successfully signed in")
                }
            } catch {
                alertMessage = authViewModel.errorMessage ?? error.localizedDescription
                showAlert = true
            }
            isLoading = false
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Logo section with flexible spacing
                    Spacer(minLength: geometry.size.height * 0.1)
                    
                    Text("iScope")
                        .font(.system(size: 40, weight: .bold))
                    
                    Text(isCreatingAccount ? "Create Account" : "Sign In")
                        .font(.title2)
                        .fontWeight(.medium)
                    
                    Spacer(minLength: geometry.size.height * 0.05)
                    
                    // Input fields
                    VStack(spacing: 16) {
                        TextField("Email", text: $email)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                        
                        SecureField("Password", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .password)
                            .submitLabel(isCreatingAccount ? .next : .done)
                        
                        if isCreatingAccount {
                            SecureField("Confirm Password", text: $confirmPassword)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .confirmPassword)
                                .submitLabel(.done)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Buttons
                    VStack(spacing: 12) {
                        Button(action: handleAuthAction) {
                            HStack {
                                Text(isCreatingAccount ? "Create Account" : "Sign In")
                                    .fontWeight(.semibold)
                                if isLoading {
                                    Spacer()
                                    ProgressView()
                                        .tint(.white)
                                }
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.blue)
                            .cornerRadius(8)
                        }
                        .disabled(isLoading)
                        
                        Button(action: {
                            withAnimation {
                                isCreatingAccount.toggle()
                                // Clear fields when switching modes
                                email = ""
                                password = ""
                                confirmPassword = ""
                                focusedField = nil
                            }
                        }) {
                            Text(isCreatingAccount ? "Already have an account? Sign In" : "Create Account")
                                .foregroundColor(.blue)
                        }
                        .disabled(isLoading)
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: geometry.size.height * 0.1)
                }
                .frame(minHeight: geometry.size.height)
            }
        }
        .ignoresSafeArea(.keyboard)
        .alert("Error", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
            }
        }
    }
}

#Preview {
    AuthenticationView(authViewModel: AuthViewModel())
} 