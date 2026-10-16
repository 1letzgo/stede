package de.letzgo.stede.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import de.letzgo.stede.data.Brand
import de.letzgo.stede.data.Council
import de.letzgo.stede.data.Feature
import de.letzgo.stede.data.Features
import de.letzgo.stede.data.Store

/** Bereiche der Startseite — wie `HomeSection` auf iOS, gleiche Schlüssel. */
enum class HomeSection(val key: String, private val label: String, val icon: ImageVector) {
    Sea("sea", "Meer & Fähre", Icons.Default.Water),
    Transit("transit", "Unterwegs", Icons.Default.Train),
    Home("home", "Zuhause", Icons.Default.Home),
    City("city", "Stadt", Icons.Default.Map),
    Politics("politics", "Politik", Icons.Default.AccountBalance);

    /** „Stadt“ heißt je Marke anders („Insel“ in Loog). */
    val title get() = if (this == City) Brand.current.placesTitle else label
    /** Nur Kacheln, deren Baustein die Gemeinde hat. */
    val tiles get() = HomeTileId.available.filter { it.section == this }
}

/** Einzelne Kacheln, ein- und ausblendbar — wie `HomeTileID` auf iOS. */
enum class HomeTileId(val key: String, val section: HomeSection, val category: String? = null) {
    Tides("tides", HomeSection.Sea), Ferry("ferry", HomeSection.Sea),
    Train("train", HomeSection.Transit), Bus("bus", HomeSection.Transit), Waste("waste", HomeSection.Home),
    Discover("discover", HomeSection.City, Catalog.DISCOVER), Gastro("gastro", HomeSection.City, Catalog.GASTRO),
    Shopping("shopping", HomeSection.City, Catalog.SHOPPING), Bikes("bikes", HomeSection.City, Catalog.BIKES),
    Playgrounds("playgrounds", HomeSection.City, Catalog.PLAYGROUNDS),
    Health("health", HomeSection.City, Catalog.HEALTH),
    Volunteer("volunteer", HomeSection.City, Catalog.VOLUNTEER),
    Sessions("sessions", HomeSection.Politics), Papers("papers", HomeSection.Politics);

    val title get() = when (this) { Tides -> "Gezeiten"; Ferry -> "Fähre"; Train -> "Bahn"; Bus -> "Bus"; Waste -> "Abfuhr"; Sessions -> "Sitzungen"; Papers -> "Vorlagen"; else -> Catalog.tileTitle(category!!) }
    val icon get() = when (this) { Tides -> Icons.Default.Waves; Ferry -> Icons.Default.DirectionsBoat; Train -> Icons.Default.Train; Bus -> Icons.Default.DirectionsBus; Waste -> Icons.Default.Delete; Sessions -> Icons.Default.Groups; Papers -> Icons.Default.Description; else -> Catalog.icon(category!!) }
    val color: Color @Composable get() = when (this) { Tides -> C.teal; Ferry -> C.red; Train -> C.red; Bus -> C.teal; Waste -> C.green; Sessions -> C.teal; Papers -> C.amber; else -> Catalog.color(category!!) }

    /** Hat die Gemeinde den Baustein? Sonst gibt es die Kachel nicht — auch nicht in den Einstellungen. */
    val isAvailable get() = when (this) {
        Tides -> Features.has(Feature.Tides); Ferry -> Features.has(Feature.Ferry)
        Train -> Features.has(Feature.Train); Bus -> Features.has(Feature.Bus); Waste -> Features.has(Feature.Waste)
        Discover -> Features.hasPlaces("sights", "leisure", "trips"); Gastro -> Features.hasPlaces("gastro")
        Shopping -> Features.hasPlaces("gastro", "bikes"); Bikes -> Features.hasPlaces("bikes") && !Brand.current.bikesInShopping
        Playgrounds -> Features.hasPlaces("playgrounds"); Health -> Features.hasPlaces("health"); Volunteer -> Features.hasPlaces("volunteer")
        Sessions, Papers -> Council.isAvailable
    }

    companion object { val available get() = entries.filter { it.isAvailable } }
}

/** Prefs `home.order` / `home.hidden`, kommagetrennt wie die iOS-UserDefaults. */
object HomeLayout {
    private const val ORDER = "home.order"
    private const val HIDDEN = "home.hidden"
    private const val TILES = "home.tiles"

    fun order(): List<HomeSection> {
        val saved = Store.string(ORDER, "").split(",").mapNotNull { k -> HomeSection.entries.firstOrNull { it.key == k } }
        // Bereiche ohne Baustein (Bahn, Bus, Abfuhr fehlen der Gemeinde) gibt es nicht.
        return (saved + HomeSection.entries.filter { it !in saved }).filter { it.tiles.isNotEmpty() }
    }
    fun setOrder(order: List<HomeSection>) = Store.setString(ORDER, order.joinToString(",") { it.key })

    /** Optionale Kacheln (vorerst Ehrenamt) sind anfangs ausgeblendet. */
    private val DEFAULT_HIDDEN = HomeTileId.Volunteer.key
    fun hidden(): Set<HomeTileId> = Store.string(HIDDEN, DEFAULT_HIDDEN).split(",").mapNotNull { k -> HomeTileId.entries.firstOrNull { it.key == k } }.toSet()
    fun setHidden(hidden: Set<HomeTileId>) = Store.setString(HIDDEN, HomeTileId.entries.filter { it in hidden }.joinToString(",") { it.key })

    /** Reihenfolge aller Kacheln; fehlende kommen hinten dazu. */
    fun tileOrder(): List<HomeTileId> {
        val saved = Store.string(TILES, "").split(",").mapNotNull { k -> HomeTileId.entries.firstOrNull { it.key == k } }
        return saved + HomeTileId.entries.filter { it !in saved }
    }
    fun tiles(section: HomeSection) = tileOrder().filter { it.section == section && it.isAvailable }

    /** Kachel innerhalb ihres Bereichs um `delta` Plätze verschieben. */
    fun moveTile(tile: HomeTileId, delta: Int) {
        val inSection = tiles(tile.section).toMutableList()
        val i = inSection.indexOf(tile); val j = i + delta
        if (j !in inSection.indices) return
        inSection[i] = inSection[j]; inSection[j] = tile
        val all = tileOrder().filter { it.section != tile.section } + inSection
        Store.setString(TILES, all.joinToString(",") { it.key })
    }

    fun reset() { Store.setString(ORDER, ""); Store.setString(HIDDEN, DEFAULT_HIDDEN); Store.setString(TILES, "") }
}
