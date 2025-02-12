import Queue from 'bull'
import { redisConfig } from '../config/redis.js'
import { processVideoJob } from '../services/videoProcessor.js'

export interface ExportJobData {
  jobId: string
  videoId: string
  language: string
}

export class QueueManager {
  private static instance: QueueManager
  private exportQueue: Queue.Queue<ExportJobData>

  private constructor() {
    this.exportQueue = new Queue<ExportJobData>('video-export', {
      redis: redisConfig,
      defaultJobOptions: {
        attempts: 3,
        backoff: {
          type: 'exponential',
          delay: 1000
        },
        removeOnComplete: true,
        removeOnFail: false
      }
    })

    // Set up queue event handlers
    this.setupQueueEvents()
    
    // Process jobs
    this.exportQueue.process(async (job) => {
      try {
        const result = await processVideoJob(job)
        return result
      } catch (error) {
        console.error(`Export job ${job.id} failed:`, error)
        throw error
      }
    })
  }

  private setupQueueEvents() {
    this.exportQueue.on('completed', (job) => {
      console.log(`Export job ${job.id} completed successfully`)
    })

    this.exportQueue.on('failed', (job, error) => {
      console.error(`Export job ${job.id} failed:`, error)
    })

    this.exportQueue.on('progress', (job, progress) => {
      console.log(`Export job ${job.id} progress: ${progress}%`)
    })

    // Handle stalled jobs
    this.exportQueue.on('stalled', (job) => {
      console.warn(`Export job ${job.id} has stalled`)
    })

    // Handle cleaned jobs
    this.exportQueue.on('cleaned', (jobs, type) => {
      console.log(`Cleaned ${jobs.length} ${type} jobs`)
    })
  }

  public static getInstance(): QueueManager {
    if (!QueueManager.instance) {
      QueueManager.instance = new QueueManager()
    }
    return QueueManager.instance
  }

  public async addExportJob(jobData: ExportJobData): Promise<Queue.Job<ExportJobData>> {
    return this.exportQueue.add(jobData)
  }

  public async getExportJob(jobId: string): Promise<Queue.Job<ExportJobData> | null> {
    return this.exportQueue.getJob(jobId)
  }

  public async cleanOldJobs(): Promise<void> {
    // Clean completed jobs older than 1 hour
    await this.exportQueue.clean(3600000, 'completed')
    // Clean failed jobs older than 24 hours
    await this.exportQueue.clean(86400000, 'failed')
  }

  public async pauseQueue(): Promise<void> {
    await this.exportQueue.pause()
  }

  public async resumeQueue(): Promise<void> {
    await this.exportQueue.resume()
  }

  public async getQueueStatus(): Promise<{
    waiting: number
    active: number
    completed: number
    failed: number
    delayed: number
  }> {
    const [waiting, active, completed, failed, delayed] = await Promise.all([
      this.exportQueue.getWaitingCount(),
      this.exportQueue.getActiveCount(),
      this.exportQueue.getCompletedCount(),
      this.exportQueue.getFailedCount(),
      this.exportQueue.getDelayedCount()
    ])

    return {
      waiting,
      active,
      completed,
      failed,
      delayed
    }
  }
} 