/**
 * Network module exports
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Data/Network/
 */

// Endpoints
export {
  type APIEndpointType,
  type APIEndpointDefinition,
  APIEndpoints,
  authenticateEndpoint,
  refreshTokenEndpoint,
  healthCheckEndpoint,
  deviceRegistrationEndpoint,
  analyticsEndpoint,
  devDeviceRegistrationEndpoint,
  devAnalyticsEndpoint,
  modelAssignmentsEndpoint,
  telemetryEndpoint,
  modelsEndpoint,
  deviceInfoEndpoint,
  generationHistoryEndpoint,
  userPreferencesEndpoint,
  deviceRegistrationEndpointForEnvironment,
  analyticsEndpointForEnvironment,
} from './APIEndpoint';

// Services
export {
  type NetworkService,
  type APIEndpoint,
  NetworkServiceImpl,
} from './Services/NetworkService';

export {
  APIClient,
  APIClientError,
  createAPIClient,
  type APIClientConfig,
  type AuthenticationProvider,
} from './Services/APIClient';

export { AuthenticationService } from './Services/AuthenticationService';

// Models
export {
  type AuthenticationRequest,
  type AuthenticationResponse,
  type RefreshTokenRequest,
  type RefreshTokenResponse,
  type DeviceRegistrationRequest,
  type DeviceRegistrationResponse,
  type HealthCheckResponse,
  toInternalAuthResponse,
  createAuthRequest,
  createRefreshRequest,
} from './Models/AuthModels';
