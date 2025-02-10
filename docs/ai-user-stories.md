# AI User Stories Checklist

## Phase I: Project & Infrastructure Setup

### Xcode Project and Dependencies
- [x] Integrate Firebase using CocoaPods or Swift Package Manager.
  - [x] Include `FirebaseAuth` and `FirebaseFirestore`.
- [x] Decide on AWS integration:
  - [x] Use presigned URLs for S3 uploads (no direct AWS SDK needed unless advanced features are required).

### Backend Setup

#### Node Server
- [x] Implement Firebase Admin SDK for user authentication.
  - [ ] Verify ID tokens.
- [x] Set up presigned URL generation for S3 uploads.
  - [x] Support multipart uploads if possible.
- [ ] Optionally, set up orchestration for AI tasks:
  - [ ] Integrate AWS Transcribe or other ML APIs.

#### AWS S3 Bucket
- [x] Configure S3 to store:
  - [x] Raw/unprocessed videos.
  - [x] Final composited videos.
  - [x] Transcripts (in .vtt or JSON files).

#### Firestore Data Model
- [x] Define a `videos` collection with the following fields:
  - [x] `ownerId`: string (Firebase UID)
  - [x] `rawVideoS3URL`: string
  - [x] `processedVideoS3URL`: string
  - [x] `status`: string (e.g., "uploaded", "processing", "ready")
  - [x] `captions`: object or sub-collection for different languages
  - [x] `highlightedKeywords`: array of strings
  - [x] `createdAt`: timestamp
  - [x] Additional metadata (e.g., title, description)

### Security & Auth
- [x] Implement Firebase Auth on the client.
- [x] Ensure Node server verifies ID tokens before issuing presigned URLs or starting AI jobs.
- [x] Set Firestore Security Rules to restrict video document edits to the owner.

## Phase II: Video Upload Workflow

### User Records/Selects Video on iOS
- [x] Implement video capture or selection using:
  - [x] `UIImagePickerController`, `PHPickerViewController`, or `AVCaptureSession`.
- [x] Optionally compress or encode large files.

### Request a Presigned (Multipart) URL
- [x] iOS app makes a POST request to `/generate-presigned` on the Node server.
  - [x] Include Firebase ID token in the header.
  - [x] Send file info (filename, MIME type, file size).

### Multipart Upload to S3
- [x] Use presigned details to upload video in chunks.
- [x] On success, write a new video document in Firestore:
  - [x] `ownerId = currentUser.uid`
  - [x] `rawVideoS3URL = returnedS3Path`
  - [x] `status = "uploaded"`
  - [x] `createdAt = FieldValue.serverTimestamp()`

### Trigger Server-Side AI Workflow
- [ ] Decide on automatic or user-triggered AI job queuing for:
  - [ ] Speech-to-text transcription
  - [ ] Background removal

## Phase III: AI Processing Orchestration (Server-Side)

### Speech-to-Text
- [ ] Call AWS Transcribe or similar service with the S3 path.
- [ ] Obtain and store the transcript.
- [ ] Optionally run translations for selected languages.
- [ ] Store subtitles or transcript data in S3 and Firestore.

### Green Screen Removal
- [ ] Call a background-segmentation service or run an ML pipeline.
- [ ] Compose video with a default or user-chosen background.

### AI-Generated Background Scenes
- [ ] If a text prompt is provided, generate background using AI services.
- [ ] Combine with segmented video and save final MP4 in S3.
- [ ] Update Firestore with `processedVideoS3URL` and `status = "ready"`.

### Keyword Highlighting
- [ ] Implement logic for highlighting keywords in the final VTT file.

### Queue or Serverless
- [ ] Use AWS SQS or Lambda for task processing to enable scalability.

### OpenAI Integration
- [ ] Integrate OpenAI API for generating creative text prompts for background scenes.
- [ ] Use OpenAI for advanced NLP on transcribed text to enhance language understanding.
- [ ] Implement OpenAI for keyword extraction and highlighting in transcripts.
- [ ] Set up OpenAI for content moderation to ensure compliance with guidelines.
- [ ] Enhance user interaction with OpenAI-powered chatbots or virtual assistants.

## Phase IV: Creator's Post-Processing UI on iOS

### Captions & Language Selection
- [ ] Provide UI for generating captions and selecting languages.
- [ ] Optionally automate transcription and translation.

### AI Green Screen & Custom Background
- [ ] Implement UI for applying green screen and choosing backgrounds.
- [ ] Send user choices to Node for processing.

### Progress Notifications
- [ ] Use Firestore snapshots or push notifications to update users on status changes.

## Phase V: Viewer Experience & Playback

### Fetching Final Video
- [ ] Query Firestore for videos with `status = "ready"`.
- [ ] Play final MP4 using `AVPlayerViewController`.

### Subtitles & Keyword Highlights
- [ ] Implement language selection or auto-detection for subtitles.
- [ ] Attach external subtitle tracks or overlay text manually.

### Further Edits
- [ ] Allow re-editing by storing the original video in S3.

## Phase VI: Monetization & Scalability

### Premium Tier
- [ ] Lock advanced features behind a subscription or IAP.
- [ ] Use Firebase or Apple's StoreKit for subscription tracking.

### Cost Control
- [ ] Track usage statistics in Firestore.
- [ ] Adjust queue concurrency or limit usage if needed.

### Auto-Scaling
- [ ] Host Node server on AWS with auto-scaling policies.
- [ ] Manage GPU workloads efficiently. 