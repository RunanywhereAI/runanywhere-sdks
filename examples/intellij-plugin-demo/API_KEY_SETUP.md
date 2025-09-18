# API Key Setup for RunAnywhere IntelliJ Plugin

## Setting Up Your API Key

The RunAnywhere plugin requires an API key to authenticate with the backend. You can provide it in one of these ways:

### Option 1: Environment Variable (Recommended)
```bash
export RUNANYWHERE_API_KEY=your-api-key-here
```

### Option 2: JVM System Property
Add to your IntelliJ VM options:
```
-Drunanywhere.api.key=your-api-key-here
```

### Option 3: IntelliJ Run Configuration
1. Go to Run → Edit Configurations
2. Select your plugin configuration
3. Add to VM options: `-Drunanywhere.api.key=your-api-key-here`

## Getting an API Key

Contact the RunAnywhere team or visit the console to obtain your API key.

## Security Note

Never commit your API key to version control. Always use environment variables or system properties.
