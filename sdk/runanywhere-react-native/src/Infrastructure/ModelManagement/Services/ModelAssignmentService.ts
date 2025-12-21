/**
 * ModelAssignmentService.ts
 *
 * Service for fetching and managing model assignments from the backend.
 * Matches iOS Infrastructure/ModelManagement/Services/ModelAssignmentService.swift
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/ModelManagement/Services/ModelAssignmentService.swift
 */

import { SDKLogger } from '../../../Foundation/Logging/Logger/SDKLogger';
import type { APIClient } from '../../../Data/Network/Services/APIClient';
import { APIEndpoints } from '../../../Data/Network/Endpoints/APIEndpoints';
import type { ModelInfo } from '../../../types';
import { ModelCategory, ModelFormat, LLMFramework } from '../../../types/enums';
import type { SDKEnvironment } from '../../../types';

const logger = new SDKLogger('ModelAssignmentService');

/**
 * Cache timeout in milliseconds (1 hour)
 */
const CACHE_TIMEOUT_MS = 60 * 60 * 1000;

/**
 * Model assignment response from the API
 */
export interface ModelAssignmentResponse {
  models: ModelAssignment[];
  device_type: string;
  platform: string;
  timestamp: string;
}

/**
 * Individual model assignment from the API
 */
export interface ModelAssignment {
  id: string;
  name: string;
  version: string;
  category: string;
  format: string;
  download_url?: string;
  size?: number;
  memory_required?: number;
  context_length?: number;
  supports_thinking: boolean;
  compatible_frameworks: string[];
  preferred_framework?: string;
  metadata?: ModelAssignmentMetadata;
  is_required: boolean;
  priority: number;
}

/**
 * Metadata for model assignments
 */
export interface ModelAssignmentMetadata {
  description?: string;
  author?: string;
  license?: string;
  tags?: string[];
  capabilities?: string[];
  limitations?: string[];
}

/**
 * Convert API model assignment to SDK ModelInfo
 */
function toModelInfo(assignment: ModelAssignment): ModelInfo {
  // Convert string category to ModelCategory enum
  const category =
    (Object.values(ModelCategory).find(
      (c) => c.toLowerCase() === assignment.category.toLowerCase()
    ) as ModelCategory) || ModelCategory.Language;

  // Convert string format to ModelFormat enum
  const format =
    (Object.values(ModelFormat).find(
      (f) => f.toLowerCase() === assignment.format.toLowerCase()
    ) as ModelFormat) || ModelFormat.GGUF;

  // Convert string frameworks to LLMFramework enum
  const frameworks = assignment.compatible_frameworks
    .map((f) =>
      Object.values(LLMFramework).find(
        (lf) => lf.toLowerCase() === f.toLowerCase()
      )
    )
    .filter((f): f is LLMFramework => f !== undefined);

  const preferredFramework = assignment.preferred_framework
    ? (Object.values(LLMFramework).find(
        (lf) => lf.toLowerCase() === assignment.preferred_framework?.toLowerCase()
      ) as LLMFramework | undefined)
    : undefined;

  return {
    id: assignment.id,
    name: assignment.name,
    category,
    format,
    downloadURL: assignment.download_url,
    localPath: undefined,
    downloadSize: assignment.size,
    memoryRequired: assignment.memory_required,
    compatibleFrameworks: frameworks,
    preferredFramework,
    contextLength: assignment.context_length,
    supportsThinking: assignment.supports_thinking,
    tags: assignment.metadata?.tags ?? [],
    description: assignment.metadata?.description,
    source: 'remote' as const,
    createdAt: new Date(),
    updatedAt: new Date(),
    syncPending: false,
    lastUsed: undefined,
    usageCount: 0,
  };
}

/**
 * Model Assignment Service
 *
 * Fetches and caches model assignments from the backend.
 * Falls back to cached/local models on network failure.
 */
export class ModelAssignmentService {
  private readonly apiClient: APIClient;
  private readonly environment: SDKEnvironment;

  private cachedAssignments: ModelInfo[] | null = null;
  private lastFetchTime: number | null = null;

  private static _instance: ModelAssignmentService | null = null;

  constructor(apiClient: APIClient, environment: SDKEnvironment) {
    this.apiClient = apiClient;
    this.environment = environment;
    logger.info('ModelAssignmentService initialized');
  }

  /**
   * Get the singleton instance
   */
  static getInstance(apiClient: APIClient, environment: SDKEnvironment): ModelAssignmentService {
    if (!ModelAssignmentService._instance) {
      ModelAssignmentService._instance = new ModelAssignmentService(apiClient, environment);
    }
    return ModelAssignmentService._instance;
  }

  /**
   * Fetch model assignments for the current device from the backend
   *
   * @param forceRefresh - Force refresh even if cache is valid
   * @returns Array of ModelInfo objects assigned to this device
   */
  async fetchModelAssignments(forceRefresh = false): Promise<ModelInfo[]> {
    // Check cache first
    if (
      !forceRefresh &&
      this.cachedAssignments &&
      this.lastFetchTime &&
      Date.now() - this.lastFetchTime < CACHE_TIMEOUT_MS
    ) {
      logger.debug(
        `Returning cached model assignments (${this.cachedAssignments.length} models)`
      );
      return this.cachedAssignments;
    }

    logger.info('Fetching model assignments from backend...');

    // Get device info for the request
    let deviceType = 'phone';
    let platform = 'ios';

    try {
      const { requireDeviceInfoModule } = await import('../../../native');
      const deviceInfo = requireDeviceInfoModule();
      platform = deviceInfo.getPlatform?.() ?? 'ios';
      deviceType = 'phone'; // TODO: Detect phone vs tablet
    } catch {
      logger.debug('Native device info not available, using defaults');
    }

    try {
      const endpoint = APIEndpoints.modelAssignments(this.environment, {
        deviceType,
        platform,
      });

      const response = await this.apiClient.get<ModelAssignmentResponse>(
        endpoint.path
      );

      logger.info(`Received ${response.models.length} model assignments`);

      // Convert API models to SDK ModelInfo objects
      const modelInfos = response.models.map(toModelInfo);

      // Cache the results
      this.cachedAssignments = modelInfos;
      this.lastFetchTime = Date.now();

      logger.info('Model assignments cached');
      return modelInfos;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(`Failed to fetch model assignments: ${errorMessage}`);

      // Fall back to cached models if network fails
      if (this.cachedAssignments) {
        logger.info('Using cached models as fallback');
        return this.cachedAssignments;
      }

      throw error;
    }
  }

  /**
   * Get model assignments for a specific framework
   */
  async getModelsForFramework(framework: LLMFramework): Promise<ModelInfo[]> {
    const allModels = await this.fetchModelAssignments();
    return allModels.filter((m) => m.compatibleFrameworks?.includes(framework));
  }

  /**
   * Get model assignments for a specific category
   */
  async getModelsForCategory(category: ModelCategory): Promise<ModelInfo[]> {
    const allModels = await this.fetchModelAssignments();
    return allModels.filter((m) => m.category === category);
  }

  /**
   * Clear cached assignments
   */
  clearCache(): void {
    this.cachedAssignments = null;
    this.lastFetchTime = null;
    logger.debug('Model assignments cache cleared');
  }

  /**
   * Reset the singleton (for testing)
   */
  static reset(): void {
    ModelAssignmentService._instance = null;
  }
}

export default ModelAssignmentService;
