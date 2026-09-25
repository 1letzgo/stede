package de.letzgo.stede.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import de.letzgo.stede.data.Place
import de.letzgo.stede.data.Places
import de.letzgo.stede.data.Store

/** Kategorien der Rubrik „Stadt“ — wie IslandCatalog in iOS. */
object Catalog {
    const val DISCOVER = "Entdecken"; const val GASTRO = "Gastro"; const val SHOPPING = "Einkaufen"
    const val PLAYGROUNDS = "Spielplätze"; const val TRIPS = "Ausflüge"; const val HEALTH = "Gesundheit"
    /** Vergünstigungen der Ehrenamtskarte in Westerstede — optionale Kachel auf Start. */
    const val VOLUNTEER = "Ehrenamtskarte"
    private val nonGastro = setOf("Einkaufen", "Bäckerei", "Drogerie")

    fun places(category: String): List<Place> = when (category) {
        // Sehenswürdigkeiten, Freizeit & Sport und Ausflüge in einer Ansicht.
        // Orte, die auch als Ausflug geführt sind (Rhododendronpark Hobbie), nur einmal — mit dem Ausflugstext.
        DISCOVER -> Places.directory("trips").places.let { trips ->
            val names = trips.map { it.name.lowercase() }.toSet()
            (Places.directory("sights").places + Places.directory("leisure").places).filter { it.name.lowercase() !in names } + trips
        }
        GASTRO -> Places.directory("gastro").places.filter { it.category !in nonGastro }
        SHOPPING -> Places.directory("gastro").places.filter { it.category == "Einkaufen" } + Places.directory("gastro").places.filter { it.category == "Drogerie" } +
            Places.directory("gastro").places.filter { it.category == "Bäckerei" } + Places.directory("bikes").places
        PLAYGROUNDS -> Places.directory("playgrounds").places
        TRIPS -> Places.directory("trips").places
        HEALTH -> Places.directory("health").places
        VOLUNTEER -> Places.directory("volunteer").places
        else -> emptyList()
    }

    fun source(category: String): String = when (category) {
        DISCOVER -> Places.directory("sights").source + " · Freizeit: " + Places.directory("leisure").source + " · Ausflüge: " + Places.directory("trips").source
        SHOPPING -> Places.directory("gastro").source + " · Fahrrad: " + Places.directory("bikes").source
        PLAYGROUNDS -> Places.directory("playgrounds").source
        TRIPS -> Places.directory("trips").source
        HEALTH -> Places.directory("health").source
        VOLUNTEER -> Places.directory("volunteer").source
        else -> Places.directory("gastro").source
    }

    fun icon(kind: String): ImageVector = when (kind) {
        "Café" -> Icons.Default.LocalCafe; "Bäckerei" -> Icons.Default.BakeryDining; "Allgemeinmedizin" -> Icons.Default.MedicalServices
        "Zahnarzt" -> Icons.Default.MedicalInformation; "Apotheke" -> Icons.Default.LocalPharmacy; "Facharzt" -> Icons.Default.MonitorHeart
        "Klinik" -> Icons.Default.LocalHospital; "Tierarzt" -> Icons.Default.Pets; "Therapie & Pflege" -> Icons.Default.Spa
        "Eiscafé" -> Icons.Default.Icecream; "Imbiss" -> Icons.Default.Fastfood; "Bar" -> Icons.Default.LocalBar
        "Einkaufen" -> Icons.Default.ShoppingCart; "Drogerie" -> Icons.Default.Soap; "Fahrrad" -> Icons.Default.DirectionsBike
        "Sehenswürdigkeiten", DISCOVER -> Icons.Default.Explore; HEALTH -> Icons.Default.MedicalServices
        "Bad" -> Icons.Default.Pool; "Sport" -> Icons.Default.DirectionsRun; "Spiel & Familie" -> Icons.Default.FamilyRestroom
        "Kultur" -> Icons.Default.TheaterComedy; TRIPS, "Park" -> Icons.Default.Park; PLAYGROUNDS, "Spielplatz" -> Icons.Default.Toys
        "Skaterplatz" -> Icons.Default.Skateboarding; "Kostenpflichtig" -> Icons.Default.ConfirmationNumber; "Draisine" -> Icons.Default.PedalBike; "Schifffahrt" -> Icons.Default.DirectionsBoat
        "Radtour" -> Icons.Default.DirectionsBike; GASTRO -> Icons.Default.Restaurant
        VOLUNTEER -> Icons.Default.VolunteerActivism; "Verwaltung" -> Icons.Default.AccountBalance; "Bildung" -> Icons.Default.MenuBook
        "Mobilität" -> Icons.Default.DirectionsBus; "Handel" -> Icons.Default.ShoppingBag; "Übernachtung" -> Icons.Default.Cabin
        "Versicherung" -> Icons.Default.Shield
        else -> Icons.Default.Restaurant
    }

    @Composable @ReadOnlyComposable
    fun color(kind: String): Color = when (kind) {
        "Café", "Bäckerei", "Spiel & Familie", PLAYGROUNDS, "Spielplatz", "Draisine", "Therapie & Pflege" -> C.amber
        "Eiscafé", "Drogerie", "Apotheke", TRIPS, "Park" -> C.red
        VOLUNTEER -> C.green
        "Kostenpflichtig" -> C.teal
        "Verwaltung" -> C.ink; "Mobilität" -> C.teal; "Handel" -> C.amber; "Übernachtung" -> C.red; "Versicherung" -> C.mudflat
        "Imbiss", "Fahrrad", "Sport", "Tierarzt", "Radtour" -> C.green
        "Bar", "Einkaufen", "Zahnarzt" -> C.ink
        "Sehenswürdigkeiten", DISCOVER, "Klinik" -> C.mudflat
        HEALTH, "Allgemeinmedizin", "Bad", "Schifffahrt" -> C.teal
        else -> C.heather
    }

    fun note(category: String): String? = when (category) {
        TRIPS, DISCOVER -> "Stadtführungen, Konzerte und Feste stehen im Kalender – hier nur Ziele rund um Westerstede."
        HEALTH -> "Notruf 112 · Ärztlicher Bereitschaftsdienst 116117 · Notaufnahme in der Ammerland-Klinik, Lange Straße 38."
        VOLUNTEER -> "Gilt nur mit der Ehrenamtskarte Niedersachsen/Bremen – beim Anbieter vorzeigen. Beantragung und alle Angebote im Land: freiwilligenserver.de/ehrenamtskarte."
        PLAYGROUNDS -> "Bewertung und Sauberkeit laut Kinderrat Westerstede, Stand der Stadtseite."
        else -> null
    }
}

/** App-weite Favoriten (island.favorites in iOS). */
object Favorites {
    var ids by mutableStateOf(Store.stringSet("island.favorites"))
        private set
    fun toggle(id: String) { ids = if (id in ids) ids - id else ids + id; Store.setStringSet("island.favorites", ids) }
}
