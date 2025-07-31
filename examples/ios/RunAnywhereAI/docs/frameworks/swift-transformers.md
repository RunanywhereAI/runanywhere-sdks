# Swift Transformers Models - Complete Technical Guide

## Executive Summary

This guide provides comprehensive technical documentation for all Swift Transformers models integrated in RunAnywhereAI, including authentication requirements, API endpoints, download mechanisms, and production deployment considerations.

## Table of Contents

1. [Model Inventory](#model-inventory)
2. [Authentication Analysis](#authentication-analysis)
3. [API Endpoints & Technical Details](#api-endpoints--technical-details)
4. [Download Implementation](#download-implementation)
5. [Production Deployment Guide](#production-deployment-guide)
6. [Troubleshooting Reference](#troubleshooting-reference)

---

## Model Inventory

### Complete Model List with Specifications

#### 1. OpenELM-270M-Instruct

| Property | Value |
|----------|-------|
| **Model ID** | `openelm-270m-instruct-st` |
| **Display Name** | OpenELM-270M-Instruct-128-float32.mlpackage |
| **Repository** | corenet-community/coreml-OpenELM-270M-Instruct |
| **Format** | .mlpackage (directory-based) |
| **Size** | ~1GB |
| **Quantization** | Float32 |
| **Context Length** | 2048 tokens |
| **Memory Requirements** | Min: 600MB, Recommended: 1GB |
| **Authentication Required** | ❌ No (Public model) |
| **Download URL** | `https://huggingface.co/corenet-community/coreml-OpenELM-270M-Instruct/resolve/main/OpenELM-270M-Instruct-128-float32.mlpackage` |
| **HF Downloads** | 5 (as of verification) |

#### 2. OpenELM-450M-Instruct

| Property | Value |
|----------|-------|
| **Model ID** | `openelm-450m-instruct-st` |
| **Display Name** | OpenELM-450M-Instruct-128-float32.mlpackage |
| **Repository** | corenet-community/coreml-OpenELM-450M-Instruct |
| **Format** | .mlpackage (directory-based) |
| **Size** | ~1.7GB |
| **Quantization** | Float32 |
| **Context Length** | 2048 tokens |
| **Memory Requirements** | Min: 1GB, Recommended: 2GB |
| **Authentication Required** | ❌ No (Public model) |
| **Download URL** | `https://huggingface.co/corenet-community/coreml-OpenELM-450M-Instruct/resolve/main/OpenELM-450M-Instruct-128-float32.mlpackage` |
| **HF Downloads** | 19 (as of verification) |

#### 3. OpenELM-1.1B-Instruct

| Property | Value |
|----------|-------|
| **Model ID** | `openelm-1.1b-instruct-st` |
| **Display Name** | OpenELM-1_1B-Instruct-128-float32.mlpackage |
| **Repository** | corenet-community/coreml-OpenELM-1_1B-Instruct |
| **Format** | .mlpackage (directory-based) |
| **Size** | ~4.1GB |
| **Quantization** | Float32 |
| **Context Length** | 2048 tokens |
| **Memory Requirements** | Min: 2.5GB, Recommended: 4GB |
| **Authentication Required** | ❌ No (Public model) |
| **Download URL** | `https://huggingface.co/corenet-community/coreml-OpenELM-1_1B-Instruct/resolve/main/OpenELM-1_1B-Instruct-128-float32.mlpackage` |
| **HF Downloads** | 4 (as of verification) |

#### 4. OpenELM-3B-Instruct

| Property | Value |
|----------|-------|
| **Model ID** | `openelm-3b-instruct-st` |
| **Display Name** | OpenELM-3B-Instruct-128-float32.mlpackage |
| **Repository** | corenet-community/coreml-OpenELM-3B-Instruct |
| **Format** | .mlpackage (directory-based) |
| **Size** | ~11.3GB |
| **Quantization** | Float32 |
| **Context Length** | 2048 tokens |
| **Memory Requirements** | Min: 6GB, Recommended: 8GB |
| **Authentication Required** | ❌ No (Public model) |
| **Download URL** | `https://huggingface.co/corenet-community/coreml-OpenELM-3B-Instruct/resolve/main/OpenELM-3B-Instruct-128-float32.mlpackage` |
| **HF Downloads** | 4 (as of verification) |

---

## Authentication Analysis

### Verification Results

All Swift Transformers models were verified using the Python script (`scripts/verify_huggingface_auth_v2.py`) with the following findings:

| Model | Public Repo | Gated | Private | Auth Required |
|-------|-------------|-------|---------|---------------|
| OpenELM-270M | ✅ Yes | ❌ No | ❌ No | ❌ No |
| OpenELM-450M | ✅ Yes | ❌ No | ❌ No | ❌ No |
| OpenELM-1.1B | ✅ Yes | ❌ No | ❌ No | ❌ No |
| OpenELM-3B | ✅ Yes | ❌ No | ❌ No | ❌ No |

### Authentication Configuration

```swift
// HuggingFaceProvider configuration
requiresAuth: false  // Public models don't require auth
authType: .huggingFace
```

### Optional Authentication Benefits

While not required, users can provide a HuggingFace token for:
- **Higher rate limits**: 300 requests/hour vs 60 for anonymous
- **Faster downloads**: Priority bandwidth allocation
- **Private model access**: For future private model additions
- **Usage analytics**: Track download statistics

---

## API Endpoints & Technical Details

### 1. Model Information API

**Endpoint**: `https://huggingface.co/api/models/{owner}/{repo}`

**Example Request**:
```bash
curl https://huggingface.co/api/models/corenet-community/coreml-OpenELM-270M-Instruct
```

**Response Structure**:
```json
{
  "id": "corenet-community/coreml-OpenELM-270M-Instruct",
  "modelId": "corenet-community/coreml-OpenELM-270M-Instruct",
  "author": "corenet-community",
  "private": false,
  "gated": false,
  "disabled": false,
  "downloads": 5,
  "likes": 0,
  "library_name": "coreml",
  "tags": ["coreml", "swift-transformers", "openelm"]
}
```

### 2. File Tree API

**Endpoint**: `https://huggingface.co/api/models/{owner}/{repo}/tree/{branch}`

**Example Request**:
```bash
curl https://huggingface.co/api/models/corenet-community/coreml-OpenELM-270M-Instruct/tree/main
```

**Response Structure**:
```json
[
  {
    "type": "directory",
    "oid": "9746d72999ab77e1e90ff42a43d2d7c2256ab58e",
    "size": 0,
    "path": "OpenELM-270M-Instruct-128-float32.mlpackage"
  },
  {
    "type": "file",
    "oid": "a6344aac8c09253b3b630fb776ae94478aa0275b",
    "size": 1519,
    "path": ".gitattributes"
  }
]
```

### 3. Directory Contents API

**Endpoint**: `https://huggingface.co/api/models/{owner}/{repo}/tree/main/{directory}`

**Example Request**:
```bash
curl https://huggingface.co/api/models/corenet-community/coreml-OpenELM-270M-Instruct/tree/main/OpenELM-270M-Instruct-128-float32.mlpackage
```

### 4. File Download API

**Endpoint**: `https://huggingface.co/{owner}/{repo}/resolve/{branch}/{file_path}`

**Headers (Optional)**:
```
Authorization: Bearer {HF_TOKEN}
```

**Example**:
```bash
# Download a specific file from .mlpackage
curl -L https://huggingface.co/corenet-community/coreml-OpenELM-270M-Instruct/resolve/main/OpenELM-270M-Instruct-128-float32.mlpackage/Manifest.json
```

---

## Download Implementation

### Directory-Based Download Process

Since `.mlpackage` files are directories, the download process involves:

1. **List Directory Contents**
   ```swift
   // HuggingFaceDirectoryDownloader.swift
   let files = try await listFiles(repoId: repoId, path: directoryPath)
   ```

2. **Download Each File**
   ```swift
   for file in files {
       let downloadURL = "https://huggingface.co/\(repoId)/resolve/main/\(file.path)"
       // Download file to local directory structure
   }
   ```

3. **Reconstruct Directory Structure**
   ```
   Models/SwiftTransformers/
   └── OpenELM-270M-Instruct-128-float32.mlpackage/
       ├── Manifest.json
       ├── Data/
       │   └── com.apple.CoreML/
       │       └── model.mlmodel
       └── Metadata.json
   ```

### Download Progress Tracking

```swift
struct DownloadProgress {
    let bytesWritten: Int64
    let totalBytes: Int64
    let fractionCompleted: Double
    let estimatedTimeRemaining: TimeInterval?
    let downloadSpeed: Double
}
```

### Error Handling

| Error Type | Handling |
|------------|----------|
| Network Error | Retry with exponential backoff |
| 401 Unauthorized | Prompt for authentication |
| 429 Rate Limited | Suggest adding token or wait |
| Insufficient Storage | Check before download |
| Corrupted File | Verify checksums if available |

---

## Production Deployment Guide

### 1. Pre-Production Checklist

- [x] **Authentication**: Set to `requiresAuth: false` for public models
- [x] **Error Messages**: Clear, actionable error messages
- [x] **Progress Tracking**: Detailed progress for multi-file downloads
- [x] **Background Downloads**: Enabled for large models
- [x] **Storage Checks**: Verify available space before download
- [x] **Network Resilience**: Handle interruptions gracefully

### 2. Security Considerations

```swift
// Token Storage (iOS Keychain)
let keychain = KeychainService()
keychain.save(key: "huggingface_token", data: tokenData)

// No hardcoded tokens
// All authentication is user-provided
// Tokens are optional for public models
```

### 3. Performance Optimizations

- **Parallel Downloads**: Download multiple files concurrently
- **Chunked Downloads**: Support resume for large files
- **Compression**: Models are pre-compressed by HuggingFace
- **Cache Management**: Clean up partial downloads

### 4. User Experience Guidelines

1. **Clear Status Indicators**
   - "Preparing" → "Downloading (X/Y files)" → "Verifying" → "Complete"

2. **Accurate Progress**
   - Show both file count and size progress
   - Display download speed and time remaining

3. **Graceful Failures**
   - Allow retry without re-downloading completed files
   - Provide specific error reasons

---

## Troubleshooting Reference

### Common Issues and Solutions

#### 1. Model Shows "Authentication Required" Despite Being Public

**Symptom**: Public models request authentication
**Solution**: Ensure `requiresAuth: false` in ModelURLRegistry

#### 2. 404 Errors on .mlpackage Downloads

**Symptom**: Direct URL returns 404
**Solution**: Use HuggingFaceDirectoryDownloader for directory-based models

#### 3. Slow Download Speeds

**Symptom**: Downloads are slower than expected
**Solutions**:
- Add HuggingFace token for better rate limits
- Check if on cellular (app restricts to WiFi)
- Verify no VPN interference

#### 4. Partial Downloads

**Symptom**: Model fails to load after download
**Solution**: Implement file count verification:
```swift
let expectedFiles = getExpectedFileCount(for: model)
let downloadedFiles = countFilesInDirectory(modelPath)
assert(expectedFiles == downloadedFiles)
```

### Debug Commands

```bash
# Check if model is public
curl -s https://huggingface.co/api/models/{repo} | jq '.private, .gated'

# List model files
curl -s https://huggingface.co/api/models/{repo}/tree/main | jq '.[].path'

# Test file accessibility
curl -I https://huggingface.co/{repo}/resolve/main/{file_path}

# Test with authentication
curl -H "Authorization: Bearer {token}" -I https://huggingface.co/{repo}/resolve/main/{file_path}
```

### Logging for Production

```swift
// Recommended logging points
Logger.info("Starting download for model: \(modelId)")
Logger.debug("Download URL: \(url)")
Logger.info("Download progress: \(progress)%")
Logger.error("Download failed: \(error.localizedDescription)")
Logger.info("Download completed: \(modelId)")
```

---

## Summary

The Swift Transformers integration in RunAnywhereAI:
- ✅ All models are publicly accessible without authentication
- ✅ Proper handling of directory-based .mlpackage format
- ✅ Robust error handling and retry mechanisms
- ✅ Clear progress tracking for multi-file downloads
- ✅ Production-ready with security and performance optimizations

The implementation correctly sets `requiresAuth: false` while supporting optional authentication for enhanced features.