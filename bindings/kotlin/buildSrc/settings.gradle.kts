// buildSrc is its own build, so it does not see the root catalog by default.
// Import it so buildSrc dependencies resolve through gradle/libs.versions.toml.
dependencyResolutionManagement {
    versionCatalogs {
        create("libs") {
            from(files("../gradle/libs.versions.toml"))
        }
    }
}
