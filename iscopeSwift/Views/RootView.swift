import SwiftUI
import FirebaseAuth

struct RootView: View {
    @StateObject private var authViewModel = AuthViewModel()
    
    var body: some View {
        Group {
            if authViewModel.isAuthenticated {
                VideoFeedView(authViewModel: authViewModel)
                    .onAppear { print("[Navigation] Showing VideoFeedView - User is authenticated") }
            } else {
                AuthenticationView(authViewModel: authViewModel)
                    .onAppear { print("[Navigation] Showing AuthenticationView - User is not authenticated") }
            }
        }
        .onChange(of: authViewModel.isAuthenticated) { oldValue, newValue in
            // Handle auth state changes if needed
        }
    }
}

#Preview {
    RootView()
} 