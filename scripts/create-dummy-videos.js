const admin = require("firebase-admin");
const serviceAccount = require("../service-account.json");

if (!admin.apps.length) {
    admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
    });
}

const db = admin.firestore();

async function createDummyVideos() {
    const userId = "atiDgqH7ChOK1uQNLEWTtG1A5cl2";
    console.log("Using user ID:", userId);

    // Create 5 dummy videos
    const dummyVideos = [
        {
            title: "My First Test Video",
            description: "Testing the creator dashboard with this video",
            videoUrl: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4",
            creatorId: userId,
            createdAt: new Date(),
            likeCount: 42,
            commentCount: 7,
            viewCount: 156,
            isLiked: false
        },
        {
            title: "Second Demo Video",
            description: "Another test video for the dashboard",
            videoUrl: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
            creatorId: userId,
            createdAt: new Date(Date.now() - 86400000), // 1 day ago
            likeCount: 89,
            commentCount: 12,
            viewCount: 445,
            isLiked: false
        },
        {
            title: "Popular Test Video",
            description: "This one has lots of engagement",
            videoUrl: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4",
            creatorId: userId,
            createdAt: new Date(Date.now() - 172800000), // 2 days ago
            likeCount: 1337,
            commentCount: 42,
            viewCount: 9001,
            isLiked: false
        },
        {
            title: "New Upload Test",
            description: "Fresh upload for testing",
            videoUrl: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4",
            creatorId: userId,
            createdAt: new Date(Date.now() - 3600000), // 1 hour ago
            likeCount: 5,
            commentCount: 2,
            viewCount: 25,
            isLiked: false
        },
        {
            title: "Dashboard Test Video",
            description: "Final test video for the dashboard",
            videoUrl: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4",
            creatorId: userId,
            createdAt: new Date(Date.now() - 432000000), // 5 days ago
            likeCount: 234,
            commentCount: 18,
            viewCount: 567,
            isLiked: false
        }
    ];

    for (const video of dummyVideos) {
        await db.collection("videos").add(video);
        console.log("Created video:", video.title);
    }

    console.log("All dummy videos created successfully!");
}

createDummyVideos().catch(console.error); 