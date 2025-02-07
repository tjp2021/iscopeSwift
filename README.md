# iScope Swift

A video sharing platform built with SwiftUI and Firebase.

## Features

- User authentication with Firebase Auth
- Video upload and streaming
- Profile management
- Video engagement (likes, comments, views)
- Real-time updates
- AWS S3 integration for media storage

## Setup

1. Clone the repository
```bash
git clone https://github.com/yourusername/iscopeSwift.git
cd iscopeSwift
```

2. Install Node.js dependencies for the server
```bash
cd server
npm install
```

3. Set up environment variables
- Create a `.env` file in the server directory with:
```
AWS_ACCESS_KEY_ID=your_aws_key
AWS_SECRET_ACCESS_KEY=your_aws_secret
```

4. Add your `GoogleService-Info.plist` to the iOS project

5. Run the server
```bash
node server.js
```

6. Open the Xcode project and run the app

## Architecture

- SwiftUI for the UI layer
- MVVM architecture
- Firebase for backend services
- AWS S3 for media storage
- Node.js server for S3 pre-signed URLs

## Requirements

- iOS 15.0+
- Xcode 14.0+
- Node.js 14.0+
- Firebase account
- AWS account 