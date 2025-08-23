import { useState, useEffect } from 'react'
import { XMarkIcon } from '@heroicons/react/24/outline'
import type { DemoPerformanceMetrics, PerformanceStatus } from '../../types/demo.types'
import { PERFORMANCE_THRESHOLDS } from '../../types/demo.types'

interface MetricsDashboardProps {
  isOpen: boolean
  onClose: () => void
  performance?: DemoPerformanceMetrics | null
}

interface HistoricalDataPoint extends DemoPerformanceMetrics {
  timestamp: Date
}

export function MetricsDashboard({ isOpen, onClose, performance }: MetricsDashboardProps) {
  const [historicalData, setHistoricalData] = useState<HistoricalDataPoint[]>([])

  useEffect(() => {
    if (performance) {
      setHistoricalData(prev => [
        ...prev.slice(-19), // Keep last 20 data points
        {
          timestamp: new Date(),
          ...performance
        }
      ])
    }
  }, [performance])

  if (!isOpen) return null

  const latestMetrics = historicalData[historicalData.length - 1]

  const getPerformanceStatus = (value: number, thresholds: { good: number; warning: number }): PerformanceStatus => {
    if (value <= thresholds.good) return 'good'
    if (value <= thresholds.warning) return 'warning'
    return 'error'
  }

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 z-50 flex items-center justify-center p-4">
      <div className="bg-white rounded-xl shadow-2xl max-w-6xl w-full max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between p-6 border-b">
          <h2 className="text-xl font-semibold text-gray-900">Performance Metrics</h2>
          <button
            onClick={onClose}
            className="text-gray-400 hover:text-gray-600 transition-colors"
          >
            <XMarkIcon className="h-6 w-6" />
          </button>
        </div>

        <div className="p-6">
          {!latestMetrics ? (
            <div className="text-center py-12">
              <div className="w-16 h-16 bg-gray-100 rounded-full flex items-center justify-center mx-auto mb-4">
                <ChartBarIcon className="w-8 h-8 text-gray-400" />
              </div>
              <p className="text-gray-500 text-lg">Start a conversation to see performance metrics</p>
              <p className="text-gray-400 text-sm mt-1">Click the microphone button to begin</p>
            </div>
          ) : (
            <div className="space-y-8">
              {/* Current Performance */}
              <section>
                <h3 className="text-lg font-medium text-gray-900 mb-4">Latest Performance</h3>
                <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                  <MetricCard
                    title="VAD Latency"
                    value={`${Math.round(latestMetrics.vadLatency)}ms`}
                    target={`<${PERFORMANCE_THRESHOLDS.vadLatency.good}ms`}
                    status={getPerformanceStatus(latestMetrics.vadLatency, PERFORMANCE_THRESHOLDS.vadLatency)}
                  />
                  <MetricCard
                    title="STT Latency"
                    value={`${Math.round(latestMetrics.sttLatency)}ms`}
                    target={`<${PERFORMANCE_THRESHOLDS.sttLatency.good}ms`}
                    status={getPerformanceStatus(latestMetrics.sttLatency, PERFORMANCE_THRESHOLDS.sttLatency)}
                  />
                  <MetricCard
                    title="LLM Latency"
                    value={`${Math.round(latestMetrics.llmLatency)}ms`}
                    target={`<${PERFORMANCE_THRESHOLDS.llmLatency.good}ms`}
                    status={getPerformanceStatus(latestMetrics.llmLatency, PERFORMANCE_THRESHOLDS.llmLatency)}
                  />
                  <MetricCard
                    title="TTS Latency"
                    value={`${Math.round(latestMetrics.ttsLatency)}ms`}
                    target={`<${PERFORMANCE_THRESHOLDS.ttsLatency.good}ms`}
                    status={getPerformanceStatus(latestMetrics.ttsLatency, PERFORMANCE_THRESHOLDS.ttsLatency)}
                  />
                </div>
              </section>

              {/* Overall Performance */}
              <section>
                <h3 className="text-lg font-medium text-gray-900 mb-4">Overall Performance</h3>
                <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                  <MetricCard
                    title="Total Duration"
                    value={`${Math.round(latestMetrics.totalDuration)}ms`}
                    target={`<${PERFORMANCE_THRESHOLDS.totalDuration.good}ms`}
                    status={getPerformanceStatus(latestMetrics.totalDuration, PERFORMANCE_THRESHOLDS.totalDuration)}
                  />
                  <MetricCard
                    title="Memory Usage"
                    value={`${Math.round(latestMetrics.memoryUsage)}MB`}
                    target={`<${PERFORMANCE_THRESHOLDS.memoryUsage.good}MB`}
                    status={getPerformanceStatus(latestMetrics.memoryUsage, PERFORMANCE_THRESHOLDS.memoryUsage)}
                  />
                  <MetricCard
                    title="Model Load Time"
                    value={`${(latestMetrics.modelLoadTime / 1000).toFixed(1)}s`}
                    target="<10s"
                    status={getPerformanceStatus(latestMetrics.modelLoadTime, { good: 5000, warning: 10000 })}
                  />
                </div>
              </section>

              {/* Performance Trends */}
              {historicalData.length > 1 && (
                <section>
                  <h3 className="text-lg font-medium text-gray-900 mb-4">Trends (Last {Math.min(historicalData.length, 20)} Interactions)</h3>
                  <div className="bg-gray-50 rounded-lg p-4">
                    <PerformanceChart data={historicalData} />
                  </div>
                </section>
              )}

              {/* Detailed Breakdown */}
              <section>
                <h3 className="text-lg font-medium text-gray-900 mb-4">Performance Breakdown</h3>
                <div className="bg-gray-50 rounded-lg p-4">
                  <PerformanceBreakdown metrics={latestMetrics} />
                </div>
              </section>

              {/* System Info */}
              <section>
                <h3 className="text-lg font-medium text-gray-900 mb-4">System Information</h3>
                <div className="bg-gray-50 rounded-lg p-4">
                  <SystemInfo />
                </div>
              </section>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

interface MetricCardProps {
  title: string
  value: string
  target: string
  status: PerformanceStatus
}

function MetricCard({ title, value, target, status }: MetricCardProps) {
  const statusColors = {
    good: 'bg-green-50 border-green-200 text-green-800',
    warning: 'bg-yellow-50 border-yellow-200 text-yellow-800',
    error: 'bg-red-50 border-red-200 text-red-800'
  }

  const indicatorColors = {
    good: 'bg-green-500',
    warning: 'bg-yellow-500',
    error: 'bg-red-500'
  }

  return (
    <div className={`border rounded-lg p-4 ${statusColors[status]}`}>
      <div className="flex items-center justify-between mb-2">
        <h4 className="font-medium text-sm">{title}</h4>
        <div className={`w-3 h-3 rounded-full ${indicatorColors[status]}`} />
      </div>
      <div className="text-2xl font-bold mb-1">{value}</div>
      <div className="text-xs opacity-75">Target: {target}</div>
    </div>
  )
}

function PerformanceChart({ data }: { data: HistoricalDataPoint[] }) {
  const recentData = data.slice(-10)
  const maxLatency = Math.max(...recentData.map(d => d.sttLatency + d.llmLatency))

  return (
    <div className="space-y-3">
      <div className="text-sm font-medium text-gray-700 mb-3">Response Time Trend (STT + LLM)</div>
      {recentData.map((point, index) => {
        const totalLatency = point.sttLatency + point.llmLatency
        const percentage = Math.max((totalLatency / maxLatency) * 100, 5) // Min 5% width for visibility

        return (
          <div key={index} className="flex items-center gap-3 text-xs">
            <div className="w-20 text-right text-gray-600 font-mono">
              {Math.round(totalLatency)}ms
            </div>
            <div className="flex-1 bg-gray-200 rounded-full h-3 relative">
              <div
                className={`rounded-full h-3 transition-all duration-300 ${
                  totalLatency < 800 ? 'bg-green-500' :
                  totalLatency < 2000 ? 'bg-yellow-500' : 'bg-red-500'
                }`}
                style={{ width: `${percentage}%` }}
              />
            </div>
            <div className="w-16 text-xs text-gray-500">
              {point.timestamp.toLocaleTimeString([], { minute: '2-digit', second: '2-digit' })}
            </div>
          </div>
        )
      })}
    </div>
  )
}

function PerformanceBreakdown({ metrics }: { metrics: DemoPerformanceMetrics }) {
  const components = [
    { name: 'Voice Activity Detection', latency: metrics.vadLatency, color: 'bg-purple-500' },
    { name: 'Speech-to-Text', latency: metrics.sttLatency, color: 'bg-blue-500' },
    { name: 'Language Model', latency: metrics.llmLatency, color: 'bg-green-500' },
    { name: 'Text-to-Speech', latency: metrics.ttsLatency, color: 'bg-orange-500' },
  ]

  const maxLatency = Math.max(...components.map(c => c.latency))

  return (
    <div className="space-y-3">
      <div className="text-sm font-medium text-gray-700 mb-3">Pipeline Component Latencies</div>
      {components.map((component) => {
        const percentage = Math.max((component.latency / maxLatency) * 100, 5)

        return (
          <div key={component.name} className="flex items-center gap-3">
            <div className="w-32 text-sm text-gray-700 truncate">{component.name}</div>
            <div className="flex-1 bg-gray-200 rounded-full h-4 relative">
              <div
                className={`${component.color} rounded-full h-4 transition-all duration-300`}
                style={{ width: `${percentage}%` }}
              />
            </div>
            <div className="w-16 text-sm text-gray-600 text-right font-mono">
              {Math.round(component.latency)}ms
            </div>
          </div>
        )
      })}
      <div className="border-t pt-3 mt-3">
        <div className="flex justify-between text-sm">
          <span className="font-medium text-gray-700">Total Pipeline Duration</span>
          <span className="font-mono font-medium text-gray-900">{Math.round(metrics.totalDuration)}ms</span>
        </div>
      </div>
    </div>
  )
}

function SystemInfo() {
  return (
    <dl className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 text-sm">
      <div>
        <dt className="font-medium text-gray-700">Browser</dt>
        <dd className="text-gray-600">{getBrowserName()}</dd>
      </div>
      <div>
        <dt className="font-medium text-gray-700">Platform</dt>
        <dd className="text-gray-600">{navigator.platform || 'Unknown'}</dd>
      </div>
      <div>
        <dt className="font-medium text-gray-700">CPU Cores</dt>
        <dd className="text-gray-600">{navigator.hardwareConcurrency || 'Unknown'}</dd>
      </div>
      <div>
        <dt className="font-medium text-gray-700">Device Memory</dt>
        <dd className="text-gray-600">
          {(navigator as any).deviceMemory ? `${(navigator as any).deviceMemory}GB` : 'Unknown'}
        </dd>
      </div>
      <div>
        <dt className="font-medium text-gray-700">Connection</dt>
        <dd className="text-gray-600">
          {(navigator as any).connection?.effectiveType || 'Unknown'}
        </dd>
      </div>
      <div>
        <dt className="font-medium text-gray-700">WebAssembly</dt>
        <dd className="text-gray-600">
          {typeof WebAssembly !== 'undefined' ? 'Supported' : 'Not Supported'}
        </dd>
      </div>
    </dl>
  )
}

function getBrowserName(): string {
  const userAgent = navigator.userAgent
  if (userAgent.includes('Chrome') && !userAgent.includes('Edg')) return 'Chrome'
  if (userAgent.includes('Firefox')) return 'Firefox'
  if (userAgent.includes('Safari') && !userAgent.includes('Chrome')) return 'Safari'
  if (userAgent.includes('Edg')) return 'Edge'
  return 'Unknown'
}

// Import for the chart icon
function ChartBarIcon({ className }: { className: string }) {
  return (
    <svg className={className} fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
      <path strokeLinecap="round" strokeLinejoin="round" d="M3 13.125C3 12.504 3.504 12 4.125 12h2.25c.621 0 1.125.504 1.125 1.125v6.75C7.5 20.496 6.996 21 6.375 21h-2.25A1.125 1.125 0 013 19.875v-6.75zM9.75 8.625c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125v11.25c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 01-1.125-1.125V8.625zM16.5 4.125c0-.621.504-1.125 1.125-1.125h2.25C20.496 3 21 3.504 21 4.125v15.75c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 01-1.125-1.125V4.125z" />
    </svg>
  )
}
