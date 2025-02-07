import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var errorMessage: String?
    
    init() {
        print("[Auth] Initializing AuthViewModel")
        // Set up auth state listener
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            if let user = user {
                print("[Auth] Auth state changed: User authenticated - \(user.uid)")
                self?.isAuthenticated = true
                self?.currentUser = user
            } else {
                print("[Auth] Auth state changed: User signed out")
                self?.isAuthenticated = false
                self?.currentUser = nil
            }
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