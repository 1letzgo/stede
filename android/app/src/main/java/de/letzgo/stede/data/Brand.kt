package de.letzgo.stede.data

import de.letzgo.stede.BuildConfig
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
    /** „loog+“ — Name des Bausteins `plus`. */
    val plusName get() = "$displayName+"

    companion object {
        val allDirectories = setOf("gastro", "health", "leisure", "sights", "playgrounds", "trips", "bikes", "volunteer")
        val islandDirectories = setOf("gastro", "health", "leisure", "sights", "playgrounds", "trips", "bikes")

        // brands: start
        val stede = Brand("stede", "stede", "ammerland", "Ammerland", "stede", true,
            FeatureSet(Feature.entries.toSet(), allDirectories),
            FeatureSet(setOf(Feature.Weather, Feature.Calendar, Feature.Train, Feature.Bus, Feature.Waste, Feature.Groups), allDirectories),
            "Stadt", true, null)

        val loog = Brand("loog", "loog", "langeoog", "Langeoog", "loog", false,
            FeatureSet(setOf(Feature.Weather, Feature.Calendar, Feature.Ferry, Feature.Tides, Feature.Air, Feature.Plus), islandDirectories),
            FeatureSet(setOf(Feature.Weather, Feature.Calendar, Feature.Ferry, Feature.Tides, Feature.Air, Feature.Plus), islandDirectories),
            "Insel", true, "https://loog.shelf.am/datenschutz.html")

        /** Spiekeroog (Skill new-region-app). */
        val spoog = Brand("spoog", "spoog", "spiekeroog", "Spiekeroog", "spiekeroog", false,
            FeatureSet(setOf(Feature.Weather, Feature.Calendar, Feature.Ferry, Feature.Tides, Feature.Air, Feature.Plus), setOf("gastro", "health", "leisure", "playgrounds", "sights")),
            FeatureSet(setOf(Feature.Weather, Feature.Calendar, Feature.Ferry, Feature.Tides, Feature.Air, Feature.Plus), setOf("gastro", "health", "leisure", "playgrounds", "sights")),
            "Insel", false, "https://loog.shelf.am/datenschutz.html")

        /** Wangerooge (Skill new-region-app). */
        val wooge = Brand("wooge", "wooge", "wangerooge", "Wangerooge", "wangerooge", false,
            FeatureSet(setOf(Feature.Weather, Feature.Calendar, Feature.Ferry, Feature.Tides, Feature.Air, Feature.Plus), setOf("gastro", "health", "leisure", "playgrounds", "sights")),
            FeatureSet(setOf(Feature.Weather, Feature.Calendar, Feature.Ferry, Feature.Tides, Feature.Air, Feature.Plus), setOf("gastro", "health", "leisure", "playgrounds", "sights")),
            "Insel", false, "https://loog.shelf.am/datenschutz.html")

        val all = listOf(stede, loog, spoog, wooge)
        // brands: end

        val current: Brand = all.firstOrNull { it.id == BuildConfig.BRAND } ?: stede
    }
}

/** Die Bausteine der laufenden App: Gemeinde ∩ Marke. */
object Features {
    val current: FeatureSet get() = (Tenants.config.features ?: Brand.current.defaultFeatures).intersect(Brand.current.allowedFeatures)
    fun has(feature: Feature) = feature in current.enabled
    fun hasPlaces(vararg directories: String) = directories.any { it in current.places }
}
