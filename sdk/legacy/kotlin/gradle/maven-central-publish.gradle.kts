/**
 * Maven Central Publishing Configuration
 *
 * This script configures publishing to Maven Central (Sonatype) for the RunAnywhere SDK.
 *
 * Usage:
 *   1. Set up Sonatype account at https://central.sonatype.com
 *   2. Verify namespace (com.runanywhere or io.github.runanywhereai)
 *   3. Generate GPG signing key
 *   4. Configure secrets in CI or local gradle.properties
 *
 * Local testing:
 *   ./gradlew publishToMavenLocal
 *
 * Publish to Maven Central:
 *   ./gradlew publishToMavenCentral
 */

// Apply signing plugin
apply(plugin = "signing")

// Get publishing credentials from environment or gradle.properties
val mavenCentralUsername: String? = System.getenv("MAVEN_CENTRAL_USERNAME")
    ?: project.findProperty("mavenCentral.username") as String?
val mavenCentralPassword: String? = System.getenv("MAVEN_CENTRAL_PASSWORD")
    ?: project.findProperty("mavenCentral.password") as String?

// GPG signing configuration
val signingKeyId: String? = System.getenv("GPG_KEY_ID")
    ?: project.findProperty("signing.keyId") as String?
val signingPassword: String? = System.getenv("GPG_SIGNING_PASSWORD")
    ?: project.findProperty("signing.password") as String?
val signingKey: String? = System.getenv("GPG_SIGNING_KEY")
    ?: project.findProperty("signing.key") as String?

// Determine if we should sign (required for Maven Central)
val shouldSign = signingKey != null || signingKeyId != null

configure<PublishingExtension> {
    repositories {
        // Maven Central (Sonatype)
        maven {
            name = "MavenCentral"
            url = uri("https://central.sonatype.com/api/v1/publisher/deployments/download")

            credentials {
                username = mavenCentralUsername
                password = mavenCentralPassword
            }
        }

        // Sonatype staging repository (for release workflow)
        maven {
            name = "SonatypeStaging"
            url = uri("https://s01.oss.sonatype.org/service/local/staging/deploy/maven2/")

            credentials {
                username = mavenCentralUsername
                password = mavenCentralPassword
            }
        }

        // GitHub Packages (backup)
        maven {
            name = "GitHubPackages"
            url = uri("https://maven.pkg.github.com/RunanywhereAI/runanywhere-sdks")

            credentials {
                username = System.getenv("GITHUB_ACTOR") ?: project.findProperty("gpr.user") as String?
                password = System.getenv("GITHUB_TOKEN") ?: project.findProperty("gpr.token") as String?
            }
        }
    }
}

// Configure signing for all publications
if (shouldSign) {
    configure<SigningExtension> {
        if (signingKey != null) {
            // Use in-memory key (from CI environment)
            useInMemoryPgpKeys(signingKeyId, signingKey, signingPassword)
        } else {
            // Use local GPG agent
            useGpgCmd()
        }

        // Sign all publications
        sign(the<PublishingExtension>().publications)
    }
}

// Log configuration for debugging
logger.lifecycle("Maven Central publishing configured:")
logger.lifecycle("  - Username: ${if (mavenCentralUsername != null) "✓" else "✗"}")
logger.lifecycle("  - Password: ${if (mavenCentralPassword != null) "✓" else "✗"}")
logger.lifecycle("  - Signing: ${if (shouldSign) "✓" else "✗ (artifacts will not be signed)"}")
