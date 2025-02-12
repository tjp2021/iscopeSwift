import * as functions from 'firebase-functions'
import * as admin from 'firebase-admin'
import * as ffmpeg from 'fluent-ffmpeg'
import * as os from 'os'
import * as path from 'path'
import * as fs from 'fs'
import fetch from 'node-fetch'

// Initialize admin if not already initialized
if (!admin.apps.length) {
  admin.initializeApp()
}

const db = admin.firestore()
const storage = admin.storage()
const bucket = storage.bucket()

interface ExportJob {
  id: string
  userId: string
  videoId: string
  language: string
  status: 'pending' | 'processing' | 'completed' | 'failed'
  createdAt: FirebaseFirestore.Timestamp
  updatedAt: FirebaseFirestore.Timestamp
  error?: string
  downloadUrl?: string
}

interface Video {
  id: string
  url: string
  transcriptionSegments?: Array<{
    text: string
    startTime: number
    endTime: number
  }>
}

async function downloadVideo(url: string, localPath: string): Promise<void> {
  const response = await fetch(url)
  const fileStream = fs.createWriteStream(localPath)
  await new Promise((resolve, reject) => {
    response.body.pipe(fileStream)
    response.body.on('error', reject)
    fileStream.on('finish', resolve)
  })
}

async function generateSubtitleFile(segments: Array<{ text: string, startTime: number, endTime: number }>, filePath: string): Promise<void> {
  let srtContent = ''
  segments.forEach((segment, index) => {
    const startTime = new Date(segment.startTime * 1000).toISOString().substr(11, 12).replace('.', ',')
    const endTime = new Date(segment.endTime * 1000).toISOString().substr(11, 12).replace('.', ',')
    
    srtContent += `${index + 1}\n${startTime} --> ${endTime}\n${segment.text}\n\n`
  })
  
  await fs.promises.writeFile(filePath, srtContent)
}

async function processVideo(inputPath: string, outputPath: string, subtitlePath: string): Promise<void> {
  return new Promise((resolve, reject) => {
    ffmpeg(inputPath)
      .outputOptions([
        '-vf', `subtitles=${subtitlePath}:force_style='FontSize=24,FontName=Arial,PrimaryColour=&HFFFFFF&,OutlineColour=&H000000&,Outline=2'`,
        '-c:v', 'libx264',
        '-preset', 'medium',
        '-crf', '23',
        '-c:a', 'aac',
        '-b:a', '128k'
      ])
      .on('end', () => resolve())
      .on('error', (err) => reject(err))
      .save(outputPath)
  })
}

export const processExportJob = functions.runWith({
  timeoutSeconds: 540, // 9 minutes
  memory: '2GB'
}).firestore.document('exportJobs/{jobId}').onCreate(async (snap, context) => {
  const job = snap.data() as ExportJob
  const jobRef = snap.ref
  
  try {
    // Update status to processing
    await jobRef.update({
      status: 'processing',
      updatedAt: admin.firestore.Timestamp.now()
    })
    
    // Get video data
    const videoDoc = await db.collection('videos').doc(job.videoId).get()
    if (!videoDoc.exists) {
      throw new Error('Video not found')
    }
    const video = videoDoc.data() as Video
    
    if (!video.transcriptionSegments || video.transcriptionSegments.length === 0) {
      throw new Error('No transcription segments found')
    }
    
    // Create temp directory
    const tempDir = path.join(os.tmpdir(), job.id)
    await fs.promises.mkdir(tempDir, { recursive: true })
    
    // Setup file paths
    const inputPath = path.join(tempDir, 'input.mp4')
    const subtitlePath = path.join(tempDir, 'subtitles.srt')
    const outputPath = path.join(tempDir, 'output.mp4')
    
    try {
      // Download video
      await downloadVideo(video.url, inputPath)
      
      // Generate subtitle file
      await generateSubtitleFile(video.transcriptionSegments, subtitlePath)
      
      // Process video with FFMPEG
      await processVideo(inputPath, outputPath, subtitlePath)
      
      // Upload to storage
      const outputFile = bucket.file(`exports/${job.id}/video.mp4`)
      await bucket.upload(outputPath, {
        destination: outputFile,
        metadata: {
          contentType: 'video/mp4'
        }
      })
      
      // Generate signed URL (valid for 7 days)
      const [url] = await outputFile.getSignedUrl({
        action: 'read',
        expires: Date.now() + 7 * 24 * 60 * 60 * 1000
      })
      
      // Update job as completed
      await jobRef.update({
        status: 'completed',
        downloadUrl: url,
        updatedAt: admin.firestore.Timestamp.now()
      })
      
    } finally {
      // Cleanup temp files
      await fs.promises.rm(tempDir, { recursive: true, force: true })
    }
    
  } catch (error) {
    console.error('Export job failed:', error)
    
    // Update job as failed
    await jobRef.update({
      status: 'failed',
      error: error.message,
      updatedAt: admin.firestore.Timestamp.now()
    })
  }
}) 