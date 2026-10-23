package de.letzgo.stede.data

import de.letzgo.stede.BuildConfig
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/** Ein Baustein, den eine Gemeinde zeigen kann — Schlüssel wie in `tenants.config.features` und iOS `Feature`. */
enum class Feature(val key: String) {
    Weather("weather"), Calendar("calendar"), Train("train"), Bus("bus"), Waste("waste"),
    Ferry("ferry"), Tides("tides"), Air("air"), Groups("groups"), Plus("plus"),
    /** Politik: Sitzungen und Vorlagen aus dem Ratsinformationssystem (`tenants.config.ris`). */
    Politics("politics"),
}

/**
 * Was eine Gemeinde zeigt (`tenants.config.features`), etwa `{"ferry": true, "places": ["gastro"]}`.
 * Fehlt ein Schlüssel, ist der Baustein aus — wie FeatureSet in iOS.
 */
@Serializable(with = FeatureSetSerializer::class)
data class FeatureSet(val enabled: Set<Feature>, val places: Set<String>) {
    /** Nur, was beide erlauben — so kann eine Marke Bausteine sperren, die eine Gemeinde hätte. */
    fun intersect(other: FeatureSet) = FeatureSet(enabled intersect other.enabled, places intersect other.places)
}

object FeatureSetSerializer : KSerializer<FeatureSet> {
    override val descriptor: SerialDescriptor = JsonObject.serializer().descriptor
    override fun deserialize(decoder: Decoder): FeatureSet {
        val obj = (decoder as JsonDecoder).decodeJsonElement() as? JsonObject ?: return FeatureSet(emptySet(), emptySet())
        val enabled = Feature.entries.filter { (obj[it.key] as? JsonPrimitive)?.booleanOrNull == true }.toSet()
        val places = runCatching { obj["places"]?.jsonArray?.mapNotNull { it.jsonPrimitive.contentOrNull }?.toSet() }.getOrNull() ?: emptySet()
        return FeatureSet(enabled, places)
    }
    override fun serialize(encoder: Encoder, value: FeatureSet) {
        (encoder as JsonEncoder).encodeJsonElement(buildJsonObject {
            value.enabled.forEach { put(it.key, true) }
            put("places", kotlinx.serialization.json.JsonArray(value.places.sorted().map { JsonPrimitive(it) }))
        })
    }
}

/**
 * Welche App gerade läuft — stede (Ammerland), Loog (Langeoog) … Der Flavor setzt `BuildConfig.BRAND`;
 * alles andere ist derselbe Code. Gegenstück zu AppBrand in iOS.
 */
data class Brand(
    val id: String,
    /** Name in Leiste und Texten („stede“, „loog“). */
    val displayName: String,
    /** `tenants.region` der Gemeinden dieser App. */
    val region: String,
    val regionName: String,
    /** Gemeinde vor der ersten Wahl — und die einzige, wenn es keine Wahl gibt. */
    val defaultTenant: String,
    /** Fragt die App beim ersten Start nach der Gemeinde? */
    val choosesTenant: Boolean,
    /** Bausteine, die diese App überhaupt enthält. */
    val allowedFeatures: FeatureSet,
    /** Bausteine einer Gemeinde ohne `features` im Backend. */
    val defaultFeatures: FeatureSet,
    /** Überschrift der Orte auf Start („Stadt“, „Insel“). */
    val placesTitle: String,
    /** Fahrradläden unter „Einkaufen“ statt in einer eigenen Kachel „Fahrräder“. */
    val bikesInShopping: Boolean,
    val privacyUrl: String?,
) {
    /** „Termine der Region“ — bisher nur stede (die übrigen Ammerland-Gemeinden werden per Cron weiter importiert). */
    val offersRegionEvents get() = id == "stede"

    /** „loog+“ — Name des Bausteins `plus`. */
    val plusName get() = "$displayName+"

    companion object {
        val allDirectories = setOf("gastro", "health", "leisure", "sights", "playgrounds", "trips", "bikes", "volunteer")
        val islandDirectories = setOf("gastro", "health", "leisure", "sights", "playgrounds", "trips", "bikes")

        // brands: start
        /** Westerstede (seit 10/2026 nur noch diese Gemeinde; die übrigen Ammerland-Gemeinden bekommen eigene Apps). */
        val stede = Brand("stede", "stede", "ammerland", "Ammerland", "stede", false,
            FeatureSet(Feature.entries.toSet(), allDirectories),
            FeatureSet(setOf(Feature.Weather, Feature.Calendar, Feature.Train, Feature.Bus, Feature.Waste, Feature.Groups), allDirectories),
            "Stadt", true, null)

        val loog = Brand("loog", "loog", "langeoog", "Langeoog", "loog", false,
            FeatureSet(setOf(Feature.Weather, Feature.Calendar, Feature.Ferry, Feature.Tides, Feature.Air, Feature.Plus, Feature.Groups), islandDirectories),
            FeatureSet(setOf(Feature.Weather, Feature.Calendar, Feature.Ferry, Feature.Tides, Feature.Air, Feature.Plus, Feature.Groups), islandDirectories),
            "Insel", true, "https://loog.shelf.am/datenschutz.html")

        /** Spiekeroog (Skill new-region-app). */
        val spoog = Brand("spoog", "spoog", "spiekeroog", "Spiekeroog", "spiekeroog", false,
            FeatureSet(setOf(Feature.Weather, Feature.Calendar, Feature.Ferry, Feature.Tides, Feature.Air, Feature.Plus, Feature.Groups), setOf("gastro", "health", "leisure", "playgrounds", "sights")),
            FeatureSet(setOf(Feature.Weather, Feature.Calendar, Feature.Ferry, Feature.Tides, Feature.Air, Feature.Plus, Feature.Groups), setOf("gastro", "health", "leisure", "playgrounds", "sights")),
            "Insel", false, "https://loog.shelf.am/datenschutz.html")

        /** Wangerooge (Skill new-region-app). */
        val wooge = Brand("wooge", "wooge", "wangerooge", "Wangerooge", "wangerooge", false,
            FeatureSet(setOf(Feature.Weather, Feature.Calendar, Feature.Ferry, Feature.Tides, Feature.Air, Feature.Plus, Feature.Groups), setOf("gastro", "health", "leisure", "playgrounds", "sights")),
            FeatureSet(setOf(Feature.Weather, Feature.Calendar, Feature.Ferry, Feature.Tides, Feature.Air, Feature.Plus, Feature.Groups), setOf("gastro", "health", "leisure", "playgrounds", "sights")),
            "Insel", false, "https://loog.shelf.am/datenschutz.html")

        val all = listOf(stede, loog, spoog, wooge)
        // brands: end

        val current: Brand = all.firstOrNull { it.id == BuildConfig.BRAND } ?: stede
    }
}

/**
 * Wer die App nutzt — wie `Audience` in iOS: Touristen sehen alles Öffentliche, aber keine Abfuhr,
 * keine Politik und keine Gruppen; Einwohner alles, was die Gemeinde hat. Gewählt im Onboarding,
 * änderbar unter Einstellungen (Pref `audience`, gleicher Schlüssel wie iOS).
 */
enum class Audience(val key: String, val title: String, val hidden: Set<Feature>) {
    Tourist("tourist", "Zu Besuch", setOf(Feature.Waste, Feature.Politics, Feature.Groups)),
    Resident("resident", "Ich wohne hier", emptySet());

    companion object {
        private const val PREF = "audience"
        /** null, solange noch nicht gewählt — dann erscheint der Wizard. Beobachtbar für Compose. */
        var current by androidx.compose.runtime.mutableStateOf(Store.string(PREF, "").let { k -> entries.firstOrNull { it.key == k } }); private set
        fun select(audience: Audience) { Store.setString(PREF, audience.key); current = audience }
    }
}

/** Die Bausteine der laufenden App: Gemeinde ∩ Marke, ohne was die gewählte Ansicht ausblendet. */
object Features {
    val current: FeatureSet get() {
        val set = (Tenants.config.features ?: Brand.current.defaultFeatures).intersect(Brand.current.allowedFeatures)
        // Ohne Wahl gilt Einwohner — der Wizard fragt ohnehin, bevor jemand etwas sieht.
        return FeatureSet(set.enabled - (Audience.current ?: Audience.Resident).hidden, set.places)
    }
    fun has(feature: Feature) = feature in current.enabled
    fun hasPlaces(vararg directories: String) = directories.any { it in current.places }
}

/** Einstellung „Termine der Region“ (Pref `events.region`, gleicher Schlüssel wie iOS). */
object RegionEvents {
    const val KEY = "events.region"
    var on by androidx.compose.runtime.mutableStateOf(Store.bool(KEY, false)); private set
    val isOn get() = Brand.current.offersRegionEvents && on
    fun set(value: Boolean) { Store.setBool(KEY, value); on = value }
}
