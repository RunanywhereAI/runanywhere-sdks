/**
 * RunAnywhere Shared Build Conventions Plugin
 *
 * Provides shared build utilities for all SDK modules, including:
 * - Module path resolution for composite builds
 * - (Future) Common publishing configuration
 * - (Future) Shared version catalogs
 * - (Future) Common code quality settings
 *
 * Usage:
 *   plugins {
 *       id("runanywhere.conventions")
 *   }
 *
 *   // Then use the extension functions:
 *   val onnxPath = resolveModulePath("runanywhere-core-onnx")
 */

/**
 * Resolves the correct Gradle module path for a given module name.
 *
 * Handles multiple scenarios:
 * - SDK as root project: path = ":" → ":modules:$moduleName"
 * - SDK as subproject: path = ":sdk:runanywhere-kotlin" → ":sdk:runanywhere-kotlin:modules:$moduleName"
 * - Composite builds from example apps or Android Studio
 *
 * @param moduleName The module name (e.g., "runanywhere-core-onnx")
 * @return The resolved Gradle module path
 */
fun Project.resolveModulePath(moduleName: String): String {
    val basePath = this.path
    val computedPath = if (basePath == ":") {
        ":modules:$moduleName"
    } else {
        "$basePath:modules:$moduleName"
    }

    // Try to find the project using rootProject to handle Android Studio sync ordering
    val foundProject = rootProject.findProject(computedPath)
    if (foundProject != null) {
        return computedPath
    }

    // Fallback: Try just :modules:$moduleName (when SDK is at non-root but modules are siblings)
    val simplePath = ":modules:$moduleName"
    if (rootProject.findProject(simplePath) != null) {
        return simplePath
    }

    // Return computed path (will fail with clear error if not found)
    return computedPath
}
