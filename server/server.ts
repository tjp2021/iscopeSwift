import express from 'express'
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

console.log('Starting server initialization...')

// Load environment variables
dotenv.config()
console.log('Environment variables loaded')

const db = getFirestore()

// Verify OpenAI API key
if (!process.env.OPENAI_API_KEY) {
    console.error('❌ OPENAI_API_KEY is not set in environment variables')
    process.exit(1)
}

// Initialize AWS
console.log('Initializing AWS S3...')
const s3 = new AWS.S3({
    accessKeyId: process.env.AWS_ACCESS_KEY_ID,
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
    region: 'us-east-2'
})
console.log('AWS S3 initialized')

// Initialize OpenAI client
console.log('Initializing OpenAI client...')
const openai = new OpenAI({
    apiKey: process.env.OPENAI_API_KEY,
    maxRetries: 5,
    timeout: 180000, // 3 minutes timeout
})

// Verify API key is valid
try {
    console.log('Verifying OpenAI API key...')
    console.log('API Key type:', process.env.OPENAI_API_KEY.startsWith('sk-proj-') ? 'Project Key' : 'Standard Key')
    
    const modelList = await openai.models.list()
    console.log('Available models:', modelList.data.map(model => model.id).join(', '))
    console.log('✅ OpenAI API key verified successfully')
} catch (error) {
    console.error('❌ Failed to verify OpenAI API key')
    console.error('Error type:', error instanceof Error ? error.constructor.name : typeof error)
    console.error('Error message:', error instanceof Error ? error.message : String(error))
    process.exit(1)
}

console.log('OpenAI client initialized')

// Initialize Express app
const app = express()
app.use(cors())
app.use(express.json())

// Add routes
app.use('/api/export', exportRouter)

// Create HTTP server with Express
const server = http.createServer(app)

// Initialize WebSocket server
const wss = new WebSocketServer({ server })

// Store active connections
const clients = new Map<number, WebSocket & { videoId?: string }>()

wss.on('connection', (ws: WebSocket) => {
    console.log('New WebSocket connection')
    
    // Generate unique client ID
    const clientId = Date.now()
    clients.set(clientId, ws as WebSocket & { videoId?: string })
    
    // Send welcome message
    ws.send(JSON.stringify({
        type: 'connection',
        message: 'Connected to transcription service'
    }))
    
    ws.on('message', async (message: Buffer | string) => {
        try {
            const data = JSON.parse(message.toString())
            console.log('Received:', data)
            
            if (data.type === 'subscribe') {
                // Store videoId with client connection
                const typedWs = ws as WebSocket & { videoId?: string }
                typedWs.videoId = data.videoId
                ws.send(JSON.stringify({
                    type: 'subscribed',
                    videoId: data.videoId
                }))
            }
        } catch (error) {
            console.error('WebSocket message error:', error)
            ws.send(JSON.stringify({
                type: 'error',
                message: error instanceof Error ? error.message : 'Unknown error'
            }))
        }
    })
    
    ws.on('close', () => {
        console.log('Client disconnected')
        clients.delete(clientId)
    })
    
    ws.on('error', (error: Error) => {
        console.error('WebSocket error:', error)
        clients.delete(clientId)
    })
})

// Function to broadcast transcription progress
function broadcastTranscriptionProgress(videoId: string, progress: number) {
    for (const [_, ws] of clients) {
        if (ws.videoId === videoId) {
            ws.send(JSON.stringify({
                type: 'progress',
                videoId: videoId,
                progress: progress
            }))
        }
    }
}

// Helper function to compress video using FFmpeg
async function compressVideo(inputBuffer: Buffer): Promise<Buffer> {
    console.log('\n🎬 Starting video compression with FFmpeg...')
    
    // Create temporary input and output files
    const inputPath = `/tmp/input-${Date.now()}.mp4`
    const outputPath = `/tmp/output-${Date.now()}.mp4`
    
    try {
        // Write input buffer to temporary file
        console.log('Writing input buffer to temporary file...')
        await fs.promises.writeFile(inputPath, inputBuffer)
        
        // OpenAI has a 25MB file size limit
        const MAX_FILE_SIZE = 25 * 1024 * 1024 // 25MB in bytes
        const inputSize = inputBuffer.length
        
        // Calculate target bitrate based on input size
        const targetSize = Math.min(20 * 1024 * 1024, inputSize)
        const durationSeconds = 600 // Assume max 10 minutes
        const targetBitrate = Math.floor((targetSize * 8) / durationSeconds)
        
        // Prepare FFmpeg command
        const ffmpegCommand = `ffmpeg -i ${inputPath} -c:v libx264 -preset medium -crf 23 -maxrate ${targetBitrate}k -bufsize ${targetBitrate*2}k -c:a aac -b:a 64k ${outputPath}`
        console.log('Running FFmpeg command:', ffmpegCommand)
        
        // Execute FFmpeg command
        await new Promise<void>((resolve, reject) => {
            exec(ffmpegCommand, (error) => {
                if (error) {
                    console.error('FFmpeg error:', error)
                    reject(error)
                    return
                }
                resolve()
            })
        })
        
        // Read the compressed video
        console.log('Reading compressed video...')
        const compressedBuffer = await fs.promises.readFile(outputPath)
        
        // Verify the compressed size
        if (compressedBuffer.length > MAX_FILE_SIZE) {
            throw new Error(`Compressed file size (${compressedBuffer.length} bytes) exceeds OpenAI's limit of ${MAX_FILE_SIZE} bytes`)
        }
        
        // Clean up temporary files
        await fs.promises.unlink(inputPath)
        await fs.promises.unlink(outputPath)
        
        console.log('✅ Video compression complete')
        return compressedBuffer
    } catch (error) {
        // Clean up on error
        try {
            await fs.promises.unlink(inputPath)
            await fs.promises.unlink(outputPath)
        } catch {}
        throw error
    }
}

// Helper function to create form data
async function createFormDataWithFile(buffer: Buffer, filename = 'video.mp4'): Promise<FormData> {
    const formData = new FormData()
    formData.append('file', buffer, { filename })
    formData.append('model', 'whisper-1')
    formData.append('language', 'en')
    formData.append('response_format', 'verbose_json')
    formData.append('timestamp_granularity', 'word')
    return formData
}

// Helper function to stream file to OpenAI
async function streamFileToOpenAI(formData: FormData) {
    const response = await fetch('https://api.openai.com/v1/audio/transcriptions', {
        method: 'POST',
        headers: {
            'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`,
            ...formData.getHeaders()
        },
        body: formData,
        timeout: 300000 // 5 minutes
    })

    if (!response.ok) {
        const text = await response.text()
        console.error('OpenAI API Error Response:', text)
        throw new Error(`OpenAI API error: ${response.status} ${text}`)
    }

    const result = await response.json()
    console.log('\nOpenAI Response Format:', Object.keys(result).join(', '))
    return result
}

// Helper function to retry failed requests
async function retryWithBackoff<T>(operation: () => Promise<T>, maxRetries = 5): Promise<T> {
    for (let i = 0; i < maxRetries; i++) {
        try {
            return await operation()
        } catch (error) {
            if (i === maxRetries - 1) throw error
            
            // Log retry attempt
            console.log(`Attempt ${i + 1} failed, retrying in ${Math.pow(2, i)} seconds...`)
            console.error('Error:', error instanceof Error ? error.message : String(error))
            
            // Exponential backoff
            await new Promise(resolve => setTimeout(resolve, Math.pow(2, i) * 1000))
        }
    }
    throw new Error('Max retries exceeded')
}

// Process transcription
async function processTranscription(videoUrl: string, videoId: string) {
    try {
        console.log('\n=== Starting Transcription Process for Video ID:', videoId, '===')
        
        // Send initial progress
        broadcastTranscriptionProgress(videoId, 0)
        
        // Fetch and process video
        const videoResponse = await fetch(videoUrl)
        if (!videoResponse.ok) {
            throw new Error(`Failed to fetch video: ${videoResponse.statusText}`)
        }
        
        const buffer = await videoResponse.arrayBuffer()
        const compressedBuffer = await compressVideo(Buffer.from(buffer))
        
        broadcastTranscriptionProgress(videoId, 0.5)
        
        // Create form data and send to OpenAI
        const formData = await createFormDataWithFile(compressedBuffer)
        console.log('📡 Sending request to OpenAI with timestamp_granularities enabled')
        
        const transcription = await retryWithBackoff(async () => {
            return await streamFileToOpenAI(formData)
        })
        
        // Process segments and words
        const segments = transcription.segments.map((segment: any) => ({
            text: segment.text,
            startTime: segment.start,
            endTime: segment.end,
            ...(segment.words && {
                words: segment.words.map((word: any) => ({
                    text: word.text,
                    startTime: word.start,
                    endTime: word.end
                }))
            })
        }))
        
        // Update Firestore
        await db.collection('videos').doc(videoId).update({
            transcriptionStatus: 'completed',
            transcriptionText: transcription.text,
            transcriptionSegments: segments
        })
        
        broadcastTranscriptionProgress(videoId, 1)
        
        return {
            text: transcription.text,
            segments: segments
        }
    } catch (error) {
        console.error('\n❌ Transcription Error:', error instanceof Error ? error.message : String(error))
        
        // Update Firestore with failed status
        try {
            await db.collection('videos').doc(videoId).update({
                transcriptionStatus: 'failed',
                transcriptionText: null,
                transcriptionSegments: null
            })
        } catch (updateError) {
            console.error('Failed to update error status:', updateError)
        }
        
        throw error
    }
}

// Add translation endpoint
app.post('/translate', async (req, res) => {
    console.log('Handling translation request')
    try {
        const { text, targetLanguage } = req.body
        console.log(`Translating to ${targetLanguage}:`, text)

        const completion = await openai.chat.completions.create({
            model: "gpt-4",
            messages: [
                {
                    role: "system",
                    content: `You are a professional translator. Translate the following text to ${targetLanguage}. Maintain the original formatting and tone.`
                },
                {
                    role: "user",
                    content: text
                }
            ],
            stream: false
        })

        const translation = completion.choices[0].message.content
        
        // Add timestamp as milliseconds
        const translationData = {
            translation: translation,
            status: "completed",
            timestamp: Date.now()
        }
        
        res.json(translationData)
    } catch (error) {
        console.error('Translation error:', error)
        res.status(500).json({ 
            error: 'Translation failed',
            details: error instanceof Error ? error.message : 'Unknown error',
            timestamp: Date.now()
        })
    }
})

// Add helper function to convert Firestore timestamps
function convertTimestamps(obj: any): any {
    if (obj === null || typeof obj !== 'object') {
        return obj
    }

    if (obj instanceof Date) {
        return obj.getTime()
    }

    if (obj.constructor.name === 'Timestamp') {
        return obj.toMillis()
    }

    if (Array.isArray(obj)) {
        return obj.map(convertTimestamps)
    }

    const converted: any = {}
    for (const key in obj) {
        if (Object.prototype.hasOwnProperty.call(obj, key)) {
            converted[key] = convertTimestamps(obj[key])
        }
    }
    return converted
}

// Add route to get updated video data
app.get('/video/:videoId', async (req, res) => {
    try {
        const { videoId } = req.params
        const docSnapshot = await db.collection('videos').doc(videoId).get()
        
        if (!docSnapshot.exists) {
            res.status(404).json({ error: 'Video not found' })
            return
        }

        // Convert timestamps in the data
        const data = convertTimestamps(docSnapshot.data())
        res.json(data)
    } catch (error) {
        console.error('Error fetching video:', error)
        res.status(500).json({
            error: 'Failed to fetch video',
            details: error instanceof Error ? error.message : 'Unknown error'
        })
    }
})

// Start server
const port = parseInt(process.env.PORT || '3001', 10)
server.listen(port, '0.0.0.0', () => {
    console.log(`\n=== Server running at http://0.0.0.0:${port} ===`)
    console.log(`WebSocket server running at ws://0.0.0.0:${port}`)
    console.log('Ready to handle requests...\n')
}) 