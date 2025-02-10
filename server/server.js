import http from 'http';

// Add debug logging
const debug = (...args) => console.log('[DEBUG]', ...args);
debug('Starting server initialization...');

// Create a basic HTTP server
const server = http.createServer((req, res) => {
    debug('Received request:', {
        method: req.method,
        url: req.url,
        headers: req.headers
    });

    // Add CORS headers
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
        debug('Handling test transcription request');
        
        // Send a mock response matching the expected WhisperResponse format
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

    console.log('Got a request:', req.method, req.url);
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('Hello World\n');
});

const port = 3000;  // Changed to match Swift app's expected port

// Add detailed error handling
server.on('error', (err) => {
    console.error('Server error:', err);
    debug('Error details:', {
        code: err.code,
        message: err.message,
        stack: err.stack
    });
    if (err.code === 'EADDRINUSE') {
        console.error(`Port ${port} is already in use`);
    }
    // Exit on critical errors
    process.exit(1);
});

// More detailed error handling
process.on('uncaughtException', (err) => {
    console.error('Uncaught exception:', err);
    debug('Exception details:', {
        name: err.name,
        message: err.message,
        stack: err.stack
    });
    // Exit on uncaught exceptions
    process.exit(1);
});

process.on('unhandledRejection', (err) => {
    console.error('Unhandled rejection:', err);
    debug('Rejection details:', {
        name: err?.name,
        message: err?.message,
        stack: err?.stack
    });
    // Exit on unhandled rejections
    process.exit(1);
});

// Add more process event handlers
process.on('SIGTERM', () => {
    debug('Received SIGTERM signal');
    console.log('Shutting down gracefully...');
    server.close(() => {
        console.log('Server closed');
        process.exit(0);
    });
});

process.on('SIGINT', () => {
    debug('Received SIGINT signal');
    console.log('Shutting down gracefully...');
    server.close(() => {
        console.log('Server closed');
        process.exit(0);
    });
});

// Try to start the server - bind to all interfaces
try {
    debug('Attempting to start server...');
    server.listen(port, '0.0.0.0', () => {
        const addr = server.address();
        debug('Server address details:', addr);
        console.log(`Server running and bound to all interfaces on port ${port}`);
        console.log('Try accessing via:');
        console.log(`  http://localhost:${port}`);
        console.log(`  http://127.0.0.1:${port}`);
        console.log(`  http://0.0.0.0:${port}`);
        console.log('Process ID:', process.pid);
    });
} catch (err) {
    console.error('Failed to start server:', err);
    debug('Startup error details:', {
        name: err.name,
        message: err.message,
        stack: err.stack
    });
    process.exit(1);
} 