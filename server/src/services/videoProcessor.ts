import * as os from 'os'
import * as path from 'path'
import * as fs from 'fs'
import ffmpeg from 'fluent-ffmpeg'
import fetch from 'node-fetch'
import { Job } from 'bull'
import AWS from 'aws-sdk'
import { db } from '../config/firebase.js'

interface ExportJobData {
  jobId: string
  videoId: string
  language: string
}

interface ExportJob {
    id: string
    userId: string
    videoId: string
    language: string
    status: string
    createdAt: Date
    updatedAt: Date
    error?: string
    downloadUrl?: string
    progress?: number
    captionSettings: {
        fontSize: number
        captionColor: string
        verticalPosition: number
    }
    segments: Array<{ text: string, startTime: number, endTime: number }>
}

// Configure AWS
const s3 = new AWS.S3({
  accessKeyId: process.env.AWS_ACCESS_KEY_ID,
  secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
  region: process.env.AWS_REGION
})

// Helper function to update job progress in Firestore
async function updateJobProgress(jobId: string, progress: number) {
  await db.collection('exportJobs').doc(jobId).update({
    progress,
    updatedAt: new Date()
  })
}

// Helper function to update job status in Firestore
async function updateJobStatus(jobId: string, status: string) {
  await db.collection('exportJobs').doc(jobId).update({
    status,
    updatedAt: new Date()
  })
}

export async function downloadVideo(url: string, localPath: string): Promise<void> {
  const response = await fetch(url)
  const fileStream = fs.createWriteStream(localPath)
  await new Promise<void>((resolve, reject) => {
    response.body.pipe(fileStream)
    response.body.on('error', (err: Error) => reject(err))
    fileStream.on('finish', () => resolve())
  })
}

export async function generateSubtitleFile(segments: Array<{ text: string, startTime: number, endTime: number }>, filePath: string): Promise<void> {
  let srtContent = ''
  segments.forEach((segment, index) => {
    const startTime = new Date(segment.startTime * 1000).toISOString().substr(11, 12).replace('.', ',')
    const endTime = new Date(segment.endTime * 1000).toISOString().substr(11, 12).replace('.', ',')
    
    srtContent += `${index + 1}\n${startTime} --> ${endTime}\n${segment.text}\n\n`
  })
  
  await fs.promises.writeFile(filePath, srtContent)
}

async function processVideo(jobId: string, videoPath: string, subtitlePath: string, outputPath: string, job?: Job) {
    console.log(`[DEBUG] Processing video with job ID: ${jobId}`)
    
    try {
        // Get the export job from Firestore
        const jobDoc = await db.collection('exportJobs').doc(jobId).get()
        if (!jobDoc.exists) {
            throw new Error('Export job not found')
        }
        const exportJob = jobDoc.data() as ExportJob
        
        // Return a promise that resolves when FFmpeg is done
        return new Promise<void>((resolve, reject) => {
            console.log('[DEBUG] Starting FFmpeg processing...')
            console.log('[DEBUG] Input path:', videoPath)
            console.log('[DEBUG] Subtitle path:', subtitlePath)
            console.log('[DEBUG] Output path:', outputPath)
            console.log('[DEBUG] Caption settings:', exportJob.captionSettings)
            
            // Escape special characters in the subtitle path
            const escapedSubtitlePath = subtitlePath.replace(/[\\:]/g, '\\$&')
            
            // Create the subtitle filter with escaped values and EXACT app styling
            const subtitleFilter = `subtitles=${escapedSubtitlePath}:force_style='` +
                `Fontsize=${exportJob.captionSettings.fontSize * 0.8},` + // Reduced scaling to match app view
                `FontName=Arial,` +
                `PrimaryColour=${exportJob.captionSettings.captionColor},` + // Color in ASS format from app
                `BackColour=&HE0000000,` + // Increased opacity (E0 = 88% opacity)
                `BorderStyle=3,` + // Opaque box style
                `Outline=0,` + // No outline
                `Shadow=0,` + // No shadow
                `Alignment=2,` + // Center alignment (2=bottom-center, 8=top-center)
                `MarginV=${Math.round((1 - exportJob.captionSettings.verticalPosition) * 100)}'` // Invert position for bottom-up calculation
            
            ffmpeg(videoPath)
                .outputOptions([
                    '-vf', subtitleFilter,
                    '-c:v', 'libx264',
                    '-preset', 'medium',
                    '-crf', '23',
                    '-c:a', 'aac',
                    '-b:a', '128k'
                ])
                .on('start', (commandLine) => {
                    console.log('[DEBUG] FFmpeg command:', commandLine)
                })
                .on('progress', (progress) => {
                    if (job && typeof progress.percent === 'number') {
                        const percent = Math.round(progress.percent)
                        console.log(`[DEBUG] Processing progress: ${percent}%`)
                        job.progress(percent)
                        updateJobProgress(jobId, percent).catch(console.error)
                    }
                })
                .on('end', () => {
                    console.log('[DEBUG] FFmpeg processing completed')
                    resolve()
                })
                .on('error', (err) => {
                    console.error('[ERROR] FFmpeg error:', err)
                    reject(err)
                })
                .save(outputPath)
        })
    } catch (error: unknown) {
        console.error('Export job failed:', error)
        
        // Update job as failed
        await updateJobStatus(jobId, 'failed')
        await db.collection('exportJobs').doc(jobId).update({
          error: error instanceof Error ? error.message : 'Unknown error occurred'
        })
        
        throw error
    }
}

export async function processVideoJob(job: Job<ExportJobData>): Promise<string> {
  // Get video data from Firestore
  const videoDoc = await db.collection('videos').doc(job.data.videoId).get()
  if (!videoDoc.exists) {
    throw new Error('Video not found')
  }
  const video = videoDoc.data()
  if (!video) {
    throw new Error('Video data is empty')
  }

  // Get the export job data to access the segments
  const jobDoc = await db.collection('exportJobs').doc(job.data.jobId).get()
  if (!jobDoc.exists) {
    throw new Error('Export job not found')
  }
  const exportJob = jobDoc.data() as ExportJob
  if (!exportJob?.segments) {
    throw new Error('No segments found in export job')
  }

  // Update status to processing
  await updateJobStatus(job.data.jobId, 'processing')

  // Create temp directory
  const tempDir = path.join(os.tmpdir(), job.data.jobId)
  await fs.promises.mkdir(tempDir, { recursive: true })
  
  try {
    // Setup file paths
    const inputPath = path.join(tempDir, 'input.mp4')
    const subtitlePath = path.join(tempDir, 'subtitles.srt')
    const outputPath = path.join(tempDir, 'output.mp4')
    
    // Download video
    await downloadVideo(video.url, inputPath)
    job?.progress(10)
    await updateJobProgress(job.data.jobId, 10)
    
    // Generate subtitle file using segments from the export job
    await generateSubtitleFile(exportJob.segments, subtitlePath)
    job?.progress(20)
    await updateJobProgress(job.data.jobId, 20)
    
    // Process video with FFMPEG
    await processVideo(job.data.jobId, inputPath, subtitlePath, outputPath, job)
    job?.progress(90)
    await updateJobProgress(job.data.jobId, 90)
    
    // Upload to S3
    const fileStream = fs.createReadStream(outputPath)
    const s3Bucket = process.env.AWS_S3_BUCKET
    if (!s3Bucket) {
      throw new Error('AWS_S3_BUCKET environment variable is not set')
    }

    console.log(`[DEBUG] Uploading to S3 bucket: ${s3Bucket}`)
    console.log(`[DEBUG] File key: exports/${job.data.jobId}/video.mp4`)

    const uploadParams = {
      Bucket: s3Bucket,
      Key: `exports/${job.data.jobId}/video.mp4`,
      Body: fileStream,
      ContentType: 'video/mp4'
    }
    
    try {
      console.log('[DEBUG] Starting S3 upload...')
      const uploadResult = await s3.upload(uploadParams).promise()
      console.log('[DEBUG] S3 upload successful:', uploadResult.Location)
      
      // Verify the file exists before generating URL
      console.log('[DEBUG] Verifying file exists in S3...')
      await s3.headObject({
        Bucket: s3Bucket,
        Key: uploadParams.Key
      }).promise()
      
      job?.progress(100)
      await updateJobProgress(job.data.jobId, 100)
      
      // Generate presigned URL (valid for 24 hours)
      console.log('[DEBUG] Generating presigned URL...')
      const signedUrl = s3.getSignedUrl('getObject', {
        Bucket: s3Bucket,
        Key: uploadParams.Key,
        Expires: 86400 // 24 hours
      })
      console.log('[DEBUG] Generated signed URL:', signedUrl)

      // Update job as completed with download URL
      await db.collection('exportJobs').doc(job.data.jobId).update({
        status: 'completed',
        downloadUrl: signedUrl,
        updatedAt: new Date()
      })
      
      return signedUrl
    } catch (s3Error: unknown) {
      console.error('[ERROR] S3 operation failed:', s3Error)
      throw new Error(`S3 operation failed: ${s3Error instanceof Error ? s3Error.message : 'Unknown S3 error'}`)
    }
  } catch (error: unknown) {
    console.error('Export job failed:', error)
    
    // Update job as failed
    await updateJobStatus(job.data.jobId, 'failed')
    await db.collection('exportJobs').doc(job.data.jobId).update({
      error: error instanceof Error ? error.message : 'Unknown error occurred'
    })
    
    throw error
  } finally {
    // Clean up temp files
    await fs.promises.rm(tempDir, { recursive: true, force: true })
  }
} 