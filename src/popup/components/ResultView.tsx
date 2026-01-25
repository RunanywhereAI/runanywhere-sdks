/**
 * Result View Component
 *
 * Displays the final result of a completed task.
 */

import React from 'react';

interface ResultViewProps {
  result: string;
  onReset: () => void;
}

export function ResultView({ result, onReset }: ResultViewProps): React.ReactElement {
  return (
    <div className="result-view">
      <h2>Task Complete</h2>

      <div className="result-content">{result}</div>

      <button onClick={onReset}>New Task</button>
    </div>
  );
}
