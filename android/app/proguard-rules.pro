# kotlinx.serialization: generierte Serializer der @Serializable-Klassen behalten.
-keepattributes *Annotation*, InnerClasses, Signature, EnclosingMethod
-dontnote kotlinx.serialization.**
-keepclassmembers class kotlinx.serialization.json.** { *** Companion; }
-keepclasseswithmembers class kotlinx.serialization.json.** { kotlinx.serialization.KSerializer serializer(...); }
-keep,includedescriptorclasses class de.letzgo.stede.**$$serializer { *; }
-keepclassmembers class de.letzgo.stede.** { *** Companion; }
-keepclasseswithmembers class de.letzgo.stede.** { kotlinx.serialization.KSerializer serializer(...); }

# Ktor / OkHttp / supabase-kt
-dontwarn org.slf4j.**
-dontwarn io.ktor.**
-keep class io.ktor.** { *; }
-keep class io.github.jan.supabase.** { *; }
-dontwarn okhttp3.internal.platform.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**

# pdfbox-android lädt Ressourcen und Klassen per Reflection.
-keep class com.tom_roush.pdfbox.** { *; }
-keep class com.tom_roush.fontbox.** { *; }
-keep class com.tom_roush.harmony.** { *; }
-dontwarn com.gemalto.jp2.**
-dontwarn com.tom_roush.pdfbox.filter.JPXFilter

# jsoup (Ratsinfo-Parser): optionale re2j-Unterstützung fehlt absichtlich.
-dontwarn com.google.re2j.**
