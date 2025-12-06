/**
 * Event Polling Module
 *
 * Exports the EventPoller class and utilities for managing
 * thread-safe event queuing from native C++ code.
 */

export { EventPoller, getEventPoller, EventPollerSingleton, type QueuedEvent } from './EventPoller';
