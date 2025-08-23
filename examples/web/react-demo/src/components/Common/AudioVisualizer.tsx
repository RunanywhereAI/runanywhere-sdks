/**
 * Audio Visualizer Component
 * Real-time audio waveform and level visualization
 */

import { useEffect, useRef } from 'react'

interface AudioVisualizerProps {
  audioLevel?: number
  isActive?: boolean
  type?: 'waveform' | 'bars' | 'circle'
  size?: 'small' | 'medium' | 'large'
  color?: string
  className?: string
}

const sizeConfig = {
  small: { width: 120, height: 40, barCount: 20 },
  medium: { width: 200, height: 60, barCount: 32 },
  large: { width: 300, height: 80, barCount: 48 }
}

export function AudioVisualizer({
  audioLevel = 0,
  isActive = false,
  type = 'bars',
  size = 'medium',
  color = '#3B82F6',
  className = ''
}: AudioVisualizerProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const animationFrameRef = useRef<number>()
  const barsRef = useRef<number[]>([])

  const config = sizeConfig[size]

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return

    const ctx = canvas.getContext('2d')
    if (!ctx) return

    // Initialize bars array
    if (barsRef.current.length === 0) {
      barsRef.current = new Array(config.barCount).fill(0)
    }

    const animate = () => {
      // Clear canvas
      ctx.clearRect(0, 0, canvas.width, canvas.height)

      if (isActive) {
        switch (type) {
          case 'bars':
            drawBars(ctx, canvas.width, canvas.height)
            break
          case 'waveform':
            drawWaveform(ctx, canvas.width, canvas.height)
            break
          case 'circle':
            drawCircle(ctx, canvas.width, canvas.height)
            break
        }
      }

      animationFrameRef.current = requestAnimationFrame(animate)
    }

    animate()

    return () => {
      if (animationFrameRef.current) {
        cancelAnimationFrame(animationFrameRef.current)
      }
    }
  }, [isActive, audioLevel, type, color, config])

  const drawBars = (ctx: CanvasRenderingContext2D, width: number, height: number) => {
    const barWidth = width / config.barCount
    const maxBarHeight = height * 0.8

    // Update bars with some randomness when active
    if (audioLevel > 0) {
      barsRef.current = barsRef.current.map((_, index) => {
        const baseHeight = audioLevel * maxBarHeight
        const randomFactor = 0.5 + Math.random() * 0.5
        const decay = 0.95

        // Create some frequency-based variation
        const freqVariation = Math.sin((index / config.barCount) * Math.PI * 2) * 0.3 + 0.7

        return Math.max(
          baseHeight * randomFactor * freqVariation,
          (barsRef.current[index] || 0) * decay
        )
      })
    } else {
      // Decay bars when not active
      barsRef.current = barsRef.current.map(height => height * 0.9)
    }

    // Draw bars
    ctx.fillStyle = color
    barsRef.current.forEach((barHeight, index) => {
      const x = index * barWidth + barWidth * 0.1
      const y = height - barHeight
      const w = barWidth * 0.8

      // Add gradient effect
      const gradient = ctx.createLinearGradient(0, height, 0, y)
      gradient.addColorStop(0, color)
      gradient.addColorStop(1, color + '80') // Semi-transparent

      ctx.fillStyle = gradient
      ctx.fillRect(x, y, w, barHeight)
    })
  }

  const drawWaveform = (ctx: CanvasRenderingContext2D, width: number, height: number) => {
    const centerY = height / 2
    const amplitude = audioLevel * centerY * 0.8

    ctx.strokeStyle = color
    ctx.lineWidth = 2
    ctx.beginPath()

    const points = 100
    const step = width / points

    for (let i = 0; i <= points; i++) {
      const x = i * step
      const frequency = 3 + audioLevel * 5 // Dynamic frequency
      const phase = Date.now() * 0.005 // Moving wave
      const noise = (Math.random() - 0.5) * audioLevel * 0.3 // Random variation

      const y = centerY + Math.sin((x / width) * Math.PI * frequency + phase) * amplitude + noise

      if (i === 0) {
        ctx.moveTo(x, y)
      } else {
        ctx.lineTo(x, y)
      }
    }

    ctx.stroke()
  }

  const drawCircle = (ctx: CanvasRenderingContext2D, width: number, height: number) => {
    const centerX = width / 2
    const centerY = height / 2
    const baseRadius = Math.min(width, height) * 0.2
    const maxRadius = Math.min(width, height) * 0.4

    // Outer pulsing circle
    const pulseRadius = baseRadius + (audioLevel * (maxRadius - baseRadius))
    const pulseOpacity = 0.3 + audioLevel * 0.4

    // Draw outer pulse
    ctx.beginPath()
    ctx.arc(centerX, centerY, pulseRadius, 0, Math.PI * 2)
    ctx.fillStyle = color + Math.floor(pulseOpacity * 255).toString(16).padStart(2, '0')
    ctx.fill()

    // Draw inner circle
    ctx.beginPath()
    ctx.arc(centerX, centerY, baseRadius, 0, Math.PI * 2)
    ctx.fillStyle = color
    ctx.fill()

    // Draw rotating elements around the circle
    const elementCount = 12
    const rotationSpeed = Date.now() * 0.002

    for (let i = 0; i < elementCount; i++) {
      const angle = (i / elementCount) * Math.PI * 2 + rotationSpeed
      const distance = baseRadius + (audioLevel * 20)
      const elementX = centerX + Math.cos(angle) * distance
      const elementY = centerY + Math.sin(angle) * distance
      const elementRadius = 1 + audioLevel * 3

      ctx.beginPath()
      ctx.arc(elementX, elementY, elementRadius, 0, Math.PI * 2)
      ctx.fillStyle = color + '80'
      ctx.fill()
    }
  }

  return (
    <div className={`flex items-center justify-center ${className}`}>
      <canvas
        ref={canvasRef}
        width={config.width}
        height={config.height}
        className="rounded"
        style={{ width: config.width, height: config.height }}
      />
    </div>
  )
}
