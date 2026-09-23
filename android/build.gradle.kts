plugins {
    id("com.android.application") version "8.10.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.1.0" apply false
    id("org.jetbrains.kotlin.plugin.serialization") version "2.1.0" apply false
}

// Build-Ausgaben außerhalb von iCloud Drive: der Sync greift sonst in die
// Dex-Dateien ein und `mergeProjectDexDebug` scheitert sporadisch.
allprojects {
    layout.buildDirectory.set(file("${System.getProperty("user.home")}/Library/Caches/stede-android/${project.name}"))
}
