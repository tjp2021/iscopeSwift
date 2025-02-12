import admin from 'firebase-admin'
import { fileURLToPath } from 'url'
import { dirname, join } from 'path'
import dotenv from 'dotenv'

// Load environment variables
dotenv.config()

const __filename = fileURLToPath(import.meta.url)
const __dirname = dirname(__filename)

// Initialize Firebase Admin if not already initialized
if (!admin.apps.length) {
  const serviceAccount = join(__dirname, '../../serviceAccountKey.json')
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  })
}

export const db = admin.firestore() 