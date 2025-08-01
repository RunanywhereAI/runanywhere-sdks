# Kaggle Model Download Guide

## Overview

This guide explains how to download TensorFlow Lite models from Kaggle in the RunAnywhereAI app.

## Prerequisites

1. **Kaggle Account**: You need a Kaggle account. Sign up at [kaggle.com](https://www.kaggle.com)
2. **API Credentials**: Generate API credentials from your Kaggle account settings
3. **Accept Model Terms**: You must accept the model's terms of use on Kaggle before downloading

## Step 1: Get Kaggle API Credentials

1. Go to [kaggle.com](https://www.kaggle.com) and sign in
2. Click on your profile picture → **Account**
3. Scroll down to the **API** section
4. Click **Create New API Token**
5. This downloads a `kaggle.json` file containing:
   ```json
   {
     "username": "your_username",
     "key": "your_api_key"
   }
   ```
6. Save these credentials - you'll need them in the app

## Step 2: Configure Credentials in the App

1. Open RunAnywhereAI
2. Go to **Settings** → **API Credentials**
3. In the Kaggle section:
   - Enter your username
   - Enter your API key
   - Tap **Save**

## Step 3: Accept Model Terms on Kaggle

**Important**: Before downloading any Kaggle model, you must accept its terms of use:

1. Visit the model page on Kaggle:
   - [Gemma Models](https://www.kaggle.com/models/google/gemma)
   - Navigate to the specific model variant you want
2. Look for the **Terms** or **License** section
3. Click **Accept** to agree to the terms
4. You only need to do this once per model

## Step 4: Download Models in the App

1. Go to the **Models** tab
2. Select **TensorFlow Lite** framework
3. Find Kaggle-hosted models (marked with 🔒)
4. Tap **Download**

## Troubleshooting

### "User has not consented to terms of use" Error

This means you haven't accepted the model's terms on Kaggle:
1. Visit the model's Kaggle page
2. Accept the terms
3. Try downloading again

### "Invalid credentials" Error

1. Verify your username and API key are correct
2. Make sure there are no extra spaces
3. Try generating a new API token on Kaggle

### "Model not found" Error

The model may have been removed or the version changed. Check the model's Kaggle page for current availability.

## Available Kaggle TFLite Models

| Model | Size | Description | Kaggle Page |
|-------|------|-------------|-------------|
| Gemma 2B GPU INT4 | ~1.35GB | GPU-optimized with INT4 quantization | [View](https://www.kaggle.com/models/google/gemma/frameworks/tfLite/variations/gemma-2b-it-gpu-int4) |
| Gemma 2B CPU INT8 | ~2.5GB | CPU-optimized with INT8 quantization | [View](https://www.kaggle.com/models/google/gemma/frameworks/tfLite/variations/gemma-2b-it-cpu-int8) |

## Technical Details

### API Endpoint Format

Kaggle uses the following REST API format for model downloads:
```
GET https://www.kaggle.com/api/v1/models/{owner}/{model}/{framework}/{variation}/{version}/download
```

Authentication is via HTTP Basic Auth using your username and API key.

### File Formats

- Models are typically downloaded as `.tar.gz` archives
- These need to be extracted after download
- The archive contains the `.tflite` model file and associated metadata

## Security Notes

- Your API credentials are stored securely in the iOS Keychain
- Never share your API key publicly
- API keys can be revoked and regenerated on Kaggle if compromised
