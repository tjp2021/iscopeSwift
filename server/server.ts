import express from 'express'
import cors from 'cors'
import dotenv from 'dotenv'
import exportRouter from './src/routes/export.js'
import './src/config/firebase.js'

// Load environment variables
dotenv.config()

// Initialize Express app
const app = express()
app.use(cors())
app.use(express.json())

// Add routes
app.use('/api/export', exportRouter)

// Start server
const port = parseInt(process.env.PORT || '3001', 10)
app.listen(port, '0.0.0.0', () => {
  console.log(`\n=== Server running at http://0.0.0.0:${port} ===`)
  console.log('Ready to handle requests...\n')
}) 