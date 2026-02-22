# IntelliJ Run Configurations

This folder contains the default IntelliJ run configurations scoped securely to ensure clean, isolated workflows across our composite builds (SDK, Android Example, and IntelliJ Plugin).

## Naming Convention
Configurations are organized explicitly to allow correct alphabetical and grouped sorting without relying on arbitrary platform-specific features (like Emojis).

**Format:** `{Project}__{Number}_{Action}.xml`
* **Prefix:** The overarching project section (e.g. `SDK`, `Android`, `IntelliJ`, `Utility`)
* **Separator:** Double underscore `__`
* **Number:** A single digit explicitly sorting the steps chronologically
* **Name:** A specific short name describing the action (e.g. `Build_App`)

## Available Configurations

### SDK (Kotlin SDK)
* **SDK: 1 Build** (`SDK__1_Build.xml`) - Builds the Kotlin SDK artifacts.
* **SDK: 2 Test** (`SDK__2_Test.xml`) - Runs the SDK unit tests.
* **SDK: 3 Publish to Maven Local** (`SDK__3_Publish_to_Maven_Local.xml`) - Publishes the SDK to Maven Local.

### Android
* **Android: 1 Build App** (`Android__1_Build_App.xml`) - Builds the Android sample app.
* **Android: 2 Run App on Device** (`Android__2_Run_App_on_Device.xml`) - Installs and runs the Android app on the targeted device.

### IntelliJ
* **IntelliJ: 1 Build Plugin** (`IntelliJ__1_Build_Plugin.xml`) - Builds the IntelliJ plugin example.
* **IntelliJ: 2 Run Plugin in Sandbox** (`IntelliJ__2_Run_Plugin_in_Sandbox.xml`) - Runs the IntelliJ plugin in an IDE sandbox window.

### Utility
* **Utility: Clean All** (`Utility__Clean_All.xml`) - Executes `cleanAll` task to purge build directories across all projects.