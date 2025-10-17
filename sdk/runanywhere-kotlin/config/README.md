# SDK Configuration Management

This directory contains configuration files for the RunAnywhere Kotlin SDK. The configuration system allows you to easily switch between development, staging, and production environments without modifying code or committing sensitive data to Git.

## Overview

The SDK uses a JSON-based configuration system that:
- Keeps sensitive URLs and API keys out of source control
- Allows easy switching between environments
- Supports dev, staging, and production configurations
- Automatically loads the appropriate configuration during build

## Directory Structure

```
config/
├── README.md              # This file
├── template.json          # Empty template with all fields
├── dev.example.json       # Example development configuration
├── staging.example.json   # Example staging configuration
├── prod.example.json      # Example production configuration
├── dev.json              # Your actual dev config (git-ignored)
├── staging.json          # Your actual staging config (git-ignored)
└── prod.json             # Your actual production config (git-ignored)
```

## Quick Start

### 1. Set Up Development Configuration

```bash
# From the SDK root directory
./scripts/sdk.sh config-dev
```

This will:
- Copy `dev.example.json` to `dev.json` if it doesn't exist
- Load the configuration for development use
- Prompt you to edit the file with your actual values

### 2. Edit Configuration

Edit the generated `config/dev.json` with your actual values:

```json
{
  "environment": "DEVELOPMENT",
  "apiBaseUrl": "https://your-dev-api.com",
  "cdnBaseUrl": "https://your-dev-cdn.com",
  "defaultApiKey": "your-dev-api-key",
  ...
}
```

### 3. Build with Configuration

```bash
# Build with specific environment
./scripts/sdk.sh jvm --env dev
./scripts/sdk.sh jvm --env staging
./scripts/sdk.sh jvm --env prod

# Or set configuration first, then build
./scripts/sdk.sh config-dev
./scripts/sdk.sh jvm
```

## Available Commands

### Configuration Commands

```bash
# Set up for specific environment
./scripts/config-manager.sh setup dev
./scripts/config-manager.sh setup staging
./scripts/config-manager.sh setup prod

# Generate config from template
./scripts/config-manager.sh generate dev

# Validate current configuration
./scripts/config-manager.sh validate

# Show current config (sensitive data masked)
./scripts/config-manager.sh show

# Clean generated files
./scripts/config-manager.sh clean
```

### SDK Build Commands with Config

```bash
# Via sdk.sh
./scripts/sdk.sh config-dev        # Configure for development
./scripts/sdk.sh config-staging    # Configure for staging
./scripts/sdk.sh config-prod       # Configure for production
./scripts/sdk.sh config-show       # Show current config
./scripts/sdk.sh config-validate   # Validate config

# Build with environment flag
./scripts/sdk.sh jvm --env dev
./scripts/sdk.sh publish --env prod
```

## Configuration Fields

### Environment Settings
- `environment`: "DEVELOPMENT", "STAGING", or "PRODUCTION"
- `apiBaseUrl`: Base URL for API endpoints
- `cdnBaseUrl`: Base URL for CDN/downloads
- `telemetryUrl`: Telemetry service URL
- `analyticsUrl`: Analytics service URL
- `defaultApiKey`: Default API key for the environment

### Feature Flags
- `enableVerboseLogging`: Enable detailed logging
- `enableMockServices`: Use mock services instead of real ones
- `features.*`: Various feature toggles

### Model URLs
- `modelUrls.*`: Download URLs for various AI models

## Security Notes

⚠️ **IMPORTANT**:
- Never commit `dev.json`, `staging.json`, or `prod.json` to Git
- These files are automatically ignored by `.gitignore`
- Only commit the `.example.json` files with placeholder values
- Store real credentials in a secure location (e.g., password manager, secrets vault)

## CI/CD Integration

For CI/CD pipelines, you can:

1. **Use environment variables**:
```bash
# Create config from environment variables
cat > config/prod.json << EOF
{
  "environment": "PRODUCTION",
  "apiBaseUrl": "$API_BASE_URL",
  "defaultApiKey": "$API_KEY",
  ...
}
EOF

# Then build
./scripts/sdk.sh jvm --env prod
```

2. **Use secret management**:
```bash
# Download config from secret store
aws secretsmanager get-secret-value \
  --secret-id runanywhere-sdk-prod-config \
  --query SecretString \
  --output text > config/prod.json

# Build with production config
./scripts/config-manager.sh setup prod
./gradlew build
```

## Troubleshooting

### Configuration not found
```bash
# Check if config exists
ls -la config/

# Generate from template
./scripts/config-manager.sh generate dev
```

### Invalid configuration
```bash
# Validate JSON syntax
./scripts/config-manager.sh validate

# Check with Python
python3 -m json.tool config/dev.json
```

### Configuration not loading
```bash
# Clean and regenerate
./scripts/config-manager.sh clean
./scripts/config-manager.sh setup dev
```

## Development Workflow

1. **Initial Setup**:
   ```bash
   # Clone repository
   git clone <repo>
   cd sdk/runanywhere-kotlin

   # Set up dev config
   ./scripts/sdk.sh config-dev
   # Edit config/dev.json with your values
   ```

2. **Daily Development**:
   ```bash
   # Ensure config is loaded
   ./scripts/sdk.sh config-dev

   # Build and test
   ./scripts/sdk.sh jvm
   ./scripts/sdk.sh test
   ```

3. **Testing Different Environments**:
   ```bash
   # Test with staging config
   ./scripts/sdk.sh config-staging
   ./scripts/sdk.sh test

   # Test with production config
   ./scripts/sdk.sh config-prod
   ./scripts/sdk.sh test
   ```

4. **Release Build**:
   ```bash
   # Build for production
   ./scripts/sdk.sh config-prod
   ./scripts/sdk.sh all --env prod
   ./scripts/sdk.sh publish --env prod
   ```

## Best Practices

1. **Keep configs minimal**: Only include necessary environment-specific values
2. **Use consistent naming**: Follow the same structure across all environments
3. **Document changes**: Update example files when adding new config fields
4. **Validate regularly**: Run validation before commits and deployments
5. **Rotate credentials**: Regularly update API keys and credentials
6. **Use environment detection**: Let the SDK auto-detect environment when possible

## Support

For issues or questions about configuration:
1. Check this README first
2. Review the example configuration files
3. Run validation to check for errors
4. Contact the SDK team if needed
