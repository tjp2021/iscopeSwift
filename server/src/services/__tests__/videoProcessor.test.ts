import { generateSubtitleFile } from '../videoProcessor'
import * as fs from 'fs'
import * as path from 'path'
import * as os from 'os'

describe('videoProcessor', () => {
  describe('generateSubtitleFile', () => {
    const testSegments = [
      {
        text: 'Hello world',
        startTime: 0,
        endTime: 2
      },
      {
        text: 'Second line',
        startTime: 2.5,
        endTime: 4
      }
    ]
    
    let tempDir: string
    let subtitlePath: string
    
    beforeEach(async () => {
      // Create temp directory for test files
      tempDir = path.join(os.tmpdir(), 'subtitle-test-' + Math.random().toString(36).substring(7))
      await fs.promises.mkdir(tempDir, { recursive: true })
      subtitlePath = path.join(tempDir, 'test.srt')
    })
    
    afterEach(async () => {
      // Cleanup temp files
      await fs.promises.rm(tempDir, { recursive: true, force: true })
    })
    
    it('should generate a valid SRT file', async () => {
      await generateSubtitleFile(testSegments, subtitlePath)
      
      const content = await fs.promises.readFile(subtitlePath, 'utf-8')
      const lines = content.split('\n')
      
      // Check structure
      expect(lines[0]).toBe('1') // First segment number
      expect(lines[1]).toBe('00:00:00,000 --> 00:00:02,000') // First timestamp
      expect(lines[2]).toBe('Hello world') // First text
      expect(lines[3]).toBe('') // Empty line
      expect(lines[4]).toBe('2') // Second segment number
      expect(lines[5]).toBe('00:00:02,500 --> 00:00:04,000') // Second timestamp
      expect(lines[6]).toBe('Second line') // Second text
    })
    
    it('should handle empty segments array', async () => {
      await generateSubtitleFile([], subtitlePath)
      
      const content = await fs.promises.readFile(subtitlePath, 'utf-8')
      expect(content).toBe('')
    })
    
    it('should handle special characters in text', async () => {
      const specialSegments = [{
        text: 'Hello & goodbye! ¿Cómo estás?',
        startTime: 0,
        endTime: 2
      }]
      
      await generateSubtitleFile(specialSegments, subtitlePath)
      
      const content = await fs.promises.readFile(subtitlePath, 'utf-8')
      expect(content).toContain('Hello & goodbye! ¿Cómo estás?')
    })
  })
}) 