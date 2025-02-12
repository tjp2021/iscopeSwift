import Queue from 'bull'

export class QueueManager {
  static instance = null
  
  constructor() {
    if (QueueManager.instance) {
      return QueueManager.instance
    }
    
    this.exportQueue = new Queue('export', process.env.REDIS_URL, {
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
    
    QueueManager.instance = this
  }
  
  static getInstance() {
    if (!QueueManager.instance) {
      QueueManager.instance = new QueueManager()
    }
    return QueueManager.instance
  }
  
  getExportQueue() {
    return this.exportQueue
  }
} 