plugins {
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.android) apply false
    alias(libs.plugins.android.library) apply false
    alias(libs.plugins.intellij) apply false
    alias(libs.plugins.detekt)
}

tasks.register("clean", Delete::class) {
    delete(rootProject.buildDir)
}
