package de.letzgo.stede.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.StarOutline
import androidx.compose.material.icons.outlined.Map
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.letzgo.stede.data.Place
import de.letzgo.stede.data.Store
import kotlinx.coroutines.launch

/** Eine Kategorie der Rubrik „Stadt“: Karte, Favoriten- und Art-Filter, Karten — wie IslandView. */
@Composable
fun CategoryScreen(category: String, onBack: () -> Unit) {
    val all = remember(category) { Catalog.places(category) }
    val kinds = remember(all) { all.map { it.category }.distinct() }
    var favoritesOnly by remember { mutableStateOf(Store.bool("island.favoritesOnly.$category", false)) }
    var selectedKinds by remember { mutableStateOf(Store.stringSet("island.selectedKinds.$category")) }
    var showsMap by remember { mutableStateOf(Store.bool("island.showsMap", true)) }
    var selectedId by remember { mutableStateOf<String?>(null) }
    val favorites = Favorites.ids
    val visible = all.filter { (!favoritesOnly || it.id in favorites) && (selectedKinds.isEmpty() || it.category in selectedKinds) }
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()
    val openUrl = rememberOpenUrl(); val openIntent = rememberOpenIntent()

    Scaffold(topBar = {
        StedeTopBar(category, onBack) {
            IconButton(onClick = { showsMap = !showsMap; Store.setBool("island.showsMap", showsMap) }) { Icon(if (showsMap) Icons.Default.Map else Icons.Outlined.Map, "Karte") }
        }
    }, containerColor = C.sand) { pad ->
        Column(Modifier.padding(pad)) {
            if (showsMap) {
                val pins = visible.mapNotNull { p -> if (p.latitude == null || p.longitude == null) null else MapPin(p.id, p.latitude, p.longitude, Catalog.icon(p.category), Catalog.color(p.category), p.name) }
                OfflineMap(pins, selectedId, Modifier.padding(start = 16.dp, end = 16.dp, top = 16.dp).fillMaxWidth().height(260.dp)) { id ->
                    selectedId = id
                    val index = visible.indexOfFirst { it.id == id }
                    if (index >= 0) scope.launch { listState.animateScrollToItem(index) }
                }
            }
            Row(Modifier.padding(top = 16.dp, bottom = Spacing), verticalAlignment = Alignment.CenterVertically) {
                SelectionChip("${favorites.count { f -> all.any { it.id == f } }} Favoriten", favoritesOnly, Modifier.padding(start = 16.dp, end = 8.dp), icon = Icons.Default.Star) {
                    favoritesOnly = !favoritesOnly; Store.setBool("island.favoritesOnly.$category", favoritesOnly)
                }
                if (kinds.size > 1) Row(Modifier.horizontalScroll(rememberScrollState()).padding(end = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    kinds.forEach { kind ->
                        ColorChip(kind, Catalog.color(kind), icon = Catalog.icon(kind), selected = selectedKinds == setOf(kind)) {
                            selectedKinds = if (selectedKinds == setOf(kind)) emptySet() else setOf(kind)
                            Store.setStringSet("island.selectedKinds.$category", selectedKinds)
                        }
                    }
                }
            }
            LazyColumn(state = listState, contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
                if (visible.isEmpty()) item { InfoCard(if (favoritesOnly) "Noch keine Favoriten — tippe auf den Stern einer Karte." else "Keine Einträge.") }
                itemsIndexed(visible, key = { _, p -> p.id }) { _, p ->
                    PlaceCard(p, p.id == selectedId, p.id in favorites, { Favorites.toggle(p.id) }, openUrl, openIntent) {
                        selectedId = p.id; if (!showsMap) { showsMap = true; Store.setBool("island.showsMap", true) }
                    }
                }
                Catalog.note(category)?.let { item { Text(it, fontSize = 12.sp, color = C.secondary, modifier = Modifier.padding(horizontal = 4.dp)) } }
                if (visible.any { it.hours != null }) item { Text("Öffnungszeiten ohne Gewähr, saisonal abweichend – im Zweifel vorher anrufen.", fontSize = 12.sp, color = C.secondary, modifier = Modifier.padding(horizontal = 4.dp)) }
                item { SourceFooter(Catalog.source(category)) }
            }
        }
    }
}


@Composable
private fun PlaceCard(p: Place, selected: Boolean, favorite: Boolean, toggleFavorite: () -> Unit, openUrl: (String) -> Unit, openIntent: (String) -> Unit, showOnMap: () -> Unit) {
    val color = Catalog.color(p.category)
    StedeCard(highlighted = selected, onClick = showOnMap) {
        Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            IconChip(Catalog.icon(p.category), color)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(p.name, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = C.text)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { Pill(p.category, color); p.features.forEach { Pill(it, color) } }
            }
            IconButton(onClick = toggleFavorite) { Icon(if (favorite) Icons.Default.Star else Icons.Outlined.StarOutline, if (favorite) "Favorit entfernen" else "Als Favorit merken", tint = if (favorite) C.amber else C.tertiary) }
        }
        p.teaser?.let { Text(it, fontSize = 15.sp, color = C.secondary, modifier = Modifier.padding(top = 8.dp)) }
        Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            p.street?.let { InfoLine(Icons.Default.Place, it) }
            p.hours?.let { InfoLine(Icons.Default.Schedule, it) }
            p.restDay?.let { InfoLine(Icons.Default.Bedtime, "Ruhetag: $it") }
            p.seasonNote?.let { InfoLine(Icons.Default.CalendarMonth, it) }
        }
        val phone = p.phone; val web = p.website?.takeIf { it.startsWith("http") }
        if (phone != null || web != null || p.latitude != null) Row(Modifier.padding(top = 10.dp).horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            phone?.let { ActionChip(it, Icons.Default.Phone) { openIntent("tel:" + it.filter { c -> c.isDigit() || c == '+' }) } }
            web?.let { ActionChip("Website", Icons.Default.Language) { openUrl(it) } }
            if (p.latitude != null) ActionChip("Karte", Icons.Default.Map, showOnMap)
        }
    }
}

@Composable
fun InfoLine(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String) {
    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(icon, null, tint = C.secondary, modifier = Modifier.size(16.dp).padding(top = 1.dp))
        Text(text, fontSize = 13.sp, color = C.secondary)
    }
}
