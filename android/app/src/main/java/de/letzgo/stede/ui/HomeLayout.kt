package de.letzgo.stede.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import de.letzgo.stede.data.Store

/** Bereiche der Startseite — wie `HomeSection` auf iOS, gleiche Schlüssel. */
enum class HomeSection(val key: String, val title: String, val icon: ImageVector) {
    Transit("transit", "Unterwegs", Icons.Default.Train),
    Home("home", "Zuhause", Icons.Default.Home),
    City("city", "Stadt", Icons.Default.Map);

    val tiles get() = HomeTileId.entries.filter { it.section == this }
}

/** Einzelne Kacheln, ein- und ausblendbar — wie `HomeTileID` auf iOS. */
enum class HomeTileId(val key: String, val section: HomeSection, val category: String? = null) {
    Train("train", HomeSection.Transit), Bus("bus", HomeSection.Transit), Waste("waste", HomeSection.Home),
    Discover("discover", HomeSection.City, Catalog.DISCOVER), Gastro("gastro", HomeSection.City, Catalog.GASTRO),
    Shopping("shopping", HomeSection.City, Catalog.SHOPPING), Playgrounds("playgrounds", HomeSection.City, Catalog.PLAYGROUNDS),
    Trips("trips", HomeSection.City, Catalog.TRIPS), Health("health", HomeSection.City, Catalog.HEALTH);

    val title get() = when (this) { Train -> "Bahn"; Bus -> "Bus"; Waste -> "Abfuhr"; else -> category!! }
    val icon get() = when (this) { Train -> Icons.Default.Train; Bus -> Icons.Default.DirectionsBus; Waste -> Icons.Default.Delete; else -> Catalog.icon(category!!) }
    val color: Color @Composable get() = when (this) { Train -> C.red; Bus -> C.teal; Waste -> C.green; else -> Catalog.color(category!!) }
}

/** Prefs `home.order` / `home.hidden`, kommagetrennt wie die iOS-UserDefaults. */
object HomeLayout {
    private const val ORDER = "home.order"
    private const val HIDDEN = "home.hidden"

    fun order(): List<HomeSection> {
        val saved = Store.string(ORDER, "").split(",").mapNotNull { k -> HomeSection.entries.firstOrNull { it.key == k } }
        return saved + HomeSection.entries.filter { it !in saved }
    }
    fun setOrder(order: List<HomeSection>) = Store.setString(ORDER, order.joinToString(",") { it.key })

    fun hidden(): Set<HomeTileId> = Store.string(HIDDEN, "").split(",").mapNotNull { k -> HomeTileId.entries.firstOrNull { it.key == k } }.toSet()
    fun setHidden(hidden: Set<HomeTileId>) = Store.setString(HIDDEN, HomeTileId.entries.filter { it in hidden }.joinToString(",") { it.key })

    fun reset() { Store.setString(ORDER, ""); Store.setString(HIDDEN, "") }
}
