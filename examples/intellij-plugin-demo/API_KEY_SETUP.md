# API Configuration for RunAnywhere IntelliJ Plugin

## Required Configuration

The RunAnywhere plugin requires both an API URL and API key to connect to your backend.

### Setting Up Your API URL and Key

#### Option 1: Environment Variables (Recommended)
```bash
export RUNANYWHERE_API_URL=https://your-api-url.com
export RUNANYWHERE_API_KEY=your-api-key-here
```

#### Option 2: JVM System Properties
Add to your IntelliJ VM options:
```
-Drunanywhere.api.url=https://your-api-url.com
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
