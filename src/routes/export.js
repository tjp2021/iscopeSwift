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
async function downloadVideo(url, localPath) {
  const response = await fetch(url)
  const fileStream = fs.createWriteStream(localPath)
  await new Promise((resolve, reject) => {
    response.body.pipe(fileStream)
    response.body.on('error', (err) => reject(err))
    fileStream.on('finish', () => resolve())
  })
}

export default router 