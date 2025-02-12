export const redisConfig = {
  url: process.env.REDIS_URL, // Heroku Redis URL
  retryStrategy: (times: number) => {
    // Maximum wait time is 3 seconds
    return Math.min(times * 50, 3000)
  }
} 