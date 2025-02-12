import express from 'express'
import cors from 'cors'
import dotenv from 'dotenv'
import OpenAI from 'openai'
import { WebSocketServer } from 'ws'
import http from 'http'
import AWS from 'aws-sdk'
import fs from 'fs'
import { exec } from 'child_process'
import fetch from 'node-fetch'
import FormData from 'form-data'
import { getFirestore } from 'firebase-admin/firestore'
import exportRouter from './src/routes/export.js'
import './src/config/firebase.js'

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
const clients = new Map()

wss.on('connection', (ws, req) => {
  console.log('New WebSocket connection from:', req.headers.origin)
  
  // Handle Heroku proxy headers
  const ip = req.headers['x-forwarded-for'] || req.socket.remoteAddress
  console.log('Client IP:', ip)
  
  // Generate unique client ID
  const clientId = Date.now()
  clients.set(clientId, ws)
  
  // Send welcome message
  ws.send(JSON.stringify({
    type: 'connection',
    message: 'Connected to transcription service'
  }))
  
  ws.on('message', async (message) => {
    try {
      const data = JSON.parse(message.toString())
      console.log('Received:', data)
      
      if (data.type === 'subscribe') {
        ws.videoId = data.videoId
        ws.send(JSON.stringify({
          type: 'subscribed',
          videoId: data.videoId
        }))
      }
    } catch (error) {
      console.error('WebSocket message error:', error)
      ws.send(JSON.stringify({
        type: 'error',
        message: error.message || 'Unknown error'
      }))
    }
  })
  
  ws.on('close', () => {
    console.log('Client disconnected')
    clients.delete(clientId)
  })
  
  ws.on('error', (error) => {
    console.error('WebSocket error:', error)
    clients.delete(clientId)
  })
})

// Start server
const port = parseInt(process.env.PORT || '3001', 10)
server.listen(port, '0.0.0.0', () => {
  console.log(`\n=== Server running at http://0.0.0.0:${port} ===`)
  console.log(`WebSocket server running at ws://0.0.0.0:${port}`)
  console.log('Ready to handle requests...\n')
}) 