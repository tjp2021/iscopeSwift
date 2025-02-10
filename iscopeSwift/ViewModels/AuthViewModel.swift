import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var errorMessage: String?
    private var handle: AuthStateDidChangeListenerHandle?
    private var appState: AppState
    
    init(appState: AppState) {
        print("[Auth] Initializing AuthViewModel")
        self.appState = appState
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.isAuthenticated = user != nil
                self?.currentUser = user
                self?.appState.authState.isAuthenticated = user != nil
                self?.appState.authState.currentUser = user
            }
        }
    }
    
    deinit {
        if let handle = handle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
    
    func signIn(email: String, password: String) async throws {
        print("[Auth] Attempting sign in for email: \(email)")
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            print("[Auth] Sign in successful for user: \(result.user.uid)")
            // State will be updated by the auth state listener
        } catch {
            print("[Auth] Sign in failed: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
            throw error
        }
    }
    
    func createAccount(email: String, password: String) async throws {
        print("[Auth] Attempting to create account for email: \(email)")
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            print("[Auth] Account created successfully for user: \(result.user.uid)")
            
            // Create user document in Firestore
            print("[Auth] Creating Firestore document for user: \(result.user.uid)")
            let db = Firestore.firestore()
            try await db.collection("users").document(result.user.uid).setData([
                "email": email,
                "created_at": Date()
            ])
            print("[Auth] Firestore document created successfully for user: \(result.user.uid)")
            // State will be updated by the auth state listener
        } catch {
            print("[Auth] Account creation failed: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
            throw error
        }
    }
    
    func signOut() throws {
        print("[Auth] Attempting to sign out")
        do {
            try Auth.auth().signOut()
            print("[Auth] Sign out successful")
            // State will be updated by the auth state listener
        } catch {
            print("[Auth] Sign out failed: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
            throw error
        }
    }
} 