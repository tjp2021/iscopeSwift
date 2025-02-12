import { Router } from 'express'
import AWS from 'aws-sdk'
import ffmpeg from 'fluent-ffmpeg'
import * as os from 'os'
import * as path from 'path'
import * as fs from 'fs'
import fetch from 'node-fetch'
import { db } from '../config/firebase.js'
import { QueueManager } from '../queues/QueueManager.js'

// Initialize AWS S3
const s3 = new AWS.S3({
  accessKeyId: process.env.AWS_ACCESS_KEY_ID,
  secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
  region: process.env.AWS_REGION
})

const router = Router()
const queueManager = QueueManager.getInstance()

// Helper functions
async function downloadVideo(url: string, localPath: string): Promise<void> {
  const response = await fetch(url)
  const fileStream = fs.createWriteStream(localPath)
  await new Promise<void>((resolve, reject) => {
    response.body.pipe(fileStream)
    response.body.on('error', (err: Error) => reject(err))
    fileStream.on('finish', () => resolve())
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
  return new Promise<void>((resolve, reject) => {
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
      .on('error', (err: Error) => reject(err))
      .save(outputPath)
  })
}

// Process export job endpoint
router.post('/process/:jobId', async (req, res) => {
  const { jobId } = req.params
  const { videoId, language } = req.body
  
  try {
    // Validate input
    if (!videoId || !language) {
      return res.status(400).json({ error: 'Missing required fields' })
    }

    // Check if video exists
    const videoDoc = await db.collection('videos').doc(videoId).get()
    if (!videoDoc.exists) {
      return res.status(404).json({ error: 'Video not found' })
    }

    // Add job to queue
    const job = await queueManager.addExportJob({
      jobId,
      videoId,
      language
    })

    // Return job details
    res.json({
      status: 'queued',
      jobId: job.id,
      queueId: job.id
    })

  } catch (error: unknown) {
    console.error('Failed to queue export job:', error)
    res.status(500).json({ error: error instanceof Error ? error.message : 'Unknown error occurred' })
  }
})

// Get job status endpoint
router.get('/status/:jobId', async (req, res) => {
  const { jobId } = req.params
  
  try {
    const job = await queueManager.getExportJob(jobId)
    if (!job) {
      return res.status(404).json({ error: 'Job not found' })
    }

    const state = await job.getState()
    const progress = job.progress()

    res.json({
      jobId: job.id,
      state,
      progress,
      data: job.data,
      failedReason: job.failedReason
    })

  } catch (error: unknown) {
    console.error('Failed to get job status:', error)
    res.status(500).json({ error: error instanceof Error ? error.message : 'Unknown error occurred' })
  }
})

// Get queue status endpoint
router.get('/queue/status', async (req, res) => {
  try {
    const status = await queueManager.getQueueStatus()
    res.json(status)
  } catch (error: unknown) {
    console.error('Failed to get queue status:', error)
    res.status(500).json({ error: error instanceof Error ? error.message : 'Unknown error occurred' })
  }
})

export default router 