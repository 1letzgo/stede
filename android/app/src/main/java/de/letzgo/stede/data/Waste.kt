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

data class WasteSelection(val street: Int, val section: Int?, val branch: Int?) { val key get() = "$street-${section ?: 0}-${branch ?: 0}" }

object Waste {
    /** Stand aus dem Backend (`content_files`), sonst das Asset. */
    private val directory by lazy {
        ContentFiles.text("abfuhr-strassen")?.let { runCatching { Http.json.decodeFromString<WasteStreets>(it) }.getOrNull() }?.takeIf { it.streets.isNotEmpty() }
            ?: Http.json.decodeFromString<WasteStreets>(Store.asset("abfuhr-strassen.json"))
    }
    val source get() = directory.source
    val streets: List<WasteStreet> get() = directory.streets
    fun street(id: Int) = streets.firstOrNull { it.id == id }

    fun selection(): WasteSelection? {
        val street = street(Store.int("waste.street")) ?: return null
        val section = Store.int("waste.section"); val branch = Store.int("waste.branchSection")
        if (street.needsSection && section == 0) return null
        if (street.needsBranch && branch == 0) return null
        return WasteSelection(street.id, if (street.needsSection) section else null, if (street.needsBranch) branch else null)
    }

    private val line = Regex("""^\s*(?:Montag|Dienstag|Mittwoch|Donnerstag|Freitag|Samstag|Sonntag),\s*(\d{1,2})\.(\d{1,2})\.\s+(.+?)\s*$""")
    fun parse(text: String, year: Int): List<WasteCollection> = text.lines().mapNotNull { l ->
        val m = line.find(l) ?: return@mapNotNull null
        val date = runCatching { LocalDate.of(year, m.groupValues[2].toInt(), m.groupValues[1].toInt()) }.getOrNull() ?: return@mapNotNull null
        WasteCollection(date.toString(), m.groupValues[3])
    }.distinctBy { it.date + it.label }.sortedBy { it.date }

    private fun cachedYear(sel: WasteSelection, year: Int) = Store.read("waste", "${sel.key}-$year.json")?.let { runCatching { Http.json.decodeFromString(ListSerializer(WasteCollection.serializer()), it) }.getOrNull() }

    private suspend fun year(sel: WasteSelection, year: Int, force: Boolean): List<WasteCollection> {
        if (!force) cachedYear(sel, year)?.let { return it }
        // Erst der Server (Edge Function `waste-calendar`, PDF 7 Tage zwischengespeichert), dann direkt bei appfuhr.de.
        val server = runCatching {
            Http.bytes("${Backend.URL}/functions/v1/waste-calendar?street=${sel.street}&year=$year&section=${sel.section ?: ""}&branch=${sel.branch ?: ""}")
        }.getOrNull()?.let { pdf -> runCatching { parse(PDDocument.load(pdf).use { PDFTextStripper().getText(it) }, year) }.getOrNull() }
        if (!server.isNullOrEmpty()) {
            Store.write("waste", "${sel.key}-$year.json", Http.json.encodeToString(ListSerializer(WasteCollection.serializer()), server))
            return server
        }
        val id = UUID.randomUUID().toString().replace("-", "")
        val yy = "%02d".format(year % 100)
        Http.text("https://www.appfuhr.de/api/makekal.php?uid=$id&str=${sel.street}&strgr=${sel.section ?: "null"}&astgr=${sel.branch ?: "null"}&komp=false&vier=false&jahr=$yy&max=999")
        Http.text("https://www.appfuhr.de/pdf/makepdf.php?uuid=$id&str=${sel.street}&jahr=$yy&sw=false")
        val pdf = Http.bytes("https://www.appfuhr.de/pdf/tmp/$id.pdf")
        val text = PDDocument.load(pdf).use { PDFTextStripper().getText(it) }
        val list = parse(text, year)
        if (list.isEmpty()) error("Der Abfuhrkalender enthält keine Termine.")
        Store.write("waste", "${sel.key}-$year.json", Http.json.encodeToString(ListSerializer(WasteCollection.serializer()), list))
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
