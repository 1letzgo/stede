package de.letzgo.stede.ui

import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.letzgo.stede.data.*
import java.time.LocalDate
import kotlinx.coroutines.launch

enum class CalendarFilter(val title: String) { All("Alle"), City("Öffentlich"), Communities("Gruppen"), Mine("Meine") }

/** Kalender-Eintrag: Stadt-Termin oder Community-Termin. */
sealed class CalendarEntry {
    abstract val day: LocalDate; abstract val sortKey: String; abstract val isOver: Boolean
    data class City(val e: CityEvent) : CalendarEntry() {
        override val day: LocalDate = LocalDate.parse(e.day); override val sortKey = e.startsAt ?: e.day
        override val isOver get() = Town.parse(e.startsAt)?.let { !eventEnd(it, Town.parse(e.endsAt), false).isAfter(Town.now()) }
            ?: !day.plusDays(1).atStartOfDay(Town.zone).isAfter(Town.now())
    }
    data class Community(val e: EventInfo) : CalendarEntry() { override val day: LocalDate = e.starts.withZoneSameInstant(Town.zone).toLocalDate(); override val sortKey = e.starts.toInstant().toString(); override val isOver get() = e.isOver }
}

/** Zeilen der fortlaufenden Liste — flach, damit „Heute“ einen festen Index hat. */
private sealed class CalendarRow(val key: String) {
    data object Earlier : CalendarRow("earlier")
    data class Header(val day: LocalDate) : CalendarRow("h$day")
    data class NoneToday(val day: LocalDate) : CalendarRow("n$day")
    data class Entry(val entry: CalendarEntry) : CalendarRow(when (entry) { is CalendarEntry.City -> "c${entry.e.externalId}${entry.e.day}"; is CalendarEntry.Community -> "m${entry.e.id}" })
    data class Later(val end: LocalDate) : CalendarRow("later$end")
    data object Footer : CalendarRow("footer")
    data object Locked : CalendarRow("locked")
}

private const val PAGE_DAYS = 21L
private const val HORIZON_DAYS = 365L

/** Kalender wie EventView: fortlaufende Liste ab heute, Filterzeile oben, nach unten
 *  lädt sie selbst weiter, frühere Termine auf Tipp, „Heute“ in der Leiste springt zurück. */
@Composable
fun CalendarScreen() {
    val today = Town.today()
    // Startet heute — Vergangenes nur über „Frühere Termine“.
    var start by remember { mutableStateOf(today) }
    var end by remember { mutableStateOf(today.plusDays(PAGE_DAYS - 1)) }
    // Ohne Gruppen gibt es nur die Gemeinde-Termine — keine Filter.
    val groups = Features.has(Feature.Groups)
    var filter by remember { mutableStateOf(if (!groups) CalendarFilter.All else runCatching { CalendarFilter.valueOf(Store.string("calendar.filter", "All")) }.getOrDefault(CalendarFilter.All)) }
    // Baustein `plus` ohne Kauf: nur heute, dafür der ganze Tag.
    val locked = !PlusStore.canChangeDay
    var city by remember { mutableStateOf(CityEvents.cached("feed")) }
    var community by remember { mutableStateOf<List<EventInfo>>(emptyList()) }
    var helpers by remember { mutableStateOf<Map<String, Int>>(emptyMap()) }
    var commentCounts by remember { mutableStateOf<Map<String, Int>>(emptyMap()) }
    var commenting by remember { mutableStateOf<EventInfo?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var open by remember { mutableStateOf<EventInfo?>(null) }
    var showAccount by remember { mutableStateOf(false) }
    var loadingEarlier by remember { mutableStateOf(false) }
    var loadingLater by remember { mutableStateOf(false) }
    var didScroll by remember { mutableStateOf(false) }
    // Erster Ladeversuch der Gruppen-Termine abgeschlossen — erst dann auf heute springen, weil sie
    // die Roh-Termine der Stadt ersetzen und sonst alles über „heute“ verschieben.
    var communityLoaded by remember { mutableStateOf(false) }
    // Nach „Frühere Termine“: Schlüssel der Zeile, die vorher ganz oben stand und nun unten am Rand stehen soll.
    var earlierAnchor by remember { mutableStateOf<String?>(null) }
    val openUrl = rememberOpenUrl()
    val userId = Session.userId
    val memberIds = Session.activeCommunityIds
    val scope = rememberCoroutineScope()
    val listState = androidx.compose.foundation.lazy.rememberLazyListState()

    // Öffentliche (auch übernommene) Termine lädt jede App; Gruppen-Termine nur mit dem Baustein Gruppen.
    suspend fun communityRange(from: LocalDate, through: LocalDate): List<EventInfo> {
        val f = from.atStartOfDay(Town.zone).toOffsetDateTime().toString(); val t = through.plusDays(1).atStartOfDay(Town.zone).toOffsetDateTime().toString()
        val tenant = Tenants.current()
        val own = if (groups) CommunityApi.events(memberIds, f, t).map { EventInfo.of(it) } else emptyList()
        val ownIds = own.map { it.id }.toSet()
        return own + CommunityApi.publicEvents(tenant.id, f, t).filter { it.id !in ownIds }.map { EventInfo.of(it) }
    }
    suspend fun refreshHelpers() { runCatching { helpers = CommunityApi.helperCounts(community.filter { it.helpersNeeded > 0 }.map { it.id }) } }
    // Kommentarzahlen nur für interne Termine mit eingeschalteten Kommentaren (öffentliche haben keine).
    suspend fun refreshComments() { runCatching { commentCounts = CommunityApi.commentCounts(community.filter { it.commentsEnabled }.map { it.id }) } }

    // Ganzer geladener Bereich — beim Start, bei An-/Abmeldung und nach Änderungen.
    LaunchedEffect(userId, memberIds, Changes.version) {
        error = null
        runCatching { CityEvents.range(start, end, cacheAs = if (start == today) "feed" else null) }
            .onSuccess { city = it }.onFailure { if (city == null) error = "Termine konnten nicht geladen werden." }
        runCatching { community = communityRange(start, end) }
        communityLoaded = true
        if (groups) { refreshHelpers(); refreshComments(); MyParticipation.load() }
    }

    fun loadLater() {
        if (loadingLater || end >= today.plusDays(HORIZON_DAYS)) return
        loadingLater = true
        scope.launch {
            val from = end.plusDays(1); val to = end.plusDays(PAGE_DAYS)
            val more = runCatching { CityEvents.range(from, to) }.getOrDefault(emptyList())
            val moreCommunity = runCatching { communityRange(from, to) }.getOrDefault(emptyList())
            city = (city.orEmpty() + more).distinctBy { it.externalId + it.day }
            community = (community + moreCommunity).distinctBy { it.id }
            end = to; loadingLater = false
            refreshHelpers()
            refreshComments()
        }
    }

    fun loadEarlier(anchorKey: String?) {
        if (loadingEarlier) return
        loadingEarlier = true
        scope.launch {
            val to = start.minusDays(1); val from = start.minusDays(PAGE_DAYS)
            val more = runCatching { CityEvents.range(from, to) }.getOrDefault(emptyList())
            val moreCommunity = runCatching { communityRange(from, to) }.getOrDefault(emptyList())
            city = (more + city.orEmpty()).distinctBy { it.externalId + it.day }
            community = (moreCommunity + community).distinctBy { it.id }
            start = from; loadingEarlier = false
            earlierAnchor = anchorKey
            refreshHelpers()
            refreshComments()
        }
    }

    // Gemeinde-Termine kommen als übernommene Termine der Gruppe „stede Veranstaltungen“; die Rohdaten
    // (city_events, offline im Cache) nur, solange davon nichts geladen ist — ohne Netz oder vor dem Import.
    val showsRawCity = community.none { it.isImported }
    val entries = buildList {
        if ((filter == CalendarFilter.All || filter == CalendarFilter.City) && showsRawCity) city?.forEach { add(CalendarEntry.City(it)) }
        community.forEach { e ->
            val mine = MyParticipation.byEvent[e.id]?.status.let { it == "going" || it == "maybe" } || e.createdBy == userId
            val show = when (filter) { CalendarFilter.All -> true; CalendarFilter.City -> e.isImported; CalendarFilter.Communities -> !e.isImported; CalendarFilter.Mine -> mine }
            if (show) add(CalendarEntry.Community(e))
        }
    }.filter { locked || start.isBefore(today) || !it.isOver } // Vorbei ausgeblendet, bis frühere Termine angefordert sind
        .filter { !locked || it.day == today }
        .sortedBy { it.sortKey }.groupBy { it.day }

    // Nur Tage mit Terminen, dazu immer heute.
    val rows = buildList {
        if (!locked) add(CalendarRow.Earlier)
        (entries.keys.filter { !it.isBefore(start) && !it.isAfter(end) } + today).distinct().sorted().forEach { day ->
            add(CalendarRow.Header(day))
            val list = entries[day].orEmpty()
            if (list.isEmpty()) add(CalendarRow.NoneToday(day)) else list.forEach { add(CalendarRow.Entry(it)) }
        }
        if (locked) add(CalendarRow.Locked) else if (end < today.plusDays(HORIZON_DAYS)) add(CalendarRow.Later(end))
        add(CalendarRow.Footer)
    }
    val todayIndex = rows.indexOfFirst { it is CalendarRow.Header && it.day == today }

    // Grenze halten: der bisher erste Tag rückt an den unteren Rand, die neu geladenen Termine stehen direkt darüber.
    LaunchedEffect(earlierAnchor) {
        val key = earlierAnchor ?: return@LaunchedEffect
        val index = rows.indexOfFirst { it.key == key }
        if (index >= 0) listState.scrollItemToBottom(index)
        earlierAnchor = null
    }

    LaunchedEffect(city != null || error != null, communityLoaded) {
        if (!didScroll && (city != null || error != null) && communityLoaded && todayIndex >= 0) { didScroll = true; listState.scrollToItem(todayIndex) }
    }

    Scaffold(topBar = {
        StedeTopBar("Kalender", actions = {
            TextButton(onClick = { scope.launch { listState.animateScrollToItem(todayIndex.coerceAtLeast(0)) } }) { Text("Heute", color = androidx.compose.ui.graphics.Color.White) }
        })
    }, containerColor = C.sand) { pad ->
        Column(Modifier.padding(pad).fillMaxSize()) {
            if (groups) Box(Modifier.padding(top = 16.dp, bottom = Spacing)) { Switcher(CalendarFilter.entries, filter, { it.title }) { filter = it; Store.setString("calendar.filter", it.name) } }
            else Spacer(Modifier.height(16.dp))
            if (city == null && error == null && community.isEmpty()) Loading()
            error?.let { Box(Modifier.padding(horizontal = 16.dp)) { InfoCard(it) } }
            LazyColumn(state = listState, contentPadding = PaddingValues(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
                items(rows, key = { it.key }) { row ->
                    Box(Modifier.padding(horizontal = 16.dp)) {
                        when (row) {
                            CalendarRow.Earlier -> SelectionChip(if (loadingEarlier) "Lade …" else "Frühere Termine", false, Modifier.fillMaxWidth(), icon = Icons.Default.KeyboardArrowUp) { loadEarlier(rows.firstOrNull { it is CalendarRow.Header }?.key) }
                            is CalendarRow.Header -> SectionHeader((if (row.day == today) "Heute, " else "") + row.day.format(Town.fmt(if (row.day.year == today.year) "EEEE, d. MMM" else "EEEE, d. MMM yyyy")), if (row.day == today) Icons.Default.WbSunny else null)
                            is CalendarRow.NoneToday -> Text("Heute keine Termine", color = C.tertiary, fontSize = 15.sp, modifier = Modifier.padding(horizontal = 4.dp))
                            is CalendarRow.Entry -> when (val entry = row.entry) {
                                is CalendarEntry.City -> CityEventRow(entry.e) { entry.e.detailUrl?.let(openUrl) }
                                is CalendarEntry.Community -> EventCard(entry.e, helpers[entry.e.id], onSignIn = { showAccount = true },
                                    commentCount = commentCounts[entry.e.id] ?: 0, onComments = { commenting = entry.e }, showsMenu = true) { open = entry.e }
                            }
                            is CalendarRow.Later -> {
                                Box(Modifier.fillMaxWidth().padding(vertical = 8.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp) }
                                LaunchedEffect(row.end) { loadLater() }
                            }
                            CalendarRow.Locked -> SelectionChip("Weitere Tage mit ${Brand.current.plusName}", false, Modifier.fillMaxWidth(), icon = Icons.Default.Lock) { AppNav.plusRequested++ }
                            CalendarRow.Footer -> SourceFooter(Tenants.config.notes?.get("events") ?: if (Tenants.usesBundle) "Stadt Westerstede · westerstede.de/veranstaltungen und Gruppen"
                                else "${Tenants.config.officialName} · Ammerland-Touristik (destination.one) und Gruppen")
                        }
                    }
                }
            }
        }
    }
    open?.let { e -> EventDetailSheet(e, helpers[e.id], onSignIn = { open = null; showAccount = true }) { open = null } }
    commenting?.let { e -> CommentsSheet(e.title, CommentTarget.Event(e.id), canModerate = canEdit(e)) { commenting = null; scope.launch { refreshComments() } } }
    if (showAccount) AccountSheet { showAccount = false }
}

/** Scrollt so, dass die Zeile [index] am unteren Rand des sichtbaren Bereichs steht —
 *  für „Frühere Termine“: die neu geladenen Einträge liegen dann direkt darüber. */
internal suspend fun LazyListState.scrollItemToBottom(index: Int) {
    scrollToItem(index)
    val info = layoutInfo
    val item = info.visibleItemsInfo.firstOrNull { it.index == index } ?: return
    val bottom = info.viewportEndOffset - info.afterContentPadding
    val delta = item.offset + item.size - bottom
    if (delta < 0) scrollBy(delta.toFloat())
}

/** Kompakte Karte für Stadt-Termine: Zeit-Pille, Titel, Ort; Tipp öffnet die Seite der Stadt. */
@Composable
private fun CityEventRow(e: CityEvent, onClick: () -> Unit) {
    val start = Town.parse(e.startsAt); val end = Town.parse(e.endsAt)
    val time = start?.let { st -> st.format(Town.hm) + (end?.let { "–${it.format(Town.hm)}" } ?: "") } ?: "ganztägig"
    // Vorschaubild als Kopf der Karte, wie bei den Gruppen-Terminen.
    StedeCard(onClick = if (e.detailUrl != null) onClick else null, header = e.imageUrl?.let { url -> { EventPhoto(url, 170.dp) } }) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
            IconChip(Icons.Default.AccountBalance, C.mudflat)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(e.title, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = C.text)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Pill(time, C.mudflat); e.category?.let { Pill(it, C.ink) }
                    if (e.soldOut) Pill("ausgebucht", C.red)
                    e.price?.let { Pill(it, C.teal) }
                }
            }
        }
        // Ort linksbündig unter der Kopfzeile — wie bei den Gruppen-Terminen.
        e.location?.let { Box(Modifier.padding(top = 10.dp)) { LocationLine(it) } }
        e.registration?.let { Box(Modifier.padding(top = 6.dp)) { InfoLine(Icons.Default.HowToReg, it) } }
    }
}
