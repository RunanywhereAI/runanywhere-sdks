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

        // Grab the first sequence of non-whitespace characters (the hash itself)
        val expectedHash = URL(shaUrl).readText().trim().split("\\s+".toRegex()).first()

        logger.lifecycle("Downloading $url...")
        var connection: HttpURLConnection? = null
        val digest = MessageDigest.getInstance("SHA-256")

        try {
            connection = URL(url).openConnection() as HttpURLConnection
            connection.connectTimeout = 30_000   // 30 seconds connect timeout
            connection.readTimeout = 120_000     // 2 minutes read timeout for large files
            
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
        check(calculatedHash.equals(expectedHash, ignoreCase = true)) {
            tempFile.delete() // Nuke the bad file
            "Security failure: Checksum mismatch for $url!\nExpected: $expectedHash\nGot:      $calculatedHash"
        }

        logger.lifecycle("Checksum verified! Extracting...")
        
        // Extract only the allowed .so files, flattening the directory structure
        fsOps.copy {
            from(archiveOps.zipTree(tempFile))
            into(destDir)
        
            include("**/*.so")
            eachFile {
                if (validFiles.contains(name)) {
                    // Flatten the directory structure
                    relativePath = RelativePath(true, name)
                } else {
                    exclude()
                }
            }
            includeEmptyDirs = false
        }
        
        tempFile.delete()
        logger.lifecycle("Successfully extracted to $destDir")
    }
}

class NativeLibraryDownloadPlugin : Plugin<Project> {
    override fun apply(project: Project) {
        
    }
}