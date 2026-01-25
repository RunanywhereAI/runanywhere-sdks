/**
 * Model Status Component
 *
 * Shows the loading progress of the WebLLM model.
 */

import React from 'react';

interface ModelStatusProps {
  progress: number;
}

export function ModelStatus({ progress }: ModelStatusProps): React.ReactElement {
  const percentage = Math.round(progress * 100);

  return (
    <div className="model-status">
      <h2>Loading AI Model</h2>

      <div className="progress-bar">
        <div
          className="progress-bar-fill"
          style={{ width: `${percentage}%` }}
        />
      </div>

      <div className="progress-text">
        {percentage < 100
          ? `Downloading and initializing... ${percentage}%`
          : 'Ready!'}
      </div>

      <p className="note">
        {percentage < 50
          ? 'First run may take a while as the model downloads (~1GB). It will be cached for future use.'
          : percentage < 100
          ? 'Almost there! Loading model into GPU memory...'
          : 'Model loaded successfully!'}
      </p>
    </div>
  );
}
