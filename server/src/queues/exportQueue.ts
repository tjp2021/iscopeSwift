import Queue from 'bull'
import { processVideoJob } from '../services/videoProcessor.js'
import { db } from '../config/firebase.js'
import { Storage } from '@google-cloud/storage'
import path from 'path'
import os from 'os'
import fs from 'fs'

const storage = new Storage()
const bucket = storage.bucket(process.env.FIREBASE_STORAGE_BUCKET!)

interface ExportJobData {
  jobId: string
  videoId: string
  language: string
}

// Create export queue
const exportQueue = new Queue<ExportJobData>('video-export', {
  redis: {
    host: process.env.REDIS_HOST || 'localhost',
    port: parseInt(process.env.REDIS_PORT || '6379')
  }
})

// Process jobs
exportQueue.process(async (job) => {
  const { jobId, videoId, language } = job.data
  const jobRef = db.collection('exportJobs').doc(jobId)
  
  try {
    // Update status to processing
    await jobRef.update({
      status: 'processing',
      updatedAt: new Date()
    })
    
    // Get video data
    const videoDoc = await db.collection('videos').doc(videoId).get()
    if (!videoDoc.exists) {
      throw new Error('Video not found')
    }
    const video = videoDoc.data()!
    
    // Get the correct segments based on language
    const segments = language === 'en' 
      ? video.transcriptionSegments 
      : video.translations?.[language]?.segments
    
    if (!segments || segments.length === 0) {
      throw new Error(`No segments found for language: ${language}`)
    }
    
    // Get the export job to access caption settings
    const jobDoc = await jobRef.get()
    if (!jobDoc.exists) {
      throw new Error('Export job not found')
    }
    const exportJob = jobDoc.data()!
    
    // Process the video with the correct segments
    const outputPath = await processVideoJob(job)
    
    // Upload to storage
    const outputFile = bucket.file(`exports/${jobId}/video.mp4`)
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
      updatedAt: new Date()
    })
    
    return { status: 'success', downloadUrl: url }
    
  } catch (error) {
    console.error('Export job failed:', error)
    
    // Update job as failed
    await jobRef.update({
      status: 'failed',
      error: error instanceof Error ? error.message : 'Unknown error occurred',
      updatedAt: new Date()
    })
    
    throw error
  }
})

// Add job to queue
export async function queueExportJob(jobId: string, videoId: string, language: string) {
  return exportQueue.add({
    jobId,
    videoId,
    language
  }, {
    attempts: 3,
    backoff: {
      type: 'exponential',
      delay: 1000
    }
  })
}

// Monitor queue events
exportQueue.on('completed', (job) => {
  console.log(`Job ${job.id} completed for video export ${job.data.jobId}`)
})

exportQueue.on('failed', (job, error) => {
  console.error(`Job ${job.id} failed for video export ${job.data.jobId}:`, error)
})

exportQueue.on('progress', (job, progress) => {
  console.log(`Job ${job.id} is ${progress}% done`)
})

export default exportQueue 