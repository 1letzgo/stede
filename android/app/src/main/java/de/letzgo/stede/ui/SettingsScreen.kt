package de.letzgo.stede.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.letzgo.stede.data.*

/** Tab „Einstellungen“ wie SettingsView: Konto, Straße und Haltestelle, Aufbau der Startseite. */
@Composable
fun SettingsScreen() {
    var streetId by remember { mutableIntStateOf(Store.int("waste.street")) }
    var sectionId by remember { mutableIntStateOf(Store.int("waste.section")) }
    var branchId by remember { mutableIntStateOf(Store.int("waste.branchSection")) }
    var noOrganic by remember { mutableStateOf(Store.bool("waste.noOrganic", false)) }
    var fourWeekly by remember { mutableStateOf(Store.bool("waste.fourWeekly", false)) }
    var stopId by remember { mutableStateOf(Store.string("bus.stop", "")) }
    var direction by remember { mutableStateOf(TrainDirection.stored()) }
    var stationId by remember { mutableStateOf(Store.string("train.station", "")) }
    var showStations by remember { mutableStateOf(false) }
    var showTenants by remember { mutableStateOf(false) }
    val tenant = Tenants.config
    // Ohne Wahl gilt der Standardbahnhof der Gemeinde.
    val station = tenant.station(stationId)
    var order by remember { mutableStateOf(HomeLayout.order()) }
    var hidden by remember { mutableStateOf(HomeLayout.hidden()) }
    var tileOrder by remember { mutableStateOf(HomeLayout.tileOrder()) }
    var showAccount by remember { mutableStateOf(false) }
    var showStreets by remember { mutableStateOf(false) }
    var showStops by remember { mutableStateOf(false) }
    val street = Waste.street(streetId)
    val context = LocalContext.current
    val version = remember {
        runCatching { context.packageManager.getPackageInfo(context.packageName, 0) }.getOrNull()
            ?.let { "${it.versionName} (${it.longVersionCode})" } ?: "–"
    }

    Scaffold(topBar = { StedeTopBar("Einstellungen") }, containerColor = C.sand) { pad ->
        LazyColumn(Modifier.padding(pad), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
            if (Features.has(Feature.Groups)) item { SectionHeader("Konto", Icons.Default.Person) }
            if (Features.has(Feature.Groups)) item {
                RowCard(Modifier.fillMaxWidth().clickable { showAccount = true }) {
                    val profile = Session.profile
                    if (Session.signedIn) PersonAvatar(profile?.avatar, profile?.displayName ?: "?", size = 44.dp)
                    else IconChip(Icons.Default.AccountCircle, C.ink, 44.dp)
                    Column(Modifier.weight(1f)) {
                        Text(if (Session.signedIn) profile?.displayName ?: "Konto" else "Anmelden", fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = C.text)
                        Text(if (Session.signedIn) "Profil, Kalender-Abo, Abmelden" else "Für Gruppen und ihre Termine", color = C.secondary, fontSize = 14.sp)
                    }
                    Chevron()
                }
            }

            if (Brand.current.choosesTenant) item { SectionHeader("Gemeinde", Icons.Default.Place) }
            if (Brand.current.choosesTenant) item {
                StedeCard { ValueRow(Icons.Default.Place, C.ink, "Gemeinde", tenant.municipality) { showTenants = true } }
            }

            item { SectionHeader("Startseite", Icons.Default.GridView) }
            item {
                StedeCard {
                    Text("Reihenfolge", fontSize = 13.sp, color = C.secondary)
                    order.forEachIndexed { index, section ->
                        Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            SmallIcon(section.icon, C.ink)
                            Text(section.title, Modifier.weight(1f), color = C.text, fontSize = 16.sp)
                            IconButton(onClick = { order = order.swapped(index, index - 1); HomeLayout.setOrder(order) }, enabled = index > 0) { Icon(Icons.Default.KeyboardArrowUp, "Nach oben") }
                            IconButton(onClick = { order = order.swapped(index, index + 1); HomeLayout.setOrder(order) }, enabled = index < order.lastIndex) { Icon(Icons.Default.KeyboardArrowDown, "Nach unten") }
                        }
                    }
                }
            }
            order.forEach { section ->
                item(key = "tiles-${section.key}") {
                    StedeCard {
                        Text(section.title, fontSize = 13.sp, color = C.secondary)
                        val tiles = tileOrder.filter { it.section == section && it.isAvailable }
                        tiles.forEachIndexed { index, tile ->
                            Row(Modifier.fillMaxWidth().padding(vertical = 2.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                SmallIcon(tile.icon, tile.color)
                                Text(tile.title, Modifier.weight(1f).padding(start = 8.dp), color = C.text, fontSize = 16.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                if (tiles.size > 1) {
                                    IconButton(onClick = { HomeLayout.moveTile(tile, -1); tileOrder = HomeLayout.tileOrder() }, enabled = index > 0) { Icon(Icons.Default.KeyboardArrowUp, "Nach oben") }
                                    IconButton(onClick = { HomeLayout.moveTile(tile, 1); tileOrder = HomeLayout.tileOrder() }, enabled = index < tiles.lastIndex) { Icon(Icons.Default.KeyboardArrowDown, "Nach unten") }
                                }
                                Switch(tile !in hidden, { visible ->
                                    hidden = if (visible) hidden - tile else hidden + tile
                                    HomeLayout.setHidden(hidden)
                                }, colors = SwitchDefaults.colors(checkedTrackColor = C.ink))
                            }
                        }
                        if (section == HomeSection.City) Text("Die ersten beiden sichtbaren Kacheln erscheinen groß.", fontSize = 12.sp, color = C.secondary, modifier = Modifier.padding(top = 4.dp))
                    }
                }
            }
            item {
                TextButton(onClick = { HomeLayout.reset(); order = HomeLayout.order(); hidden = HomeLayout.hidden(); tileOrder = HomeLayout.tileOrder() },
                    enabled = Store.string("home.order", "").isNotEmpty() || hidden != setOf(HomeTileId.Volunteer) || Store.string("home.tiles", "").isNotEmpty()) { Text("Standard wiederherstellen") }
            }

            if (Features.has(Feature.Waste)) item { SectionHeader("Zuhause", Icons.Default.Home) }
            if (Features.has(Feature.Waste)) item {
                StedeCard {
                    ValueRow(Icons.Default.Delete, C.green, "Abfuhr", street?.name ?: "Nicht gewählt") { showStreets = true }
                    street?.takeIf { it.needsSection }?.let { s ->
                        Spacer(Modifier.height(10.dp))
                        SectionPicker("Abschnitt", s.sections!!, sectionId) { sectionId = it; Store.setInt("waste.section", it) }
                    }
                    street?.takeIf { it.needsBranch }?.let { s ->
                        Spacer(Modifier.height(10.dp))
                        SectionPicker("Ast- und Strauchwerk", s.branchSections!!, branchId) { branchId = it; Store.setInt("waste.branchSection", it) }
                    }
                    // Wie auf der appfuhr-Website: Eigenkompostierer ohne Biotonne, Restabfall alle 4 Wochen.
                    if (street != null) {
                        Spacer(Modifier.height(10.dp))
                        WasteOptionRow(Icons.Default.Eco, C.green, "Keine Biotonne", noOrganic) { noOrganic = it; Store.setBool("waste.noOrganic", it) }
                        WasteOptionRow(Icons.Default.Delete, C.ink, "Restabfall alle 4 Wochen", fourWeekly) { fourWeekly = it; Store.setBool("waste.fourWeekly", it) }
                    }
                }
            }

            val bus = Features.has(Feature.Bus); val train = Features.has(Feature.Train) && tenant.stations.isNotEmpty()
            if (bus || train) item { SectionHeader("Unterwegs", Icons.Default.Train) }
            if (bus || train) item {
                StedeCard {
                    if (bus) ValueRow(Icons.Default.DirectionsBus, C.teal, "Bushaltestelle", busStop(stopId).short) { showStops = true }
                    if (bus && train) HorizontalDivider(Modifier.padding(vertical = 10.dp), color = C.text.copy(alpha = 0.12f))
                    if (train) Box {
                        ValueRow(Icons.Default.Train, C.red, "Bahnhof", station?.name ?: "–") { showStations = true }
                        DropdownMenu(showStations, { showStations = false }) {
                            tenant.stations.forEach { s ->
                                DropdownMenuItem({ Text(s.name) }, {
                                    stationId = s.id; Store.setString("train.station", s.id); showStations = false
                                }, trailingIcon = if (s.id == station?.id) { { Icon(Icons.Default.Check, null, tint = C.ink) } } else null)
                            }
                        }
                    }
                    if (train) {
                        HorizontalDivider(Modifier.padding(vertical = 10.dp), color = C.text.copy(alpha = 0.12f))
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            SmallIcon(Icons.Default.SwapHoriz, C.red)
                            Text("Bahn-Richtung", Modifier.weight(1f), color = C.text, fontSize = 16.sp)
                        }
                        Spacer(Modifier.height(8.dp))
                        Switcher(TrainDirection.entries, direction, { it.short(station) }) { direction = it; Store.setString("train.direction", it.name.lowercase()) }
                    }
                }
            }

            item { StedeCard { Row { Text("Version", Modifier.weight(1f), color = C.text); Text(version, color = C.secondary) } } }
            item { Spacer(Modifier.height(24.dp)) }
        }
    }
    if (showAccount) AccountSheet { showAccount = false }
    if (showTenants) TenantPickerSheet { showTenants = false }
    if (showStreets) StreetSheet(streetId, { id -> if (id != streetId) { streetId = id; sectionId = 0; branchId = 0 } }) { showStreets = false }
    if (showStops) BusStopSheet(stopId, { stopId = it; Store.setString("bus.stop", it) }) { showStops = false }
}

private fun <T> List<T>.swapped(i: Int, j: Int): List<T> = toMutableList().also { val t = it[i]; it[i] = it[j]; it[j] = t }

@Composable
private fun SmallIcon(icon: ImageVector, color: Color) {
    Box(Modifier.size(30.dp).background(color.copy(alpha = 0.16f), RoundedCornerShape(8.dp)), contentAlignment = Alignment.Center) {
        Icon(icon, null, tint = color, modifier = Modifier.size(17.dp))
    }
}

@Composable
private fun Chevron() = Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = C.tertiary)

@Composable
private fun ValueRow(icon: ImageVector, color: Color, title: String, value: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        SmallIcon(icon, color)
        Text(title, color = C.text, fontSize = 16.sp)
        Text(value, Modifier.weight(1f), color = C.secondary, fontSize = 15.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = androidx.compose.ui.text.style.TextAlign.End)
        Chevron()
    }
}

/** Schalter für eine Abfuhr-Option mit Symbol und Titel — wie toggleRow in SettingsView. */
@Composable
private fun WasteOptionRow(icon: androidx.compose.ui.graphics.vector.ImageVector, color: androidx.compose.ui.graphics.Color, title: String, on: Boolean, onToggle: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        IconChip(icon, color, size = 32.dp)
        Text(title, color = C.text, modifier = Modifier.weight(1f))
        Switch(on, onToggle)
    }
}
