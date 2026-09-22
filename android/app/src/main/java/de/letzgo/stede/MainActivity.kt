package de.letzgo.stede

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import kotlinx.coroutines.launch
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.TemporalAdjusters
import java.util.Locale

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent { StedeTheme { StedeApp() } }
    }
}

enum class Tab(val title: String, val icon: ImageVector) { Start("Start", Icons.Default.Home), Kalender("Kalender", Icons.Default.DateRange), Community("Community", Icons.Default.Groups) }

val berlin: ZoneId = ZoneId.of("Europe/Berlin")
val de: Locale = Locale.GERMAN

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StedeApp() {
    var tab by remember { mutableStateOf(Tab.Start) }
    var tenant by remember { mutableStateOf<Tenant?>(null) }
    var directory by remember { mutableStateOf<Pair<String, String>?>(null) }  // key, title
    LaunchedEffect(Unit) { tenant = runCatching { Backend.tenant() }.getOrNull() }
    val title = directory?.second ?: when (tab) { Tab.Start -> "stede"; Tab.Kalender -> "Kalender"; Tab.Community -> "Community" }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(title, fontWeight = FontWeight.SemiBold) },
                navigationIcon = { if (directory != null) IconButton(onClick = { directory = null }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Zurück", tint = Color.White) } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Stede.deep, titleContentColor = Color.White),
            )
        },
        bottomBar = {
            NavigationBar {
                Tab.entries.forEach { t ->
                    NavigationBarItem(selected = tab == t && directory == null, onClick = { tab = t; directory = null },
                        icon = { Icon(t.icon, t.title) }, label = { Text(t.title) })
                }
            }
        },
        containerColor = MaterialTheme.colorScheme.background,
    ) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            val dir = directory
            when {
                dir != null -> PlacesScreen(tenant, dir.first)
                tab == Tab.Start -> StartScreen(tenant) { key, name -> directory = key to name }
                tab == Tab.Kalender -> CalendarScreen(tenant)
                else -> CommunityScreen(tenant)
            }
        }
    }
}

// MARK: Bausteine im Stil der iOS-Karten

@Composable
fun StedeCard(modifier: Modifier = Modifier, onClick: (() -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    val base = modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(MaterialTheme.colorScheme.surface)
    Column((if (onClick != null) base.clickable { onClick() } else base).padding(14.dp), content = content)
}

@Composable
fun Pill(text: String, color: Color) {
    Text(text, color = color, fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
        modifier = Modifier.background(color.copy(alpha = 0.16f), RoundedCornerShape(50)).padding(horizontal = 8.dp, vertical = 3.dp))
}

@Composable
fun IconChip(icon: ImageVector, color: Color) {
    Box(Modifier.size(38.dp).background(color.copy(alpha = 0.16f), RoundedCornerShape(12.dp)), contentAlignment = Alignment.Center) {
        Icon(icon, null, tint = color)
    }
}

@Composable
fun SectionHeader(text: String) {
    Text(text, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, modifier = Modifier.padding(top = 4.dp))
}

// MARK: Start

data class Directory(val key: String, val title: String, val icon: ImageVector, val color: Color)
val directories = listOf(
    Directory("sights", "Entdecken", Icons.Default.Explore, Stede.mudflat),
    Directory("gastro", "Gastro", Icons.Default.Restaurant, Stede.heather),
    Directory("playgrounds", "Spielplätze", Icons.Default.ChildCare, Stede.amber),
    Directory("trips", "Ausflüge", Icons.Default.Park, Stede.red),
    Directory("health", "Gesundheit", Icons.Default.MedicalServices, Stede.teal),
    Directory("leisure", "Freizeit & Sport", Icons.Default.SportsSoccer, Stede.green),
)

@Composable
fun StartScreen(tenant: Tenant?, open: (String, String) -> Unit) {
    val hour = OffsetDateTime.now(berlin).hour
    val greeting = when (hour) { in 5..10 -> "Guten Morgen"; in 11..17 -> "Schönen Tag"; in 18..22 -> "Schönen Abend"; else -> "Gute Nacht" }
    LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            StedeCard {
                Text("Moin!", fontSize = 28.sp, fontWeight = FontWeight.Bold, color = Stede.teal)
                Text("$greeting in ${tenant?.municipality ?: "Westerstede"}", color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            }
        }
        item { SectionHeader("Stadt") }
        items(directories.chunked(2)) { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                row.forEach { d ->
                    Column(Modifier.weight(1f).height(110.dp).clip(RoundedCornerShape(18.dp)).background(d.color.copy(alpha = 0.16f)).clickable { open(d.key, d.title) }.padding(12.dp)) {
                        Text(d.title, color = d.color, fontWeight = FontWeight.SemiBold)
                        Spacer(Modifier.weight(1f))
                        Icon(d.icon, null, tint = d.color.copy(alpha = 0.5f), modifier = Modifier.size(40.dp).align(Alignment.End))
                    }
                }
            }
        }
        item { Text("Bahn, Bus, Wetter, Abfuhr und Karte folgen in der Android-Version.", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)) }
    }
}

// MARK: Verzeichnisse

@Composable
fun PlacesScreen(tenant: Tenant?, directory: String) {
    var places by remember { mutableStateOf<List<Place>>(emptyList()) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(tenant, directory) {
        tenant ?: return@LaunchedEffect
        runCatching { Backend.places(tenant.id, directory) }.onSuccess { places = it }.onFailure { error = it.message }
    }
    LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (places.isEmpty()) item { Text(error ?: "Lade …", color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)) }
        items(places) { p ->
            val color = directories.firstOrNull { it.key == p.directory }?.color ?: Stede.ink
            StedeCard {
                Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    IconChip(directories.firstOrNull { it.key == p.directory }?.icon ?: Icons.Default.Place, color)
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(p.name, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
                        Pill(p.kind, color)
                    }
                }
                p.teaser?.let { Text(it, modifier = Modifier.padding(top = 8.dp), color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.65f), fontSize = 14.sp) }
                p.street?.let { Text("📍 $it", fontSize = 12.sp, modifier = Modifier.padding(top = 6.dp)) }
                p.hours?.let { Text("🕒 $it", fontSize = 12.sp) }
            }
        }
    }
}

// MARK: Kalender

enum class Filter(val title: String) { Alle("Alle"), Stadt("Öffentlich"), Communities("Communities") }

sealed class Entry(val time: OffsetDateTime?) {
    class City(val e: CityEvent, t: OffsetDateTime?) : Entry(t)
    class Public(val e: PublicEvent, t: OffsetDateTime) : Entry(t)
}

fun parseTime(iso: String?): OffsetDateTime? = iso?.let { runCatching { OffsetDateTime.parse(it).atZoneSameInstant(berlin).toOffsetDateTime() }.getOrNull() }

@Composable
fun CalendarScreen(tenant: Tenant?) {
    var weekStart by remember { mutableStateOf(LocalDate.now(berlin).with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))) }
    var filter by remember { mutableStateOf(Filter.Alle) }
    var city by remember { mutableStateOf<List<CityEvent>>(emptyList()) }
    var public by remember { mutableStateOf<List<PublicEvent>>(emptyList()) }
    LaunchedEffect(tenant, weekStart) {
        tenant ?: return@LaunchedEffect
        val end = weekStart.plusDays(7)
        city = runCatching { Backend.cityEvents(tenant.id, weekStart.toString(), end.toString()) }.getOrDefault(emptyList())
        public = runCatching { Backend.publicEvents(tenant.id, weekStart.atStartOfDay(berlin).toOffsetDateTime().toString(), end.atStartOfDay(berlin).toOffsetDateTime().toString()) }.getOrDefault(emptyList())
    }
    val entries: List<Entry> = buildList {
        if (filter != Filter.Communities) addAll(city.map { Entry.City(it, parseTime(it.startsAt) ?: it.day.let { d -> LocalDate.parse(d).atStartOfDay(berlin).toOffsetDateTime() }) })
        if (filter != Filter.Stadt) addAll(public.mapNotNull { e -> parseTime(e.startsAt)?.let { Entry.Public(e, it) } })
    }.sortedBy { it.time }
    val dayFormat = DateTimeFormatter.ofPattern("EEEE, d. MMM", de)
    val timeFormat = DateTimeFormatter.ofPattern("HH:mm", de)
    val today = LocalDate.now(berlin)

    Column {
        Row(Modifier.padding(horizontal = 16.dp, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Filter.entries.forEach { f ->
                val selected = filter == f
                Text(f.title, color = if (selected) Color.White else Stede.ink, fontWeight = FontWeight.SemiBold, fontSize = 14.sp,
                    modifier = Modifier.weight(1f).clip(RoundedCornerShape(50)).background(if (selected) Stede.deep else MaterialTheme.colorScheme.surface).clickable { filter = f }.padding(vertical = 8.dp),
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            }
        }
        Row(Modifier.padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = { weekStart = weekStart.minusWeeks(1) }) { Icon(Icons.Default.ChevronLeft, "Vorherige Woche") }
            Text(if (today >= weekStart && today < weekStart.plusDays(7)) "Diese Woche" else "${weekStart.dayOfMonth}.–${weekStart.plusDays(6).format(DateTimeFormatter.ofPattern("d. MMM", de))}",
                Modifier.weight(1f), fontWeight = FontWeight.SemiBold, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            IconButton(onClick = { weekStart = weekStart.plusWeeks(1) }) { Icon(Icons.Default.ChevronRight, "Nächste Woche") }
        }
        LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            (0..6).forEach { offset ->
                val date = weekStart.plusDays(offset.toLong())
                val dayEntries = entries.filter { it.time?.toLocalDate() == date }
                item { SectionHeader((if (date == today) "Heute, " else "") + date.format(dayFormat)) }
                if (dayEntries.isEmpty()) item { Text("Keine Termine", fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f)) }
                items(dayEntries) { entry ->
                    when (entry) {
                        is Entry.City -> StedeCard {
                            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
                                IconChip(Icons.Default.AccountBalance, Stede.mudflat)
                                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                    Text(entry.e.title, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
                                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                        Pill(entry.e.startsAt?.let { parseTime(it)?.format(timeFormat) + (parseTime(entry.e.endsAt)?.let { e -> "–" + e.format(timeFormat) } ?: "") } ?: "ganztägig", Stede.mudflat)
                                        entry.e.category?.let { Pill(it, Stede.ink) }
                                    }
                                    entry.e.location?.let { Text("📍 $it", fontSize = 12.sp, maxLines = 1) }
                                }
                            }
                        }
                        is Entry.Public -> StedeCard {
                            Backend.photoUrl(entry.e.imagePath)?.let { AsyncImage(it, null, Modifier.fillMaxWidth().height(160.dp).clip(RoundedCornerShape(12.dp))); Spacer(Modifier.height(10.dp)) }
                            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
                                val logo = Backend.logoUrl(entry.e.communityLogoPath)
                                if (logo != null) AsyncImage(logo, null, Modifier.size(38.dp).clip(RoundedCornerShape(12.dp)))
                                else Box(Modifier.size(38.dp).background(Stede.teal.copy(alpha = 0.16f), RoundedCornerShape(12.dp)), contentAlignment = Alignment.Center) {
                                    Text(entry.e.communityName.split(" ", "-").filter { it.isNotBlank() }.take(2).joinToString("") { it.first().uppercase() }, color = Stede.teal, fontWeight = FontWeight.Bold)
                                }
                                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                    Text(entry.e.title, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
                                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                        Pill(entry.time!!.format(timeFormat) + (parseTime(entry.e.endsAt)?.let { "–" + it.format(timeFormat) } ?: ""), Stede.teal)
                                        if (entry.e.helpersNeeded > 0) Pill("Helfer gesucht", Stede.heather)
                                    }
                                }
                            }
                            if (entry.e.description.isNotBlank()) Text(entry.e.description, Modifier.padding(top = 8.dp), fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.65f), maxLines = 4)
                            entry.e.location?.let { Text("📍 $it", fontSize = 12.sp, modifier = Modifier.padding(top = 6.dp)) }
                        }
                    }
                }
            }
            item { Text("Stadt Westerstede · westerstede.de/veranstaltungen · Community-Termine aus der App", fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f), modifier = Modifier.fillMaxWidth(), textAlign = androidx.compose.ui.text.style.TextAlign.Center) }
        }
    }
}

// MARK: Community

@Composable
fun CommunityScreen(tenant: Tenant?) {
    var communities by remember { mutableStateOf<List<Community>>(emptyList()) }
    LaunchedEffect(tenant) { tenant?.let { communities = runCatching { Backend.communities(it.id) }.getOrDefault(emptyList()) } }
    LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            StedeCard {
                Text("Communities sind Gruppen aus ${tenant?.municipality ?: "Westerstede"} mit eigenem Kalender – Verein, Nachbarschaft, Chor.", color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                Text("Anmeldung und Beitritt folgen in der Android-Version.", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f), modifier = Modifier.padding(top = 8.dp))
            }
        }
        item { SectionHeader("Communities") }
        items(communities) { c ->
            StedeCard {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
                    val logo = Backend.logoUrl(c.logoPath)
                    if (logo != null) AsyncImage(logo, null, Modifier.size(38.dp).clip(RoundedCornerShape(12.dp)))
                    else Box(Modifier.size(38.dp).background(Stede.teal.copy(alpha = 0.16f), RoundedCornerShape(12.dp)), contentAlignment = Alignment.Center) {
                        Text(c.name.split(" ", "-").filter { it.isNotBlank() }.take(2).joinToString("") { it.first().uppercase() }, color = Stede.teal, fontWeight = FontWeight.Bold)
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(c.name, fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
                        if (c.description.isNotBlank()) Text(c.description, fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.65f), maxLines = 2)
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Pill(if (c.memberCount == 1) "1 Mitglied" else "${c.memberCount} Mitglieder", Stede.teal)
                            Pill(if (c.joinPolicy == "open") "offen" else "auf Anfrage", Stede.mudflat)
                        }
                    }
                }
            }
        }
    }
}
