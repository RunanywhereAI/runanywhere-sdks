/**
 * Status Indicator Component
 * Visual indicator for different states (good, warning, error)
 */

import type { PerformanceStatus } from '../../types/demo.types'

interface StatusIndicatorProps {
  status: PerformanceStatus
  size?: 'small' | 'medium' | 'large'
  showLabel?: boolean
  className?: string
}

const sizeClasses = {
  small: 'w-2 h-2',
  medium: 'w-3 h-3',
  large: 'w-4 h-4'
}

const statusConfig = {
  good: {
    color: 'bg-green-500',
    label: 'Good',
    description: 'Performance is within target range'
  },
  warning: {
    color: 'bg-yellow-500',
    label: 'Warning',
    description: 'Performance is above target but acceptable'
  },
  error: {
    color: 'bg-red-500',
    label: 'Error',
    description: 'Performance is significantly above target'
  }
}

export function StatusIndicator({
  status,
  size = 'medium',
  showLabel = false,
  className = ''
}: StatusIndicatorProps) {
  const config = statusConfig[status]

  return (
    <div className={`flex items-center gap-2 ${className}`}>
      <div
        className={`rounded-full ${sizeClasses[size]} ${config.color}`}
        title={config.description}
        aria-label={`Status: ${config.label}`}
      />
      {showLabel && (
        <span className={`text-sm font-medium ${getTextColor(status)}`}>
          {config.label}
        </span>
      )}
    </div>
  )
}

function getTextColor(status: PerformanceStatus): string {
  switch (status) {
    case 'good':
      return 'text-green-700'
    case 'warning':
      return 'text-yellow-700'
    case 'error':
      return 'text-red-700'
    default:
      return 'text-gray-700'
  }
}
