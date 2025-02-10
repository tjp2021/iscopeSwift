import http from 'http';

/**
 * Simple HTTP server that handles transcription requests.
 * Endpoints:
 * - POST /test-transcription: Returns a test response for validating client integration
 * - POST /start-transcription: (Future) Will handle actual video transcription
 */

const server = http.createServer((req, res) => {
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