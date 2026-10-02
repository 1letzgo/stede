package de.letzgo.stede.data

import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import java.time.LocalDate
import java.util.UUID

// MARK: Abfuhr — appfuhr.de, wie WasteClient in iOS (PDF erzeugen, laden, Text lesen)

@Serializable data class WasteSection(val id: Int, val label: String)
@Serializable data class WasteStreet(val id: Int, val name: String, val sections: List<WasteSection>? = null, val branchSections: List<WasteSection>? = null) {
    val needsSection get() = (sections?.size ?: 0) > 1
    val needsBranch get() = (branchSections?.size ?: 0) > 1
}
@Serializable private data class WasteStreets(val source: String = "", val streets: List<WasteStreet> = emptyList())

enum class WasteKind(val label: String) {
    Rest("Restabfall"), Papier("Papier"), Gelb("Gelber Sack"), Bio("Bioabfall"), Ast("Ast- und Strauchwerk"), Problem("Problemstoffe"), Sonst("Sonstiges");
    companion object { fun of(label: String) = entries.firstOrNull { it.label == label } ?: Sonst }
}
@Serializable data class WasteCollection(val date: String, val label: String) { val day: LocalDate get() = LocalDate.parse(date); val kind get() = WasteKind.of(label) }

/** `noOrganic`: Eigenkompostierer ohne Biotonne (appfuhr `komp=true`); `fourWeekly`: Restabfall alle 4 Wochen (`vier=true`). */
data class WasteSelection(val street: Int, val section: Int?, val branch: Int?, val noOrganic: Boolean = false, val fourWeekly: Boolean = false) {
    /** Ohne Optionen wie bisher; jede Option bekommt einen eigenen Cache-Eintrag. */
    val key get() = "$street-${section ?: 0}-${branch ?: 0}" + (if (noOrganic) "-nobio" else "") + (if (fourWeekly) "-4w" else "")
}

object Waste {
    /** Straßen der aktuellen Gemeinde: Stand aus dem Backend (`content_files`), sonst (nur Westerstede) das Asset. */
    private var loaded: Pair<String, WasteStreets>? = null
    private val directory: WasteStreets
        get() = loaded?.takeIf { it.first == Tenants.slug }?.second ?: (
            ContentFiles.text("abfuhr-strassen")?.let { runCatching { Http.json.decodeFromString<WasteStreets>(it) }.getOrNull() }?.takeIf { it.streets.isNotEmpty() }
                ?: if (Tenants.usesBundle) Http.json.decodeFromString<WasteStreets>(Store.asset("abfuhr-strassen.json")) else WasteStreets()
            ).also { loaded = Tenants.slug to it }
    val source get() = directory.source
    val streets: List<WasteStreet> get() = directory.streets
    fun street(id: Int) = streets.firstOrNull { it.id == id }

    fun selection(): WasteSelection? {
        val street = street(Store.int("waste.street")) ?: return null
        val section = Store.int("waste.section"); val branch = Store.int("waste.branchSection")
        if (street.needsSection && section == 0) return null
        if (street.needsBranch && branch == 0) return null
        return WasteSelection(street.id, if (street.needsSection) section else null, if (street.needsBranch) branch else null,
            Store.bool("waste.noOrganic", false), Store.bool("waste.fourWeekly", false))
    }

    private val line = Regex("""^\s*(?:Montag|Dienstag|Mittwoch|Donnerstag|Freitag|Samstag|Sonntag),\s*(\d{1,2})\.(\d{1,2})\.\s+(.+?)\s*$""")
    private val kinds = setOf("Restabfall", "Papier", "Gelber Sack", "Bioabfall", "Ast- und Strauchwerk", "Problemstoffe")

    /** Zwei Abfuhren am selben Tag: Das PDF nennt das Datum nur einmal, die zweite Art steht allein
     *  in der Folgezeile (oft mit Monatsnamen dazwischen) und gehört zum zuletzt genannten Datum. */
    fun parse(text: String, year: Int): List<WasteCollection> {
        var lastDate: LocalDate? = null
        return text.lines().mapNotNull { l ->
            val m = line.find(l)
            if (m == null) {
                val label = l.trim()
                return@mapNotNull lastDate?.takeIf { label in kinds }?.let { WasteCollection(it.toString(), label) }
            }
            val date = runCatching { LocalDate.of(year, m.groupValues[2].toInt(), m.groupValues[1].toInt()) }.getOrNull() ?: return@mapNotNull null
            lastDate = date
            WasteCollection(date.toString(), m.groupValues[3])
        }.distinctBy { it.date + it.label }.sortedBy { it.date }
    }

    /** `v2`: Doppeltermine werden mitgelesen — ältere Dateien haben dort Lücken. */
    private fun cacheName(sel: WasteSelection, year: Int) = "v2-${sel.key}-$year.json"

    private fun cachedYear(sel: WasteSelection, year: Int) = Store.read("waste", cacheName(sel, year))?.let { runCatching { Http.json.decodeFromString(ListSerializer(WasteCollection.serializer()), it) }.getOrNull() }

    private suspend fun year(sel: WasteSelection, year: Int, force: Boolean): List<WasteCollection> {
        if (!force) cachedYear(sel, year)?.let { return it }
        // Erst der Server (Edge Function `waste-calendar`, PDF 7 Tage zwischengespeichert), dann direkt bei appfuhr.de.
        val server = runCatching {
            Http.bytes("${Backend.URL}/functions/v1/waste-calendar?street=${sel.street}&year=$year&section=${sel.section ?: ""}&branch=${sel.branch ?: ""}&komp=${sel.noOrganic}&vier=${sel.fourWeekly}")
        }.getOrNull()?.let { pdf -> runCatching { parse(PDDocument.load(pdf).use { PDFTextStripper().getText(it) }, year) }.getOrNull() }
        if (!server.isNullOrEmpty()) {
            Store.write("waste", cacheName(sel, year), Http.json.encodeToString(ListSerializer(WasteCollection.serializer()), server))
            Store.file("waste", "${sel.key}-$year.json").delete()
            return server
        }
        val id = UUID.randomUUID().toString().replace("-", "")
        val yy = "%02d".format(year % 100)
        Http.text("https://www.appfuhr.de/api/makekal.php?uid=$id&str=${sel.street}&strgr=${sel.section ?: "null"}&astgr=${sel.branch ?: "null"}&komp=${sel.noOrganic}&vier=${sel.fourWeekly}&jahr=$yy&max=999")
        Http.text("https://www.appfuhr.de/pdf/makepdf.php?uuid=$id&str=${sel.street}&jahr=$yy&sw=false")
        val pdf = Http.bytes("https://www.appfuhr.de/pdf/tmp/$id.pdf")
        val text = PDDocument.load(pdf).use { PDFTextStripper().getText(it) }
        val list = parse(text, year)
        if (list.isEmpty()) error("Der Abfuhrkalender enthält keine Termine.")
        Store.write("waste", cacheName(sel, year), Http.json.encodeToString(ListSerializer(WasteCollection.serializer()), list))
        Store.file("waste", "${sel.key}-$year.json").delete()
        return list
    }

    fun cachedUpcoming(sel: WasteSelection): List<WasteCollection>? {
        val today = Town.today()
        return cachedYear(sel, today.year)?.filter { !it.day.isBefore(today) }
    }

    suspend fun upcoming(sel: WasteSelection, force: Boolean = false): List<WasteCollection> {
        val today = Town.today()
        var all = year(sel, today.year, force)
        if (today.monthValue >= 12) all = all + runCatching { year(sel, today.year + 1, force) }.getOrDefault(emptyList())
        return all.filter { !it.day.isBefore(today) }
    }
}
