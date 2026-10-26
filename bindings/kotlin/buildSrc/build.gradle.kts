plugins {
    `kotlin-dsl`
}

repositories {
    mavenCentral()
}

dependencies {
    testImplementation("org.junit.jupiter:junit-jupiter:5.11.4")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher:1.11.4")
}

tasks.named<Test>("test") {
    useJUnitPlatform()
}
