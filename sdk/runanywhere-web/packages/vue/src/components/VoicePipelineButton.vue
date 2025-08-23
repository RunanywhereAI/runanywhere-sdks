<template>
  <button
    @click="handleClick"
    :disabled="disabled || (state.isProcessing && !state.isListening)"
    :class="buttonClasses"
    :style="customStyle"
  >
    <span v-if="showIcon" class="ra-vp-button__icon">
      <svg v-if="!state.isListening" width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
        <path d="M12 14c1.66 0 3-1.34 3-3V5c0-1.66-1.34-3-3-3S9 3.34 9 5v6c0 1.66 1.34 3 3 3z"/>
        <path d="M17 11c0 2.76-2.24 5-5 5s-5-2.24-5-5H5c0 3.53 2.61 6.43 6 6.92V21h2v-3.08c3.39-.49 6-3.39 6-6.92h-2z"/>
      </svg>
      <svg v-else width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
        <rect x="6" y="4" width="4" height="16"/>
        <rect x="14" y="4" width="4" height="16"/>
      </svg>
    </span>
    <span v-if="state.isListening && showPulse" class="ra-pulse"></span>
    <span class="ra-vp-button__text">{{ displayText }}</span>
  </button>
</template>

<script setup lang="ts">
import { computed, onMounted } from 'vue';
import { useVoicePipeline } from '../composables/useVoicePipeline';
import type { VoicePipelineConfig } from '../types';

interface Props {
  config?: VoicePipelineConfig;
  variant?: 'primary' | 'secondary' | 'outline';
  size?: 'small' | 'medium' | 'large';
  showIcon?: boolean;
  showPulse?: boolean;
  customText?: {
    initialize?: string;
    start?: string;
    stop?: string;
    processing?: string;
  };
  disabled?: boolean;
  autoInitialize?: boolean;
  className?: string;
  customStyle?: Record<string, any>;
}

const props = withDefaults(defineProps<Props>(), {
  variant: 'primary',
  size: 'medium',
  showIcon: true,
  showPulse: true,
  disabled: false,
  autoInitialize: false
});

const {
  state,
  buttonText,
  initialize,
  start,
  stop
} = useVoicePipeline(props.config);

const displayText = computed(() => {
  if (props.customText) {
    if (!state.isInitialized && props.customText.initialize) {
      return props.customText.initialize;
    }
    if (state.isProcessing && props.customText.processing) {
      return props.customText.processing;
    }
    if (state.isListening && props.customText.stop) {
      return props.customText.stop;
    }
    if (!state.isListening && state.isInitialized && props.customText.start) {
      return props.customText.start;
    }
  }
  return buttonText.value;
});

const buttonClasses = computed(() => {
  const classes = ['ra-vp-button'];

  // Add variant class
  classes.push(`ra-vp-button--${props.variant}`);

  // Add size class
  classes.push(`ra-vp-button--${props.size}`);

  // Add state classes
  if (state.isListening) {
    classes.push('ra-vp-button--listening');
  }
  if (state.isProcessing) {
    classes.push('ra-vp-button--processing');
  }
  if (state.error) {
    classes.push('ra-vp-button--error');
  }

  // Add custom class if provided
  if (props.className) {
    classes.push(props.className);
  }

  return classes;
});

const handleClick = async () => {
  try {
    if (!state.isInitialized) {
      await initialize();
      if (props.config?.autoStart) {
        await start();
      }
    } else if (state.isListening) {
      await stop();
    } else {
      await start();
    }
  } catch (error) {
    console.error('Voice pipeline error:', error);
  }
};

// Auto-initialize if requested
onMounted(async () => {
  if (props.autoInitialize) {
    try {
      await initialize();
    } catch (error) {
      console.error('Failed to auto-initialize:', error);
    }
  }
});
</script>

<style scoped>
.ra-vp-button {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  border: none;
  border-radius: 6px;
  font-weight: 500;
  cursor: pointer;
  transition: all 0.2s ease;
  position: relative;
  overflow: hidden;
}

.ra-vp-button:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.ra-vp-button:focus {
  outline: 2px solid transparent;
  outline-offset: 2px;
}

.ra-vp-button:focus-visible {
  box-shadow: 0 0 0 2px white, 0 0 0 4px #3b82f6;
}

/* Variants */
.ra-vp-button--primary {
  background: #10b981;
  color: white;
}

.ra-vp-button--primary:hover:not(:disabled) {
  background: #059669;
}

.ra-vp-button--primary.ra-vp-button--listening {
  background: #ef4444;
}

.ra-vp-button--primary.ra-vp-button--listening:hover:not(:disabled) {
  background: #dc2626;
}

.ra-vp-button--primary.ra-vp-button--processing {
  background: #f59e0b;
}

.ra-vp-button--secondary {
  background: #6b7280;
  color: white;
}

.ra-vp-button--secondary:hover:not(:disabled) {
  background: #4b5563;
}

.ra-vp-button--outline {
  background: transparent;
  color: #10b981;
  border: 2px solid #10b981;
}

.ra-vp-button--outline:hover:not(:disabled) {
  background: #10b981;
  color: white;
}

.ra-vp-button--outline.ra-vp-button--listening {
  border-color: #ef4444;
  color: #ef4444;
}

.ra-vp-button--outline.ra-vp-button--listening:hover:not(:disabled) {
  background: #ef4444;
  color: white;
}

/* Sizes */
.ra-vp-button--small {
  padding: 6px 12px;
  font-size: 12px;
}

.ra-vp-button--medium {
  padding: 10px 20px;
  font-size: 14px;
}

.ra-vp-button--large {
  padding: 14px 28px;
  font-size: 16px;
}

/* Icon */
.ra-vp-button__icon {
  display: inline-flex;
  align-items: center;
  justify-content: center;
}

/* Error state */
.ra-vp-button--error {
  animation: shake 0.5s;
}

@keyframes shake {
  0%, 100% { transform: translateX(0); }
  10%, 30%, 50%, 70%, 90% { transform: translateX(-2px); }
  20%, 40%, 60%, 80% { transform: translateX(2px); }
}

/* Pulse animation */
.ra-pulse {
  position: absolute;
  top: 8px;
  right: 8px;
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: currentColor;
  animation: pulse 1.5s infinite;
}

@keyframes pulse {
  0%, 100% {
    opacity: 1;
    transform: scale(1);
  }
  50% {
    opacity: 0.5;
    transform: scale(1.1);
  }
}

/* Ripple effect on click */
.ra-vp-button::before {
  content: '';
  position: absolute;
  top: 50%;
  left: 50%;
  width: 0;
  height: 0;
  border-radius: 50%;
  background: rgba(255, 255, 255, 0.5);
  transform: translate(-50%, -50%);
  transition: width 0.6s, height 0.6s;
}

.ra-vp-button:active::before {
  width: 300px;
  height: 300px;
}
</style>
