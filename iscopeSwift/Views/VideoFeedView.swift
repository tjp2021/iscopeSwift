import SwiftUI
import FirebaseFirestore
import AVKit
import Combine

struct VideoFeedView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @EnvironmentObject private var viewModel: VideoFeedViewModel
    @State private var showingUploadSheet = false
    @State private var showingMyVideosSheet = false
    @State private var showingSettingsSheet = false
    @State private var showError = false
    @State private var currentIndex = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach($viewModel.videos) { $video in
                            VideoPageView(video: $video, viewModel: viewModel)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .id(video.id)
                        }
                        
                        if viewModel.isLoadingMore {
                            ProgressView()
                                .tint(.white)
                                .frame(height: 44)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .background(Color.black)
                .refreshable {
                    await viewModel.refreshVideos()
                }
                .onChange(of: currentIndex) { _, newValue in
                    if newValue == viewModel.videos.count - 2 {
                        Task {
                            await viewModel.fetchMoreVideos()
                        }
                    }
                }
                
                if viewModel.videos.isEmpty && !viewModel.isRefreshing {
                    VStack(spacing: 16) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.white)
                        Text("No videos available")
                            .font(.headline)
                            .foregroundColor(.white)
                        Button("Refresh") {
                            Task {
                                await viewModel.refreshVideos()
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }
                }
                
                if viewModel.isRefreshing {
                    ProgressView()
                        .tint(.white)
                }
                
                // Settings gear icon in top-right corner
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            showingSettingsSheet = true
                        } label: {
                            Image(systemName: "gear")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .padding(.top, 50)
                        .padding(.trailing, 16)
                    }
                    Spacer()
                }
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showingUploadSheet) {
            UploadVideoView()
        }
        .sheet(isPresented: $showingMyVideosSheet) {
            MyVideosView()
        }
        .sheet(isPresented: $showingSettingsSheet) {
            SettingsProfileView(authViewModel: authViewModel)
        }
        .task {
            print("[VideoFeedView] Task started - Fetching videos")
            await viewModel.fetchVideos()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.error ?? "An unknown error occurred")
        }
        .onAppear {
            print("[VideoFeedView] View appeared")
        }
        .onDisappear {
            print("[VideoFeedView] View disappeared")
        }
    }
} 
