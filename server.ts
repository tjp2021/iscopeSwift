import express, { Request, Response } from 'express'
import cors from 'cors'
import dotenv from 'dotenv'
import OpenAI from 'openai'
import { WebSocketServer, WebSocket } from 'ws'
import http from 'http'
import AWS from 'aws-sdk'
import fs from 'fs'
import { exec } from 'child_process'
import fetch from 'node-fetch'
import FormData from 'form-data'
import { getFirestore } from 'firebase-admin/firestore'
import exportRouter from './src/routes/export.js'
import './src/config/firebase.js'  // Import Firebase config

// Load environment variables
dotenv.config()
console.log('Environment variables loaded')

// Initialize Express app
const app = express()

// Configure CORS with proper origin handling
const corsOptions = {
  origin: '*', // Allow all origins since this is a mobile app
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: true
}

app.use(cors(corsOptions))
app.use(express.json())

// Add routes
app.use('/api/export', exportRouter)

// Generate presigned URL endpoint
app.post('/generate-presigned-url', async (req: Request, res: Response) => {
    try {
        const { fileName, contentType, isProfile } = req.body

        if (!fileName || !contentType) {
            return res.status(400).json({ error: 'Missing required fields' })
        }

        // Determine the S3 key based on the type
        const key = isProfile ? `profiles/${fileName}` : `videos/${fileName}`

        // Generate upload URL (expires in 5 minutes)
        const uploadURL = s3.getSignedUrl('putObject', {
            Bucket: process.env.AWS_S3_BUCKET,
            Key: key,
            Expires: 300, // 5 minutes
            ContentType: contentType
        })

        // Generate download URL (expires in 7 days)
        const downloadURL = s3.getSignedUrl('getObject', {
            Bucket: process.env.AWS_S3_BUCKET,
            Key: key,
            Expires: 7 * 24 * 60 * 60 // 7 days
        })

        res.json({
            uploadURL,
            downloadURL,
            key,
            imageKey: key,
            videoKey: key
        })
    } catch (error) {
        console.error('Error generating presigned URL:', error)
        res.status(500).json({ error: error instanceof Error ? error.message : 'Unknown error' })
    }
})

// Create HTTP server with Express
const server = http.createServer(app)

// Initialize WebSocket server with proper configuration for Heroku
const wss = new WebSocketServer({ 
  server,
  clientTracking: true,
  perMessageDeflate: {
    zlibDeflateOptions: {
      chunkSize: 1024,
      memLevel: 7,
      level: 3
    },
    zlibInflateOptions: {
      chunkSize: 10 * 1024
    }
  }
})

// Store active connections
const clients = new Map<number, WebSocket & { videoId?: string }>()

wss.on('connection', (ws: WebSocket, req: http.IncomingMessage) => {
  console.log('New WebSocket connection from:', req.headers.origin)
  
  // Handle Heroku proxy headers
  const ip = req.headers['x-forwarded-for'] || req.socket.remoteAddress
  console.log('Client IP:', ip)
  
  // Generate unique client ID
  const clientId = Date.now()
  clients.set(clientId, ws as WebSocket & { videoId?: string })
  
  // Send welcome message
  ws.send(JSON.stringify({
    type: 'connection',
    message: 'Connected to transcription service'
  }))
  
  // ... rest of the existing WebSocket code ...
}) 