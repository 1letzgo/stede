package de.letzgo.stede.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
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

enum class CalendarFilter(val title: String) { All("Alle"), City("Öffentlich"), Communities("Communities"), Mine("Meine") }

/** Kalender-Eintrag: Stadt-Termin oder Community-Termin. */
sealed class CalendarEntry {
    abstract val day: LocalDate; abstract val sortKey: String
    data class City(val e: CityEvent) : CalendarEntry() { override val day: LocalDate = LocalDate.parse(e.day); override val sortKey = e.startsAt ?: e.day }
    data class Community(val e: EventInfo) : CalendarEntry() { override val day: LocalDate = e.starts.withZoneSameInstant(Town.zone).toLocalDate(); override val sortKey = e.starts.toInstant().toString() }
}

/** Wochenkalender wie EventView: Filterzeile oben, Tage der Woche, schwebende Wochen-Navigation. */
@Composable
fun CalendarScreen() {
    var week by remember { mutableStateOf(Town.weekStart(Town.today())) }
    var filter by remember { mutableStateOf(runCatching { CalendarFilter.valueOf(Store.string("calendar.filter", "All")) }.getOrDefault(CalendarFilter.All)) }
    var city by remember { mutableStateOf(CityEvents.cached(week)) }
    var community by remember { mutableStateOf<List<EventInfo>>(emptyList()) }
    var helpers by remember { mutableStateOf<Map<String, Int>>(emptyMap()) }
    var error by remember { mutableStateOf<String?>(null) }
    var open by remember { mutableStateOf<EventInfo?>(null) }
    val openUrl = rememberOpenUrl()
    val userId = Session.userId
    val memberIds = Session.activeCommunityIds

    val listState = androidx.compose.foundation.lazy.rememberLazyListState()
    LaunchedEffect(week) { listState.scrollToItem(0) }
    LaunchedEffect(week, userId, memberIds, Changes.version) {
        city = CityEvents.cached(week) ?: city?.takeIf { false }
        error = null
        runCatching { CityEvents.week(week) }.onSuccess { city = it }.onFailure { if (city == null) error = "Termine konnten nicht geladen werden." }
        val from = week.atStartOfDay(Town.zone).toOffsetDateTime().toString(); val to = week.plusDays(7).atStartOfDay(Town.zone).toOffsetDateTime().toString()
        runCatching {
            val tenant = Tenants.current()
            val own = CommunityApi.events(memberIds, from, to).map { EventInfo.of(it) }
            val ownIds = own.map { it.id }.toSet()
            val public = CommunityApi.publicEvents(tenant.id, from, to).filter { it.id !in ownIds }.map { EventInfo.of(it) }
            community = own + public
            helpers = CommunityApi.helperCounts(community.filter { it.helpersNeeded > 0 }.map { it.id })
        }
        MyParticipation.load()
        if (listState.firstVisibleItemIndex > 0 && !listState.isScrollInProgress) listState.scrollToItem(0)
    }

    val entries = buildList {
        if (filter == CalendarFilter.All || filter == CalendarFilter.City) city?.forEach { add(CalendarEntry.City(it)) }
        community.forEach { e ->
            val mine = MyParticipation.byEvent[e.id]?.status.let { it == "going" || it == "maybe" } || e.createdBy == userId
            val show = when (filter) { CalendarFilter.All -> true; CalendarFilter.City -> false; CalendarFilter.Communities -> true; CalendarFilter.Mine -> mine }
            if (show) add(CalendarEntry.Community(e))
        }
    }.sortedBy { it.sortKey }.groupBy { it.day }

    Scaffold(topBar = { StedeTopBar("Kalender") }, containerColor = C.sand) { pad ->
        Box(Modifier.padding(pad).fillMaxSize()) {
            Column(Modifier.fillMaxSize()) {
            Box(Modifier.padding(top = 16.dp, bottom = Spacing)) { Switcher(CalendarFilter.entries, filter, { it.title }) { filter = it; Store.setString("calendar.filter", it.name) } }
            LazyColumn(state = listState, contentPadding = PaddingValues(bottom = 96.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
                if (city == null && error == null && community.isEmpty()) item { Loading() }
                error?.let { item { Box(Modifier.padding(horizontal = 16.dp)) { InfoCard(it) } } }
                (0L..6L).map { week.plusDays(it) }.forEach { day ->
                    val list = entries[day].orEmpty()
                    if (list.isEmpty() && day != Town.today()) return@forEach
                    item(key = "h$day") {
                        Row(Modifier.padding(horizontal = 16.dp).padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(if (day == Town.today()) "Heute" else day.format(Town.dayLong), fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = if (day == Town.today()) C.teal else C.text)
                            if (day == Town.today() && list.isNotEmpty()) Text(day.format(Town.dayLong), color = C.secondary, fontSize = 14.sp)
                        }
                    }
                    if (list.isEmpty()) item(key = "e$day") { Box(Modifier.padding(horizontal = 16.dp)) { InfoCard("Heute keine Termine.") } }
                    items(list, key = { when (it) { is CalendarEntry.City -> "c${it.e.externalId}${it.e.day}"; is CalendarEntry.Community -> "m${it.e.id}" } }) { entry ->
                        Box(Modifier.padding(horizontal = 16.dp)) {
                            when (entry) {
                                is CalendarEntry.City -> CityEventRow(entry.e) { entry.e.detailUrl?.let(openUrl) }
                                is CalendarEntry.Community -> EventCard(entry.e, helpers[entry.e.id]) { open = entry.e }
                            }
                        }
                    }
                }
                if (entries.isEmpty() && city != null) item { Box(Modifier.padding(horizontal = 16.dp)) { InfoCard("Keine Termine in dieser Woche.") } }
                item { SourceFooter("Stadt Westerstede · westerstede.de/veranstaltungen und Communities") }
            }
            }
            DayBar(week, week = true, modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 12.dp)) { week = Town.weekStart(it) }
        }
    }
    open?.let { e -> EventDetailSheet(e, helpers[e.id]) { open = null } }
}

@Composable
private fun CityEventRow(e: CityEvent, onClick: () -> Unit) {
    val start = Town.parse(e.startsAt); val end = Town.parse(e.endsAt)
    val time = start?.let { s -> s.format(Town.hm) + (end?.let { "–${it.format(Town.hm)}" } ?: "") } ?: "Ganztägig"
    StedeCard(onClick = onClick) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
            IconChip(Icons.Default.Event, C.red)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(e.title, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = C.text, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { Pill(time, C.teal); e.category?.let { Pill(it, C.mudflat) } }
                e.location?.let { Text(it, color = C.secondary, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis) }
                if (e.summary.isNotBlank()) Text(e.summary, color = C.text, fontSize = 14.sp, maxLines = 3, overflow = TextOverflow.Ellipsis)
                e.seriesNote?.let { Text(it, color = C.secondary, fontSize = 12.sp) }
            }
        }
    }
}
