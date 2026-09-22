package de.letzgo.stede.data

import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.temporal.TemporalAdjusters
import java.util.Locale

/** Ortszeit der Stadt — wie IslandTime in iOS: immer Europe/Berlin, immer Deutsch. */
object Town {
    val zone: ZoneId = ZoneId.of("Europe/Berlin")
    val locale: Locale = Locale.GERMAN
    fun today(): LocalDate = LocalDate.now(zone)
    fun now(): ZonedDateTime = ZonedDateTime.now(zone)
    fun weekStart(day: LocalDate): LocalDate = day.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
    fun parse(iso: String?): ZonedDateTime? = iso?.let {
        runCatching { OffsetDateTime.parse(it).atZoneSameInstant(zone) }.getOrNull()
            ?: runCatching { Instant.parse(it).atZone(zone) }.getOrNull()
    }
    fun fmt(pattern: String): DateTimeFormatter = DateTimeFormatter.ofPattern(pattern, locale)
    val hm: DateTimeFormatter = fmt("HH:mm")
    val dayShort: DateTimeFormatter = fmt("EE d. MMM")
    val dayLong: DateTimeFormatter = fmt("EEEE, d. MMM")
    val dayFull: DateTimeFormatter = fmt("EEEE, d. MMMM yyyy")
}
