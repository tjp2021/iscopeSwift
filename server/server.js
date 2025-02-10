import http from 'http';
import OpenAI from 'openai';
import dotenv from 'dotenv';
import { Readable } from 'stream';

// Load environment variables
dotenv.config();

// Initialize OpenAI client
const openai = new OpenAI({
    apiKey: process.env.OPENAI_API_KEY
});

/**
 * Simple HTTP server that handles transcription requests using OpenAI's Whisper API.
 * Endpoints:
 * - POST /test-transcription: Returns a test response for validating client integration
 * - POST /start-transcription: Handles actual video transcription using Whisper
 */

const server = http.createServer(async (req, res) => {
    // Add CORS headers for cross-origin requests
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

    // Handle OPTIONS request for CORS preflight
    if (req.method === 'OPTIONS') {
        res.writeHead(204);
        res.end();
        return;
    }

    // Handle test transcription endpoint
    if (req.method === 'POST' && req.url === '/test-transcription') {
        const mockResponse = {
            jobId: "test-123",
            status: "completed",
            transcriptUrl: "https://example.com/test-transcript.txt",
            text: "This is a test transcription response."
        };
        
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(mockResponse));
        return;
    }

    // Handle actual transcription endpoint
    if (req.method === 'POST' && req.url === '/start-transcription') {
        try {
            // Get request body
            let body = '';
            req.on('data', chunk => {
                body += chunk.toString();
            });

            req.on('end', async () => {
                try {
                    const { videoUrl, languageCode } = JSON.parse(body);
                    console.log(`Processing video from URL: ${videoUrl}`);
                    
                    // Download video file from URL
                    const videoResponse = await fetch(videoUrl);
                    if (!videoResponse.ok) {
                        throw new Error(`Failed to fetch video: ${videoResponse.statusText}`);
                    }
                    
                    const buffer = await videoResponse.arrayBuffer();
                    const file = new File([buffer], 'video.mp4', { type: 'video/mp4' });
                    
                    console.log('Creating transcription with Whisper API...');
                    const transcription = await openai.audio.transcriptions.create({
                        file: file,
                        model: "whisper-1",
                        language: languageCode || 'en'
                    });

                    console.log('Transcription completed:', transcription);

                    const transcriptionResponse = {
                        jobId: `whisper-${Date.now()}`,
                        status: "completed",
                        transcriptUrl: "", // We could store this in S3 if needed
                        text: transcription.text
                    };

                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify(transcriptionResponse));
                } catch (error) {
                    console.error('Transcription error:', error);
                    res.writeHead(500, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ 
                        error: 'Transcription failed',
                        details: error.message 
                    }));
                }
            });
        } catch (error) {
            console.error('Request handling error:', error);
            res.writeHead(400, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: 'Invalid request' }));
        }
        return;
    }

    // Default response for unhandled routes
    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Not Found' }));
});

const port = 3000;

// Error handling
server.on('error', (err) => {
    console.error('Server error:', err);
    if (err.code === 'EADDRINUSE') {
        console.error(`Port ${port} is already in use`);
    }
    process.exit(1);
});

// Graceful shutdown handlers
process.on('SIGTERM', () => {
    console.log('Shutting down gracefully...');
    server.close(() => {
        console.log('Server closed');
        process.exit(0);
    });
});

process.on('SIGINT', () => {
    console.log('Shutting down gracefully...');
    server.close(() => {
        console.log('Server closed');
        process.exit(0);
    });
});

// Start the server
try {
    server.listen(port, '0.0.0.0', () => {
        console.log(`Server running on port ${port}`);
    });
} catch (err) {
    console.error('Failed to start server:', err);
    process.exit(1);
} 