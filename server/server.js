import http from 'http';
import OpenAI from 'openai';
import dotenv from 'dotenv';
import { Readable } from 'stream';
import AWS from 'aws-sdk';
import { WebSocketServer } from 'ws';
import fs from 'fs';
import { exec } from 'child_process';
import https from 'https';
import fetch from 'node-fetch';
import FormData from 'form-data';
import { initializeApp, applicationDefault, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

console.log('Starting server initialization...');

// Load environment variables
dotenv.config();
console.log('Environment variables loaded');

// Initialize Firebase Admin
console.log('Initializing Firebase Admin...');
initializeApp({
    credential: cert('./serviceAccountKey.json')
});
console.log('Firebase Admin initialized');

const db = getFirestore();

// Verify OpenAI API key
if (!process.env.OPENAI_API_KEY) {
    console.error('❌ OPENAI_API_KEY is not set in environment variables');
    process.exit(1);
}

// Initialize AWS
console.log('Initializing AWS S3...');
const s3 = new AWS.S3({
    accessKeyId: process.env.AWS_ACCESS_KEY_ID,
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
    region: 'us-east-2'
});
console.log('AWS S3 initialized');

// Initialize OpenAI client with additional configuration
console.log('Initializing OpenAI client...');
const openai = new OpenAI({
    apiKey: process.env.OPENAI_API_KEY,
    maxRetries: 5,
    timeout: 180000, // 3 minutes timeout
});

// Verify API key is valid with detailed error handling
try {
    console.log('Verifying OpenAI API key...');
    console.log('API Key type:', process.env.OPENAI_API_KEY.startsWith('sk-proj-') ? 'Project Key' : 'Standard Key');
    
    const modelList = await openai.models.list();
    console.log('Available models:', modelList.data.map(model => model.id).join(', '));
    console.log('✅ OpenAI API key verified successfully');
} catch (error) {
    console.error('❌ Failed to verify OpenAI API key');
    console.error('Error type:', error.constructor.name);
    console.error('Error message:', error.message);
    if (error.response) {
        console.error('Response status:', error.response.status);
        console.error('Response data:', error.response.data);
    }
    if (error.cause) {
        console.error('Error cause:', error.cause);
    }
    process.exit(1);
}

console.log('OpenAI client initialized');

// Create HTTP server
const server = http.createServer(async (req, res) => {
    console.log(`\n[${new Date().toISOString()}] Received ${req.method} request to ${req.url}`);
    
    // Parse the URL to handle paths consistently
    const parsedUrl = new URL(req.url, `http://${req.headers.host}`);
    const pathname = parsedUrl.pathname;
    
    // Add CORS headers for cross-origin requests
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

    // Test endpoint
    if (req.method === 'GET' && pathname === '/test') {
        console.log('Handling test request');
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ status: 'Server is running on port 3001' }));
        return;
    }

    // Health check endpoint
    if (req.method === 'GET' && pathname === '/health') {
        console.log('Handling health check request');
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ 
            status: 'healthy',
            openai: true,
            firebase: true,
            s3: true
        }));
        return;
    }

    // Handle OPTIONS request for CORS preflight
    if (req.method === 'OPTIONS') {
        console.log('Handling CORS preflight request');
        res.writeHead(204);
        res.end();
        return;
    }

    // Handle presigned URL generation
    if (req.method === 'POST' && pathname === '/generate-presigned-url') {
        console.log('Handling presigned URL generation request');
        try {
            let body = '';
            req.on('data', chunk => {
                body += chunk.toString();
            });

            req.on('end', async () => {
                try {
                    console.log('Request body:', body);
                    const { fileName } = JSON.parse(body);
                    console.log('Generating presigned URL for file:', fileName);
                    
                    const videoKey = `videos/${Date.now()}-${fileName}`;
                    console.log('Generated video key:', videoKey);
                    
                    const params = {
                        Bucket: 'iscope',
                        Key: videoKey,
                        Expires: 60 * 5,
                        ContentType: 'video/mp4'
                    };
                    console.log('S3 params:', params);

                    const uploadURL = s3.getSignedUrl('putObject', params);
                    const downloadURL = s3.getSignedUrl('getObject', {
                        Bucket: 'iscope',
                        Key: videoKey,
                        Expires: 60 * 60 * 24 * 7 // 7 days
                    });
                    
                    const responseBody = { 
                        uploadURL: uploadURL,
                        videoKey: videoKey,
                        downloadURL: downloadURL
                    };
                    console.log('Sending response:', JSON.stringify(responseBody, null, 2));
                    
                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify(responseBody));
                    console.log('Successfully sent presigned URL response');
                } catch (error) {
                    console.error('Presigned URL error:', error);
                    console.error('Error stack:', error.stack);
                    res.writeHead(500, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ 
                        error: 'Failed to generate presigned URL',
                        details: error.message 
                    }));
                }
            });
            return;
        } catch (error) {
            console.error('Request handling error:', error);
            console.error('Error stack:', error.stack);
            res.writeHead(400, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: 'Invalid request' }));
            return;
        }
    }

    // Handle upload complete endpoint
    if (req.method === 'POST' && pathname === '/start-transcription') {
        console.log('Handling transcription request');
        try {
            let body = '';
            req.on('data', chunk => {
                body += chunk.toString();
            });

            req.on('end', async () => {
                let videoId;
                try {
                    console.log('Request body:', body);
                    const parsedBody = JSON.parse(body);
                    videoId = parsedBody.videoId;
                    console.log('Processing transcription for videoId:', videoId);
                    
                    // Set initial transcription status
                    await db.collection('videos').doc(videoId).update({
                        transcriptionStatus: 'pending',
                        transcriptionText: null,
                        transcriptionSegments: null
                    });
                    
                    // Get the video document to use the stored download URL
                    const videoDoc = await db.collection('videos').doc(videoId).get();
                    if (!videoDoc.exists) {
                        throw new Error('Video document not found');
                    }
                    
                    const videoData = videoDoc.data();
                    const downloadURL = videoData.url;
                    
                    console.log('Using download URL for transcription:', downloadURL);
                    
                    // Use the download URL for transcription
                    const transcription = await processTranscription(downloadURL, videoId);
                    
                    // Update Firestore with completed transcription
                    await db.collection('videos').doc(videoId).update({
                        transcriptionStatus: 'completed',
                        transcriptionText: transcription.text,
                        transcriptionSegments: transcription.segments
                    });

                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ 
                        jobId: videoId,
                        status: "completed",
                        transcriptUrl: downloadURL,
                        text: transcription.text,
                        segments: transcription.segments
                    }));
                    console.log('Successfully sent transcription response');
                } catch (error) {
                    console.error('Transcription error:', error);
                    console.error('Error stack:', error.stack);
                    
                    // Update Firestore with failed status if we have the videoId
                    if (videoId) {
                        try {
                            await db.collection('videos').doc(videoId).update({
                                transcriptionStatus: 'failed',
                                transcriptionText: null,
                                transcriptionSegments: null
                            });
                            console.log('Updated Firestore with failed status');
                        } catch (updateError) {
                            console.error('Failed to update error status:', updateError);
                        }
                    }
                    
                    res.writeHead(500, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ 
                        error: 'Transcription failed',
                        details: error.message 
                    }));
                }
            });
        } catch (error) {
            console.error('Request handling error:', error);
            console.error('Error stack:', error.stack);
            res.writeHead(400, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: 'Invalid request' }));
        }
        return;
    }

    // Translation test endpoint
    if (req.method === 'POST' && pathname === '/translate') {
        console.log('Handling translation request');
        let body = '';
        req.on('data', chunk => {
            body += chunk.toString();
        });

        req.on('end', async () => {
            try {
                const { text, targetLanguage } = JSON.parse(body);
                console.log(`Translating to ${targetLanguage}:`, text);

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
                    stream: false // Changed to false for initial testing
                });

                const translation = completion.choices[0].message.content;
                
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ 
                    translation,
                    sourceLanguage: 'en',
                    targetLanguage,
                    status: 'success'
                }));
            } catch (error) {
                console.error('Translation error:', error);
                res.writeHead(500, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ 
                    error: 'Translation failed',
                    details: error.message 
                }));
            }
        });
        return;
    }

    // Default response for unhandled routes
    console.log('Unhandled route:', pathname);
    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Not Found' }));
});

// Initialize WebSocket server
const wss = new WebSocketServer({ server });

// Store active connections
const clients = new Map();

wss.on('connection', (ws) => {
    console.log('New WebSocket connection');
    
    // Generate unique client ID
    const clientId = Date.now();
    clients.set(clientId, ws);
    
    // Send welcome message
    ws.send(JSON.stringify({
        type: 'connection',
        message: 'Connected to transcription service'
    }));
    
    ws.on('message', async (message) => {
        try {
            const data = JSON.parse(message);
            console.log('Received:', data);
            
            if (data.type === 'subscribe') {
                // Store videoId with client connection
                ws.videoId = data.videoId;
                ws.send(JSON.stringify({
                    type: 'subscribed',
                    videoId: data.videoId
                }));
            }
        } catch (error) {
            console.error('WebSocket message error:', error);
            ws.send(JSON.stringify({
                type: 'error',
                message: error.message
            }));
        }
    });
    
    ws.on('close', () => {
        console.log('Client disconnected');
        clients.delete(clientId);
    });
    
    ws.on('error', (error) => {
        console.error('WebSocket error:', error);
        clients.delete(clientId);
    });
});

// Function to broadcast transcription progress
function broadcastTranscriptionProgress(videoId, progress) {
    for (const [_, ws] of clients) {
        if (ws.videoId === videoId) {
            ws.send(JSON.stringify({
                type: 'progress',
                videoId: videoId,
                progress: progress
            }));
        }
    }
}

// Helper function to compress video using FFmpeg
async function compressVideo(inputBuffer) {
    console.log('\n🎬 Starting video compression with FFmpeg...');
    
    // Create temporary input and output files
    const inputPath = `/tmp/input-${Date.now()}.mp4`;
    const outputPath = `/tmp/output-${Date.now()}.mp4`;
    
    try {
        // Write input buffer to temporary file
        console.log('Writing input buffer to temporary file...');
        await fs.promises.writeFile(inputPath, inputBuffer);
        
        // OpenAI has a 25MB file size limit
        const MAX_FILE_SIZE = 25 * 1024 * 1024; // 25MB in bytes
        const inputSize = inputBuffer.length;
        
        // Calculate target bitrate based on input size
        // Aim for 20MB to leave some headroom
        const targetSize = Math.min(20 * 1024 * 1024, inputSize);
        const durationSeconds = 600; // Assume max 10 minutes, adjust if needed
        const targetBitrate = Math.floor((targetSize * 8) / durationSeconds);
        
        // Prepare FFmpeg command with bitrate control
        const ffmpegCommand = `ffmpeg -i ${inputPath} -c:v libx264 -preset medium -crf 23 -maxrate ${targetBitrate}k -bufsize ${targetBitrate*2}k -c:a aac -b:a 64k ${outputPath}`;
        console.log('Running FFmpeg command:', ffmpegCommand);
        
        // Execute FFmpeg command
        await new Promise((resolve, reject) => {
            exec(ffmpegCommand, (error, stdout, stderr) => {
                if (error) {
                    console.error('FFmpeg error:', error);
                    reject(error);
                    return;
                }
                resolve();
            });
        });
        
        // Read the compressed video
        console.log('Reading compressed video...');
        const compressedBuffer = await fs.promises.readFile(outputPath);
        
        // Verify the compressed size
        if (compressedBuffer.length > MAX_FILE_SIZE) {
            throw new Error(`Compressed file size (${compressedBuffer.length} bytes) exceeds OpenAI's limit of ${MAX_FILE_SIZE} bytes`);
        }
        
        // Clean up temporary files
        await fs.promises.unlink(inputPath);
        await fs.promises.unlink(outputPath);
        
        console.log('✅ Video compression complete');
        return compressedBuffer;
    } catch (error) {
        // Clean up on error
        try {
            await fs.promises.unlink(inputPath);
            await fs.promises.unlink(outputPath);
        } catch {}
        throw error;
    }
}

// Helper function to create form data with proper headers
async function createFormDataWithFile(buffer, filename = 'video.mp4') {
    const formData = new FormData();
    formData.append('file', buffer, { filename });
    formData.append('model', 'whisper-1');
    formData.append('language', 'en');
    formData.append('response_format', 'verbose_json');
    formData.append('timestamp_granularity', 'word');
    return formData;
}

// Helper function to stream file to OpenAI
async function streamFileToOpenAI(formData) {
    const response = await fetch('https://api.openai.com/v1/audio/transcriptions', {
        method: 'POST',
        headers: {
            'Authorization': `Bearer ${process.env.OPENAI_API_KEY}`,
            ...formData.getHeaders()
        },
        body: formData,
        timeout: 300000 // 5 minutes
    });

    if (!response.ok) {
        const text = await response.text();
        console.error('OpenAI API Error Response:', text);
        throw new Error(`OpenAI API error: ${response.status} ${text}`);
    }

    const result = await response.json();
    console.log('\nOpenAI Response Format:', Object.keys(result).join(', '));
    return result;
}

// Helper function to retry failed requests
async function retryWithBackoff(operation, maxRetries = 5) {
    for (let i = 0; i < maxRetries; i++) {
        try {
            return await operation();
        } catch (error) {
            if (i === maxRetries - 1) throw error;
            
            // Log retry attempt
            console.log(`Attempt ${i + 1} failed, retrying in ${Math.pow(2, i)} seconds...`);
            console.error('Error:', error.message);
            
            // Exponential backoff
            await new Promise(resolve => setTimeout(resolve, Math.pow(2, i) * 1000));
        }
    }
}

// Modify the transcription process to send progress updates
async function processTranscription(videoUrl, videoId) {
    try {
        console.log('\n=== Starting Transcription Process for Video ID:', videoId, '===');
        
        // Send initial progress
        broadcastTranscriptionProgress(videoId, 0);
        
        // Fetch and process video (keeping logs minimal)
        const videoResponse = await fetch(videoUrl);
        if (!videoResponse.ok) {
            throw new Error(`Failed to fetch video: ${videoResponse.statusText}`);
        }
        
        const buffer = await videoResponse.arrayBuffer();
        const compressedBuffer = await compressVideo(Buffer.from(buffer));
        
        broadcastTranscriptionProgress(videoId, 0.5);
        
        // Create form data and send to OpenAI
        const formData = await createFormDataWithFile(compressedBuffer);
        console.log('📡 Sending request to OpenAI with timestamp_granularities enabled');
        
        const transcription = await retryWithBackoff(async () => {
            return await streamFileToOpenAI(formData);
        });
        
        // Log transcription timing data
        console.log('\n=== Transcription Timing Data ===');
        console.log(`Total segments: ${transcription.segments?.length || 0}`);
        
        // Log sample of segments (first 2 for verification)
        if (transcription.segments && transcription.segments.length > 0) {
            console.log('\nSample segments:');
            transcription.segments.slice(0, 2).forEach((segment, i) => {
                console.log(`\nSegment ${i + 1}:`);
                console.log(`Text: "${segment.text}"`);
                console.log(`Time: ${segment.start}s -> ${segment.end}s`);
                if (segment.words) {
                    console.log('Word timing:');
                    segment.words.forEach(word => {
                        console.log(`- "${word.text}": ${word.start}s -> ${word.end}s`);
                    });
                }
            });
        }
        
        // Process segments and words
        const segments = transcription.segments.map(segment => ({
            text: segment.text,
            startTime: segment.start,
            endTime: segment.end,
            ...(segment.words && {
                words: segment.words.map(word => ({
                    text: word.text,
                    startTime: word.start,
                    endTime: word.end
                }))
            })
        }));
        
        // Update Firestore
        console.log('\nUpdating Firestore with timing data...');
        await db.collection('videos').doc(videoId).update({
            transcriptionStatus: 'completed',
            transcriptionText: transcription.text,
            transcriptionSegments: segments
        });
        console.log('✅ Firestore updated with timing data');
        
        broadcastTranscriptionProgress(videoId, 1);
        
        return {
            text: transcription.text,
            segments: segments
        };
    } catch (error) {
        console.error('\n❌ Transcription Error:', error.message);
        
        // Update Firestore with failed status
        try {
            await db.collection('videos').doc(videoId).update({
                transcriptionStatus: 'failed',
                transcriptionText: null,
                transcriptionSegments: null
            });
            console.error('Status updated to failed in Firestore');
        } catch (updateError) {
            console.error('Failed to update error status in Firestore');
        }
        
        throw error;
    }
}

const port = process.env.PORT || 3001;
const host = '0.0.0.0';

// Add error handling for server
server.on('error', (error) => {
    console.error('Server error:', error);
    if (error.code === 'EADDRINUSE') {
        console.error(`Port ${port} is already in use. Please choose a different port or kill the process using this port.`);
    }
});

server.listen(port, host, () => {
    console.log(`\n=== Server running at http://${host}:${port} ===`);
    console.log(`WebSocket server running at ws://${host}:${port}`);
    console.log('Ready to handle requests...\n');
}); 