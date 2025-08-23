/**
 * Loading Spinner Component
 * Reusable loading indicator with customizable size and color
 */

interface LoadingSpinnerProps {
  size?: 'small' | 'medium' | 'large'
  color?: 'blue' | 'gray' | 'white'
  className?: string
  label?: string
}

const sizeClasses = {
  small: 'w-4 h-4',
  medium: 'w-6 h-6',
  large: 'w-8 h-8'
}

const colorClasses = {
  blue: 'border-blue-500 border-t-transparent',
  gray: 'border-gray-500 border-t-transparent',
  white: 'border-white border-t-transparent'
}

export function LoadingSpinner({
  size = 'medium',
  color = 'blue',
  className = '',
  label
}: LoadingSpinnerProps) {
  return (
    <div className={`flex items-center gap-2 ${className}`}>
      <div
        className={`
          animate-spin rounded-full border-2
          ${sizeClasses[size]}
          ${colorClasses[color]}
        `}
        role="status"
        aria-label={label || 'Loading'}
      />
      {label && (
        <span className="text-sm text-gray-600">{label}</span>
      )}
    </div>
  )
}
