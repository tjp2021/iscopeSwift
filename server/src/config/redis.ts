export const redisConfig = {
  host: process.env.REDIS_HOST || 'localhost',
  port: parseInt(process.env.REDIS_PORT || '6379'),
  retryStrategy: (times: number) => {
    // Maximum wait time is 3 seconds
    return Math.min(times * 50, 3000)
  }
} 