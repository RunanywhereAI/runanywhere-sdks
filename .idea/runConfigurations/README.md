# Run Configurations

IntelliJ/Android Studio run configurations for the RunAnywhere SDK project.

## First Time? Start Here

If you just cloned the repo, run **"Setup: 1 - First Time Setup (Do Everything)"** from the run dropdown.
It will check your environment, create all config files, and build everything in one click.

## Naming Convention

All configuration files follow the pattern:

```
{Category}__{Number}_{Description}.xml
```

- **Category**: Project group prefix (`Setup`, `SDK`, `Android`, `IntelliJ`, `Utility`)
- **Double underscore** (`__`): Separator between category and description
- **Number**: Ordering within the category
- **Description**: Short, descriptive name using underscores

Display names in IntelliJ follow the pattern: `{Category}: {Number} - {Description}`

## Available Configurations

### Setup (First-Time & Environment)

| File | Display Name | Gradle Task | Description |
|------|-------------|-------------|-------------|
| `Setup__1_First_Time_Setup.xml` | Setup: 1 - First Time Setup (Do Everything) | `firstTimeSetup` | One-click: checks env, creates config files, builds everything |
| `Setup__2_Check_Environment.xml` | Setup: 2 - Check Environment | `checkEnvironment` | Verify Android SDK, NDK, and local.properties |
| `Setup__3_Setup_Local_Properties.xml` | Setup: 3 - Setup Local Properties | `setupLocalProperties` | Create local.properties in all project directories |

### SDK (Kotlin Multiplatform SDK)

| File | Display Name | Gradle Task | Description |
|------|-------------|-------------|-------------|
| `SDK__1_Build.xml` | SDK: 1 - Build | `buildSdk` | Build the SDK (debug AAR) |
| `SDK__2_Test.xml` | SDK: 2 - Test | `:runanywhere-kotlin:allTests` | Run all SDK tests (JVM + Android) |
| `SDK__3_Publish_to_Maven_Local.xml` | SDK: 3 - Publish to Maven Local | `publishSdkToMavenLocal` | Publish SDK to `~/.m2/repository` |
| `SDK__4_Build_All.xml` | SDK: 4 - Build All (SDK + Apps) | `buildAll` | Build SDK + Android app + IntelliJ plugin |
| `SDK__5_Build_Release.xml` | SDK: 5 - Build Release | `buildSdkRelease` | Build SDK release variant |

### Android (Sample App)

| File | Display Name | Gradle Task | Description |
|------|-------------|-------------|-------------|
| `Android__1_Build_App.xml` | Android: 1 - Build App | `buildAndroidApp` | Build the Android sample app |
| `Android__2_Run_App_on_Device.xml` | Android: 2 - Run App on Device | `runAndroidApp` | Build, install, and launch on connected device |

### IntelliJ (Plugin Demo)

| File | Display Name | Gradle Task | Description |
|------|-------------|-------------|-------------|
| `IntelliJ__1_Build_Plugin.xml` | IntelliJ: 1 - Build Plugin | `buildIntellijPlugin` | Publish SDK to Maven Local, then build plugin |
| `IntelliJ__2_Run_Plugin_in_Sandbox.xml` | IntelliJ: 2 - Run Plugin in Sandbox | `runIntellijPlugin` | Publish SDK to Maven Local, then launch in sandbox |

### Utility

| File | Display Name | Gradle Task | Description |
|------|-------------|-------------|-------------|
| `Utility__1_Clean_All.xml` | Utility: 1 - Clean All | `cleanAll` | Clean SDK, Android app, and IntelliJ plugin |

## IntelliJ UI Grouping

Configurations sort alphabetically by filename, resulting in this grouped order:

1. `Android__*` - Android sample app tasks
2. `IntelliJ__*` - IntelliJ plugin tasks
3. `SDK__*` - SDK build/test/publish tasks
4. `Setup__*` - Environment setup tasks
5. `Utility__*` - Maintenance tasks

## Adding New Configurations

1. Choose the appropriate category prefix
2. Number sequentially within the category
3. Use a short descriptive name (underscores, no spaces or emojis)
4. Set the display name to match: `{Category}: {Number} - {Description}`
