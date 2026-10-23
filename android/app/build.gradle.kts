import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

android {
    namespace = "de.letzgo.stede"
    compileSdk = 36
    defaultConfig {
        minSdk = 26
        targetSdk = 36
    }
    // Eine App je Region aus demselben Code (wie die App-Hüllen auf iOS): die Marke steht in
    // BuildConfig.BRAND, Name, Paket und URL-Schema je Flavor; Bausteine kommen aus tenants.config.
    flavorDimensions += "brand"
    productFlavors {
        create("stede") {
            dimension = "brand"
            applicationId = "de.letzgo.stede"
            versionCode = 10
            versionName = "1.0"
            buildConfigField("String", "BRAND", "\"stede\"")
            resValue("string", "app_name", "stede")
            manifestPlaceholders["urlScheme"] = "stede"
        }
        create("loog") {
            dimension = "brand"
            applicationId = "de.letzgo.loog"
            versionCode = 1
            versionName = "1.3"
            buildConfigField("String", "BRAND", "\"loog\"")
            resValue("string", "app_name", "Loog")
            manifestPlaceholders["urlScheme"] = "loog"
        }
        create("spoog") {
            dimension = "brand"
            applicationId = "de.letzgo.spoog"
            versionCode = 1
            versionName = "1.0"
            buildConfigField("String", "BRAND", "\"spoog\"")
            resValue("string", "app_name", "Spoog")
            manifestPlaceholders["urlScheme"] = "spoog"
        }
        create("wooge") {
            dimension = "brand"
            applicationId = "de.letzgo.wooge"
            versionCode = 1
            versionName = "1.4"
            buildConfigField("String", "BRAND", "\"wooge\"")
            resValue("string", "app_name", "Wooge")
            manifestPlaceholders["urlScheme"] = "wooge"
        }
        // brands: end (neue Flavors fügt der Skill `new-region-app` davor ein)
    }
    // Upload-Schlüssel liegt außerhalb von Repo und iCloud; ohne die Datei
    // entsteht ein unsignierter Release-Build.
    val signingFile = file("${System.getProperty("user.home")}/Library/Application Support/stede-signing/keystore.properties")
    signingConfigs {
        if (signingFile.exists()) create("upload") {
            val props = Properties().apply { signingFile.inputStream().use { load(it) } }
            storeFile = file(props.getProperty("storeFile"))
            storePassword = props.getProperty("storePassword")
            keyAlias = props.getProperty("keyAlias")
            keyPassword = props.getProperty("keyPassword")
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfigs.findByName("upload")?.let { signingConfig = it }
            buildConfigField("Boolean", "SIDELOAD", "false")
        }
        // APK für GitHub und Tower: wie release, aber mit Update-Download in der App
        // (REQUEST_INSTALL_PACKAGES nur hier, nicht im Play-Bundle).
        create("sideload") {
            initWith(getByName("release"))
            matchingFallbacks += "release"
            buildConfigField("Boolean", "SIDELOAD", "true")
        }
        debug { buildConfigField("Boolean", "SIDELOAD", "true") }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true; buildConfig = true }
    // pdfbox zieht BouncyCastle mit; dessen Post-Quanten-Tabellen (~8 MB) braucht
    // das Lesen des Abfuhr-PDFs nicht.
    packaging { resources { excludes += "org/bouncycastle/pqc/**" } }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(composeBom)
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("io.ktor:ktor-client-okhttp:3.0.3")
    implementation("io.ktor:ktor-client-content-negotiation:3.0.3")
    implementation("io.ktor:ktor-serialization-kotlinx-json:3.0.3")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("io.coil-kt.coil3:coil-compose:3.0.4")
    implementation("io.coil-kt.coil3:coil-network-okhttp:3.0.4")
    implementation(platform("io.github.jan-tennert.supabase:bom:3.0.3"))
    implementation("io.github.jan-tennert.supabase:postgrest-kt")
    implementation("io.github.jan-tennert.supabase:auth-kt")
    implementation("io.github.jan-tennert.supabase:storage-kt")
    implementation("io.github.jan-tennert.supabase:functions-kt")
    implementation("com.tom-roush:pdfbox-android:2.0.27.0")
    implementation("org.jsoup:jsoup:1.18.3")
    implementation("androidx.browser:browser:1.8.0")
    // Baustein „plus“ (loog+): Einmalkauf und Monatsabo über Google Play.
    implementation("com.android.billingclient:billing-ktx:7.1.1")
}
