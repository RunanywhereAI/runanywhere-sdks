plugins {
    `kotlin-dsl`
}

repositories {
    mavenCentral()
    google()
    gradlePluginPortal()
}

gradlePlugin {
    plugins {
        create("nativeDownloader") {
            id = "com.runanywhere.native-downloader"
            implementationClass = "com.runanywhere.buildlogic.NativeLibraryDownloadPlugin"
        }
    }
}

dependencies {
    
}