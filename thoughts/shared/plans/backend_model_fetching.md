# Backend Model Fetching Implementation Plan

## Overview
Implement complete model fetching from RunAnywhere backend API to display available models in the iOS app.

## Credentials
- **API Key**: `runa_prod_2wQMlC_fXcy8qnkaP3o1xjWV0xJAbA8T18EnalRWEgk`
- **Base URL**: `https://REDACTED_URL`

## Current State
- ✅ Model registry structure exists
- ✅ UI can display models
- ✅ Device registration with lazy loading
- ❌ Remote model fetching returns empty array
- ❌ Backend API endpoints not configured

## Implementation Steps

### 1. Update App Credentials
**File**: `RunAnywhereAI/App/RunAnywhereAIApp.swift`
- Update API key to production key
- Update base URL to Railway URL

### 2. Add API Endpoints
**File**: `Sources/RunAnywhere/Data/Network/Models/APIEndpoint.swift`
- Add case for `fetchModels`
- Add case for `fetchModel(id: String)`
- Add case for `downloadModel(id: String)`

### 3. Implement Remote Model Fetching
**File**: `Sources/RunAnywhere/Data/DataSources/ModelInfo/RemoteModelInfoDataSource.swift`

#### fetchAll() Implementation
```swift
public func fetchAll(filter: [String: Any]? = nil) async throws -> [ModelInfo] {
    guard let apiClient = apiClient else {
        throw DataSourceError.networkUnavailable
    }

    logger.debug("Fetching all models from backend")

    return try await operationHelper.withTimeout {
        // Call API endpoint
        let response = try await apiClient.request(
            .fetchModels,
            method: .get,
            responseType: ModelsResponse.self
        )

        // Convert response to ModelInfo objects
        return response.models.map { apiModel in
            ModelInfo(
                id: apiModel.id,
                name: apiModel.name,
                // ... map other fields
            )
        }
    }
}
```

### 4. Define Response Models
**File**: `Sources/RunAnywhere/Data/Network/Models/APIModels.swift`
```swift
struct ModelsResponse: Codable {
    let models: [APIModel]
}

struct APIModel: Codable {
    let id: String
    let name: String
    let description: String?
    let downloadUrl: String?
    let size: Int64?
    let format: String?
    let compatibleFrameworks: [String]
}
```

### 5. Update Model Repository
**File**: `Sources/RunAnywhere/Data/Repositories/ModelInfoRepositoryImpl.swift`
- Ensure it uses remote data source
- Add caching logic
- Handle offline scenarios

### 6. Integration Flow
1. App starts → SDK initializes with credentials
2. User opens model selection → Triggers `availableModels()`
3. SDK checks device registration (lazy)
4. SDK fetches models from backend
5. Models displayed in UI
6. User selects download → Triggers device registration if needed
7. Download proceeds with correct model ID

## API Endpoints to Implement

### GET /api/sdk/models
- Headers: `X-API-Key: {apiKey}`
- Response: List of available models

### GET /api/sdk/models/{modelId}
- Headers: `X-API-Key: {apiKey}`
- Response: Single model details

### POST /api/sdk/models/{modelId}/download
- Headers: `X-API-Key: {apiKey}`
- Response: Download URL or stream

## Testing Plan
1. Test API connectivity with curl
2. Test model list fetching
3. Test single model fetch
4. Test download functionality
5. Verify UI updates properly

## Success Criteria
- [ ] Models load from backend API
- [ ] Models display in UI
- [ ] Download button works
- [ ] Device registration happens on first API call
- [ ] No duplicate registrations
- [ ] Error handling for network issues
