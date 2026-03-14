package com.runanywhere.buildlogic

import org.gradle.api.DefaultTask
import org.gradle.api.Plugin
import org.gradle.api.Project
import org.gradle.api.file.ArchiveOperations
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.file.FileSystemOperations
import org.gradle.api.file.RelativePath
import org.gradle.api.provider.ListProperty
import org.gradle.api.provider.Property
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.TaskAction
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import javax.inject.Inject

// A Gradle plugin that provides a task to securely download and verify native libraries using SHA-256 checksums.
abstract class DownloadAndVerifyNativeLibTask @Inject constructor(
    private val fsOps: FileSystemOperations,
    private val archiveOps: ArchiveOperations
) : DefaultTask() {

    // Inputs for the task: download URL, expected SHA256 URL, allowed .so files, and output directory
    @get:Input
    abstract val downloadUrl: Property<String>
    
    @get:Input
    abstract val expectedSha256Url: Property<String>

    @get:Input
    abstract val allowedSoFiles: ListProperty<String>

    @get:OutputDirectory
    abstract val outputDir: DirectoryProperty

    // The main action of the task: download the file, verify its checksum, and extract it if valid
    @TaskAction
    fun execute() {
        val url = downloadUrl.get()
        val shaUrl = expectedSha256Url.get()
        val validFiles = allowedSoFiles.get()
        val destDir = outputDir.get().asFile
        
        // Ensure output directory exists
        destDir.mkdirs()
        
        val tempFile = File(temporaryDir, "downloaded.zip")

        logger.lifecycle("Fetching expected SHA256 from $shaUrl...")

        // Fetch the expected SHA256 checksum from the provided URL, with error handling for network issues and invalid responses
        val expectedHash = try {
            val shaConnection = URL(shaUrl).openConnection() as HttpURLConnection
            shaConnection.connectTimeout = 30_000
            shaConnection.readTimeout = 30_000
            
            val responseCode = shaConnection.responseCode
            if (responseCode !in 200..299) {
                error("Failed to fetch SHA256 checksum from $shaUrl - HTTP $responseCode. Ensure checksum files are published to the release.")
            }
            
            shaConnection.inputStream.bufferedReader().use { it.readText() }
                .trim()
                .split("\\s+".toRegex())
                .first()
        } catch (e: Exception) {
            error("Error fetching SHA256 checksum: ${e.message}")
        }

        logger.lifecycle("Downloading $url...")
        var connection: HttpURLConnection? = null
        val digest = MessageDigest.getInstance("SHA-256")

        try {
            connection = URL(url).openConnection() as HttpURLConnection
            connection.connectTimeout = 30_000   // 30 seconds connect timeout
            connection.readTimeout = 120_000     // 2 minutes read timeout for large files
            
            val responseCode = connection.responseCode
            if (responseCode !in 200..299) {
                error("Download failed for $url — HTTP $responseCode")
            }

            // Stream the download directly to a temp file while updating the digest
            connection.inputStream.use { input ->
                tempFile.outputStream().use { output ->
                    val buffer = ByteArray(8192) // 8 KB buffer for efficient reading
                    var bytesRead = input.read(buffer)
                    while (bytesRead != -1) {
                        output.write(buffer, 0, bytesRead)
                        digest.update(buffer, 0, bytesRead)
                        bytesRead = input.read(buffer)
                    }
                }
            }
        } finally {
            connection?.disconnect() // Clean up hanging sockets
        }

        // Verify Checksum
        val calculatedHash = digest.digest().joinToString("") { "%02x".format(it) } // Convert to hex string
        if (!calculatedHash.equals(expectedHash, ignoreCase = true)) {
            tempFile.delete()
            error("Security failure: Checksum mismatch for $url!\nExpected: $expectedHash\nGot:      $calculatedHash")
        }

        logger.lifecycle("Checksum verified! Extracting...")
        
        // Extract the archive, but only include the allowed .so files to prevent zip slip vulnerabilities. Use Gradle's built-in archive handling for safety.
        try {
            fsOps.copy {
                from(archiveOps.zipTree(tempFile))
                into(destDir)
            
                // Fix: Explicitly include only the valid files to avoid eachFile exclude() bugs
                validFiles.forEach { fileName ->
                    include("**/$fileName")
                }
                
                eachFile {
                    // Flatten the directory structure
                    relativePath = RelativePath(true, name)
                }
                includeEmptyDirs = false
            }
        } finally {
            tempFile.delete()
        }
        
        logger.lifecycle("Successfully extracted to $destDir")
    }
}

class NativeLibraryDownloadPlugin : Plugin<Project> {
    override fun apply(project: Project) {
        // Plugin registration logic if required
    }
}