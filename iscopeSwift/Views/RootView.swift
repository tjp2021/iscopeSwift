import SwiftUI
import FirebaseAuth

// App-wide state container
final class AppState: ObservableObject {
    @Published var authState: AuthState
    @Published var feedState: FeedState
    
    init(authState: AuthState = AuthState(), feedState: FeedState = FeedState()) {
        self.authState = authState
        self.feedState = feedState
    }
}

// Separate state containers for better organization
final class AuthState: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    // Other auth-related state
}

final class FeedState: ObservableObject {
    @Published var videos: [Video] = []
    @Published var error: String?
    @Published var isLoading = false
    // Other feed-related state
}

// Main app coordinator
struct RootView: View {
    @StateObject private var appState: AppState
    @StateObject private var feedViewModel = VideoFeedViewModel()
    @StateObject private var authViewModel: AuthViewModel
    
    init(appState: AppState = AppState()) {
        _appState = StateObject(wrappedValue: appState)
        _authViewModel = StateObject(wrappedValue: AuthViewModel(appState: appState))
    }
    
    var body: some View {
        Group {
            if appState.authState.isAuthenticated {
                VideoFeedView(authViewModel: authViewModel)
                .onAppear { 
                    print("[Navigation] Showing VideoFeedView - User is authenticated")
                    Task {
                        await feedViewModel.refreshVideos()
                    }
                }
            } else {
                AuthenticationView()
                    .onAppear { print("[Navigation] Showing AuthenticationView - User is not authenticated") }
            }
        }
        .environmentObject(appState)  // Provide app-wide state
        .environmentObject(authViewModel)  // Provide view models
        .environmentObject(feedViewModel)
    }
}

// Preview with mocked state
#Preview {
    RootView(appState: AppState(
        authState: AuthState(),
        feedState: FeedState()
    ))
} 