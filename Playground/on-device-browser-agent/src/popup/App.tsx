/**
 * Main Application Component
 *
 * Manages the popup UI state and communication with the background service worker.
 */

import React, { useState, useEffect, useCallback } from 'react';
import { TaskInput } from './components/TaskInput';
import { ProgressDisplay } from './components/ProgressDisplay';
import { ModelStatus } from './components/ModelStatus';
import { ResultView } from './components/ResultView';
import { POPUP_PORT_NAME } from '../shared/constants';
import type { ExecutorEvent } from '../shared/types';

// ============================================================================
// Types
// ============================================================================

export interface Step {
  number: number;
  action: string;
  params: Record<string, string>;
  status: 'pending' | 'running' | 'success' | 'failed';
  result?: string;
  error?: string;
}

type AppState = 'idle' | 'loading' | 'planning' | 'executing' | 'paused' | 'complete' | 'error';

interface ObstacleInfo {
  type: string;
  message: string;
}

// ============================================================================
// App Component
// ============================================================================

export function App(): React.ReactElement {
  // Application state
  const [state, setState] = useState<AppState>('idle');
  const [modelProgress, setModelProgress] = useState(0);
  const [plan, setPlan] = useState<string[]>([]);
  const [steps, setSteps] = useState<Step[]>([]);
  const [result, setResult] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [port, setPort] = useState<chrome.runtime.Port | null>(null);
  const [obstacle, setObstacle] = useState<ObstacleInfo | null>(null);

  // Connect to background service worker
  useEffect(() => {
    let currentPort: chrome.runtime.Port | null = null;

    const connect = () => {
      try {
        console.log('[Popup] Connecting to background service...');
        const newPort = chrome.runtime.connect({ name: POPUP_PORT_NAME });
        currentPort = newPort;

        newPort.onMessage.addListener((message) => {
          console.log('[Popup] Received message:', message);

          if (message.type === 'EXECUTOR_EVENT') {
            handleExecutorEvent(message.event as ExecutorEvent);
          } else if (message.type === 'TASK_RESULT') {
            setResult(message.result);
            setState('complete');
          } else if (message.type === 'ERROR') {
            setError(message.error);
            setState('error');
          }
        });

        newPort.onDisconnect.addListener(() => {
          console.log('[Popup] Port disconnected');
          const lastError = chrome.runtime.lastError;
          if (lastError) {
            console.error('[Popup] Disconnect error:', lastError.message);
          }
          setPort(null);
          currentPort = null;
        });

        setPort(newPort);
        console.log('[Popup] Connected successfully');
      } catch (err) {
        console.error('[Popup] Failed to connect:', err);
        setError('Failed to connect to background service. Try reloading the extension.');
        setState('error');
      }
    };

    connect();

    return () => {
      if (currentPort) {
        currentPort.disconnect();
      }
    };
  }, []);

  // Handle executor events
  const handleExecutorEvent = useCallback((event: ExecutorEvent) => {
    console.log('[Popup] Executor event:', event.type);

    switch (event.type) {
      case 'INIT_START':
        setState('loading');
        setModelProgress(0);
        break;

      case 'INIT_PROGRESS':
        setModelProgress(event.progress);
        break;

      case 'INIT_COMPLETE':
        setModelProgress(1);
        break;

      case 'VLM_INIT_START':
        // VLM loading starts after LLM
        break;

      case 'VLM_INIT_PROGRESS':
        // Show VLM progress (offset from LLM progress)
        setModelProgress(0.5 + event.progress * 0.5);
        break;

      case 'VLM_INIT_COMPLETE':
        setModelProgress(1);
        break;

      case 'SCREENSHOT_CAPTURED':
        // Could show visual feedback
        break;

      case 'VISION_ANALYSIS_COMPLETE':
        // Could show visual feedback
        break;

      case 'PLAN_START':
        setState('planning');
        break;

      case 'PLAN_COMPLETE':
        setPlan(event.plan);
        setState('executing');
        break;

      case 'STEP_START':
        setSteps((prev) => [
          ...prev,
          {
            number: event.stepNumber,
            action: '...',
            params: {},
            status: 'running',
          },
        ]);
        break;

      case 'STEP_ACTION':
        setSteps((prev) => {
          const updated = [...prev];
          const last = updated[updated.length - 1];
          if (last) {
            last.action = event.action;
            last.params = event.params;
          }
          return updated;
        });
        break;

      case 'STEP_RESULT':
        setSteps((prev) => {
          const updated = [...prev];
          const last = updated[updated.length - 1];
          if (last) {
            last.status = event.success ? 'success' : 'failed';
            if (event.success && event.data) {
              last.result = event.data.slice(0, 200);
            } else if (!event.success) {
              last.error = event.data;
            }
          }
          return updated;
        });
        break;

      case 'REPLAN':
        // Clear plan and steps for replanning
        setPlan([]);
        setSteps([]);
        setState('planning');
        break;

      case 'TASK_COMPLETE':
        setResult(event.result);
        setState('complete');
        break;

      case 'TASK_FAILED':
        setError(event.error);
        setState('error');
        break;

      // Obstacle handling events
      case 'OBSTACLE_DETECTED':
        setObstacle({
          type: event.obstacle,
          message: event.message,
        });
        break;

      case 'TASK_PAUSED':
        setState('paused');
        break;

      case 'TASK_RESUMED':
        setObstacle(null);
        setState('executing');
        break;

      case 'USER_ACTION_REQUIRED':
        // Additional UI hint could be shown here
        break;
    }
  }, []);

  // Submit a new task
  const handleSubmitTask = useCallback(
    (task: string, modelId: string, visionMode: boolean, vlmModelId: string) => {
      const payload = { task, modelId, visionMode, vlmModelId };

      // Try to reconnect if port is disconnected
      if (!port) {
        console.log('[Popup] Port disconnected, attempting to reconnect...');
        try {
          const newPort = chrome.runtime.connect({ name: POPUP_PORT_NAME });

          newPort.onMessage.addListener((message) => {
            console.log('[Popup] Received message:', message);
            if (message.type === 'EXECUTOR_EVENT') {
              handleExecutorEvent(message.event as ExecutorEvent);
            } else if (message.type === 'TASK_RESULT') {
              setResult(message.result);
              setState('complete');
            } else if (message.type === 'ERROR') {
              setError(message.error);
              setState('error');
            }
          });

          newPort.onDisconnect.addListener(() => {
            console.log('[Popup] Port disconnected');
            setPort(null);
          });

          setPort(newPort);

          // Reset state and send task
          setState('loading');
          setModelProgress(0);
          setPlan([]);
          setSteps([]);
          setResult(null);
          setError(null);

          newPort.postMessage({ type: 'START_TASK', payload });
          return;
        } catch (err) {
          console.error('[Popup] Reconnection failed:', err);
          setError('Failed to connect to background service. Try closing and reopening the popup.');
          setState('error');
          return;
        }
      }

      // Reset state
      setState('loading');
      setModelProgress(0);
      setPlan([]);
      setSteps([]);
      setResult(null);
      setError(null);

      // Send task to background
      port.postMessage({ type: 'START_TASK', payload });
    },
    [port, handleExecutorEvent]
  );

  // Cancel the running task
  const handleCancel = useCallback(() => {
    if (port) {
      port.postMessage({ type: 'CANCEL_TASK' });
      setState('idle');
      setModelProgress(0);
      setPlan([]);
      setSteps([]);
    }
  }, [port]);

  // Resume a paused task
  const handleResume = useCallback(() => {
    if (port) {
      port.postMessage({ type: 'RESUME_TASK' });
      setObstacle(null);
      setState('executing');
    }
  }, [port]);

  // Reset to initial state
  const handleReset = useCallback(() => {
    setState('idle');
    setModelProgress(0);
    setPlan([]);
    setSteps([]);
    setResult(null);
    setError(null);
    setObstacle(null);
  }, []);

  return (
    <div className="app">
      <header className="header">
        <h1>Local Browser</h1>
        <p>AI Web Automation (On-Device)</p>
      </header>

      <main className="main">
        {state === 'idle' && <TaskInput onSubmit={handleSubmitTask} />}

        {state === 'loading' && (
          <>
            <ModelStatus progress={modelProgress} />
            <button className="stop-button" onClick={handleCancel}>
              Stop
            </button>
          </>
        )}

        {(state === 'planning' || state === 'executing') && (
          <>
            <ProgressDisplay state={state} plan={plan} steps={steps} />
            <button className="stop-button" onClick={handleCancel}>
              Stop Task
            </button>
          </>
        )}

        {state === 'paused' && obstacle && (
          <div className="paused-view">
            <div className="obstacle-icon">
              {obstacle.type === 'LOGIN_REQUIRED' && '🔐'}
              {obstacle.type === 'CAPTCHA' && '🤖'}
              {obstacle.type === 'OUT_OF_STOCK' && '📦'}
              {obstacle.type === 'ERROR' && '⚠️'}
            </div>
            <h2>Action Required</h2>
            <div className="obstacle-message">
              {obstacle.type === 'LOGIN_REQUIRED' && 'Please sign in to your account in the browser tab.'}
              {obstacle.type === 'CAPTCHA' && 'Please solve the CAPTCHA in the browser tab.'}
              {obstacle.type === 'OUT_OF_STOCK' && 'This item is out of stock.'}
              {obstacle.type === 'ERROR' && obstacle.message}
            </div>
            <div className="paused-actions">
              <button className="resume-button" onClick={handleResume}>
                Resume Task
              </button>
              <button className="stop-button" onClick={handleCancel}>
                Cancel
              </button>
            </div>
            <ProgressDisplay state="executing" plan={plan} steps={steps} />
          </div>
        )}

        {state === 'complete' && result && (
          <ResultView result={result} onReset={handleReset} />
        )}

        {state === 'error' && error && (
          <div className="error-view">
            <h2>Error</h2>
            <div className="error-content">{error}</div>
            <button onClick={handleReset}>Try Again</button>
          </div>
        )}
      </main>
    </div>
  );
}
