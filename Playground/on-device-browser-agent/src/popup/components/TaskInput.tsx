/**
 * Task Input Component
 *
 * Allows users to enter natural language tasks for the AI agent to execute.
 */

import React, { useState, useCallback } from 'react';
import { AVAILABLE_LLM_MODELS, DEFAULT_MODEL } from '../../shared/constants';

interface TaskInputProps {
  onSubmit: (task: string, modelId: string, visionMode: boolean, vlmModelId: string) => void;
}

const EXAMPLE_TASKS = [
  'Go to Wikipedia and search for "WebGPU"',
  'Search Google for "latest AI news"',
  'Go to example.com and tell me what\'s there',
];

export function TaskInput({ onSubmit }: TaskInputProps): React.ReactElement {
  const [task, setTask] = useState('');
  const [modelId, setModelId] = useState(DEFAULT_MODEL);

  const handleSubmit = useCallback(
    (e: React.FormEvent) => {
      e.preventDefault();
      if (task.trim()) {
        // Vision mode disabled - always pass false
        onSubmit(task.trim(), modelId, false, 'small');
      }
    },
    [task, modelId, onSubmit]
  );

  const handleExampleClick = useCallback((example: string) => {
    setTask(example);
  }, []);

  return (
    <form className="task-input" onSubmit={handleSubmit}>
      <textarea
        value={task}
        onChange={(e) => setTask(e.target.value)}
        placeholder="Describe what you want to automate...&#10;&#10;Example: Search for 'WebGPU' on Wikipedia and extract the first paragraph"
        autoFocus
      />

      <div className="model-settings">
        <div className="model-select">
          <label htmlFor="llm-select">LLM:</label>
          <select
            id="llm-select"
            value={modelId}
            onChange={(e) => setModelId(e.target.value)}
          >
            {AVAILABLE_LLM_MODELS.map((model) => (
              <option key={model.id} value={model.id}>
                {model.name} - {model.size} ({model.context} ctx)
              </option>
            ))}
          </select>
        </div>

        <div className="vision-toggle">
          <label className="vision-disabled">
            <input
              type="checkbox"
              checked={false}
              disabled
            />
            Vision Mode
          </label>
          <span className="vision-badge vision-unavailable" title="Vision mode unavailable: Chrome MV3 blocks required CDN imports for Transformers.js">
            N/A
          </span>
        </div>
      </div>

      <button type="submit" disabled={!task.trim()}>
        Run Task
      </button>

      <div className="examples">
        <div className="examples-label">Try an example:</div>
        <div className="examples-list">
          {EXAMPLE_TASKS.map((example, index) => (
            <button
              key={index}
              type="button"
              className="example-chip"
              onClick={() => handleExampleClick(example)}
            >
              {example.slice(0, 30)}...
            </button>
          ))}
        </div>
      </div>
    </form>
  );
}
