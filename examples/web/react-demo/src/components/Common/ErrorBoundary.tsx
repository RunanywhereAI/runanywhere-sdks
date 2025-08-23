/**
 * Error Boundary Component
 * Catches and displays React errors gracefully
 */

import { Component, ReactNode, ErrorInfo } from 'react'
import { formatErrorMessage } from '../../utils/formatters'

interface ErrorBoundaryState {
  hasError: boolean
  error?: Error
  errorInfo?: ErrorInfo
}

interface ErrorBoundaryProps {
  children: ReactNode
  fallback?: (error: Error, errorInfo: ErrorInfo, resetError: () => void) => ReactNode
  onError?: (error: Error, errorInfo: ErrorInfo) => void
}

export class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  constructor(props: ErrorBoundaryProps) {
    super(props)
    this.state = { hasError: false }
  }

  static getDerivedStateFromError(_error: Error): Partial<ErrorBoundaryState> {
    return { hasError: true }
  }

  override componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    this.setState({ error, errorInfo })

    // Report error to logging service
    console.error('Error caught by boundary:', error, errorInfo)

    // Call custom error handler if provided
    this.props.onError?.(error, errorInfo)
  }

  resetError = () => {
    this.setState({ hasError: false, error: undefined, errorInfo: undefined })
  }

  override render() {
    if (this.state.hasError && this.state.error && this.state.errorInfo) {
      // Custom fallback component
      if (this.props.fallback) {
        return this.props.fallback(this.state.error, this.state.errorInfo, this.resetError)
      }

      // Default error display
      return (
        <DefaultErrorFallback
          error={this.state.error}
          resetError={this.resetError}
        />
      )
    }

    return this.props.children
  }
}

interface DefaultErrorFallbackProps {
  error: Error
  resetError: () => void
}

function DefaultErrorFallback({ error, resetError }: DefaultErrorFallbackProps) {
  const isDevelopment = import.meta.env?.DEV ?? false

  return (
    <div className="min-h-screen bg-gray-50 flex items-center justify-center p-4">
      <div className="bg-white rounded-lg shadow-lg max-w-md w-full p-6">
        <div className="flex items-center mb-4">
          <div className="w-12 h-12 bg-red-100 rounded-full flex items-center justify-center mr-4">
            <svg
              className="w-6 h-6 text-red-600"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L3.732 16.5c-.77.833.192 2.5 1.732 2.5z"
              />
            </svg>
          </div>
          <div>
            <h3 className="text-lg font-semibold text-gray-900">Something went wrong</h3>
            <p className="text-sm text-gray-600">The application encountered an unexpected error</p>
          </div>
        </div>

        <div className="mb-6">
          <p className="text-sm text-gray-700 mb-2">
            {formatErrorMessage(error)}
          </p>

          {isDevelopment && (
            <details className="mt-3">
              <summary className="text-xs text-gray-500 cursor-pointer hover:text-gray-700">
                Technical Details (Development Mode)
              </summary>
              <div className="mt-2 p-3 bg-gray-100 rounded text-xs font-mono text-gray-700 whitespace-pre-wrap max-h-40 overflow-y-auto">
                {error.stack}
              </div>
            </details>
          )}
        </div>

        <div className="flex gap-3">
          <button
            onClick={resetError}
            className="flex-1 bg-blue-600 text-white py-2 px-4 rounded-lg hover:bg-blue-700 transition-colors font-medium"
          >
            Try Again
          </button>
          <button
            onClick={() => window.location.reload()}
            className="flex-1 border border-gray-300 text-gray-700 py-2 px-4 rounded-lg hover:bg-gray-50 transition-colors font-medium"
          >
            Reload Page
          </button>
        </div>

        <div className="mt-4 pt-4 border-t text-center">
          <p className="text-xs text-gray-500">
            If this problem persists, please refresh the page or check your browser console for more details.
          </p>
        </div>
      </div>
    </div>
  )
}

// Hook for using error boundary in functional components
import { useState } from 'react'

export function useErrorBoundary() {
  const [error, setError] = useState<Error | null>(null)

  const captureError = (error: Error) => {
    setError(error)
  }

  if (error) {
    throw error
  }

  return captureError
}
