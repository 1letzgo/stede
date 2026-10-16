package de.letzgo.stede.data

import io.ktor.client.HttpClient
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.plugins.cookies.AcceptAllCookiesStorage
import io.ktor.client.plugins.cookies.HttpCookies
import io.ktor.client.request.HttpRequestBuilder
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsBytes
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.content.TextContent
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import org.jsoup.nodes.Element
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZonedDateTime

// Politik: Ratsinformationssystem ALLRIS net 3.9 (`tenants.config.ris.url`), übernommen aus dem
// Projekt „rischen“ — Gegenstück zu Council.swift / CouncilClient.swift in iOS.

/** Sitzung aus dem Sitzungskalender (`si010_e.asp`). */
@Serializable data class CouncilSession(
    /** SILFDNR. */
    val id: Int,
    val title: String,
    /** ISO-Zeit in Europe/Berlin. */
    val start: String,
    val end: String? = null,
    val hasTime: Boolean,
    val room: String? = null,
    val hasAgenda: Boolean,
) {
    val startTime: ZonedDateTime get() = ZonedDateTime.parse(start)
    val endTime: ZonedDateTime? get() = end?.let(ZonedDateTime::parse)
    val isOver get() = (endTime ?: startTime.plusHours(3)).isBefore(Town.now())

    /** Gremium ohne „Sitzung des …“: „Sozialausschusses“ → „Sozialausschuss“, „Rates der Stadt“ → „Rat der Stadt“. */
    val committee: String get() {
        val prefix = listOf("Sitzung des ", "Sitzung der ", "Sitzung ").firstOrNull { title.startsWith(it) } ?: return title
        val rest = title.removePrefix(prefix)
            .replace(Regex("^Rates\\b"), "Rat")
            .replace(Regex("(\\w)(ausschuss|rat|beirat)es\\b"), "$1$2")
            .replace(Regex("\\bAusschusses\\b"), "Ausschuss")
        return rest.replaceFirstChar { it.uppercase() }
    }
}

@Serializable data class CouncilAgendaItem(
    /** „Ö 4“ (öffentlich) oder „N 2“. */
    val number: String,
    val title: String,
    val result: String? = null,
    val paperId: Int? = null,
    val paperNumber: String? = null,
) { val isPublic get() = !number.startsWith("N") }

@Serializable data class CouncilAgenda(
    val sessionId: Int, val title: String, val committee: String, val date: String, val time: String,
    val room: String, val place: String, val documents: List<CouncilDocument>, val items: List<CouncilAgendaItem>,
)

/** Zeile der Vorlagenliste (`vo040.asp`). */
@Serializable data class CouncilPaper(
    val id: Int, val number: String, val subject: String, val office: String, val date: String, val kind: String,
    val hasAttachments: Boolean, val hasResolution: Boolean,
)

data class CouncilPaperPage(val items: List<CouncilPaper>, val approximateTotal: Int?, val hasNext: Boolean)

data class CouncilConsultation(
    val committee: String, val role: String, val status: String, val date: String?,
    val sessionId: Int?, val sessionName: String?, val result: String?,
)

/** PDF; die Temp-Adresse holt [Council.documentUrl] direkt vor dem Öffnen. */
@Serializable data class CouncilDocument(val title: String, val dolfdnr: Int? = null, val path: String? = null, val size: String? = null)

data class CouncilTextSection(val title: String, val paragraphs: List<String>)

data class CouncilPaperDetail(
    val id: Int, val number: String, val subject: String, val status: String, val kind: String, val office: String, val clerk: String,
    val consultations: List<CouncilConsultation>, val sections: List<CouncilTextSection>,
    val documents: List<CouncilDocument>, val attachments: List<CouncilDocument>,
)

/** Liest ALLRIS-net-Seiten. Reine Funktionen ohne Netz. */
object AllrisParser {
    private val rangeRegex = Regex("""Ergebnisse\s+(\d+)-(\d+)(?:\s+von\s+\D*?(\d+))?""")
    private val sectionAnchor = Regex("""<a name="allris([A-Z]+)"></a>""")
    private val sectionEnd = listOf("<a name=\"allris", "<table class=\"tk1\"", "<div id=\"risfoot\"")
    private val times = Regex("""(\d{1,2}):(\d{2})""")

    /** Monatsansicht; eine zweite Sitzung am selben Tag lässt die Tageszelle leer. */
    fun sessions(html: String, year: Int, month: Int): List<CouncilSession> {
        val result = mutableListOf<CouncilSession>()
        var day: Int? = null
        for (row in Jsoup.parse(html).select("tr.zl11, tr.zl12, tr.zl16, tr.zl17")) {
            val cells = row.children().filter { it.tagName() == "td" }
            if (cells.size < 4) continue
            cells[1].cleanText().toIntOrNull()?.let { day = it }
            val id = row.selectFirst("input[name=SILFDNR]")?.attr("value")?.toIntOrNull() ?: continue
            val dayOfMonth = day ?: continue
            val date = runCatching { LocalDate.of(year, month, dayOfMonth) }.getOrNull() ?: continue
            val found = times.findAll(cells[2].text()).map { LocalTime.of(it.groupValues[1].toInt(), it.groupValues[2].toInt()) }.toList()
            val titleCell = cells.getOrNull(5)
            result += CouncilSession(
                id = id,
                title = titleCell?.cleanText().orEmpty(),
                start = date.atTime(found.firstOrNull() ?: LocalTime.MIDNIGHT).atZone(Town.zone).toString(),
                end = found.getOrNull(1)?.let { date.atTime(it).atZone(Town.zone).toString() },
                hasTime = found.isNotEmpty(),
                room = cells.last().cleanText().ifEmpty { null },
                hasAgenda = titleCell?.selectFirst("a[href*=to010.asp]") != null,
            )
        }
        return result
    }

    fun agenda(html: String, sessionId: Int): CouncilAgenda {
        val doc = Jsoup.parse(html)
        val items = doc.select("tr.zl11, tr.zl12").mapNotNull { row ->
            val cells = row.children().filter { it.tagName() == "td" }
            val number = cells.firstOrNull()?.cleanText().orEmpty()
            if (cells.size < 4 || !Regex("^[ÖN]\\s*\\d").containsMatchIn(number)) return@mapNotNull null
            val result = row.selectFirst("input.il1_naz")?.attr("title")?.trim()
            val paper = row.selectFirst("a[href^=vo020.asp]")
            CouncilAgendaItem(
                number = number,
                title = row.selectFirst("a[href^=to020.asp]")?.cleanText() ?: cells[3].cleanText(),
                result = result?.takeIf { it.isNotEmpty() && it != "(offen)" },
                paperId = paper?.attr("href")?.substringAfter("VOLFDNR=")?.takeWhile { it.isDigit() }?.toIntOrNull(),
                paperNumber = paper?.cleanText(),
            )
        }
        return CouncilAgenda(sessionId, field(doc, "Bezeichnung:"), field(doc, "Gremium:"), field(doc, "Datum:"), field(doc, "Zeit:"),
            field(doc, "Raum:"), field(doc, "Ort:"), generatedDocuments(doc), items)
    }

    fun papers(html: String): CouncilPaperPage {
        val doc = Jsoup.parse(html)
        val items = doc.select("tr.zl11, tr.zl12").mapNotNull { row -> paperRow(row) }
        val range = doc.select("td.kb1").firstNotNullOfOrNull { rangeRegex.find(it.text()) }
        return CouncilPaperPage(items, range?.groupValues?.get(3)?.toIntOrNull(), doc.select("a[href*=shownext]").isNotEmpty())
    }

    private fun paperRow(row: Element): CouncilPaper? {
        val cells = row.children().filter { it.tagName() == "td" }
        if (cells.size < 7) return null
        val id = cells[0].selectFirst("input[name=VOLFDNR]")?.attr("value")?.toIntOrNull() ?: return null
        // „26/2190&nbsp;Stadtstrand 2026 …“: Nummer und Betreff teilen sich einen Link.
        val title = cells[1].text().replace(' ', ' ').trim()
        val number = title.substringBefore(' ')
        return CouncilPaper(id, number, title.removePrefix(number).trim(), cells[3].cleanText(), cells[5].cleanText(), cells[6].cleanText(),
            cells[0].selectFirst("img[src*=attmnt]") != null, cells[2].selectFirst("input[name=VOLFDNR]") != null)
    }

    fun paper(html: String, id: Int): CouncilPaperDetail {
        val doc = Jsoup.parse(html)
        return CouncilPaperDetail(
            id = id,
            number = doc.title().split(" - ").getOrNull(1)?.trim().orEmpty(),
            subject = field(doc, "Betreff:"), status = field(doc, "Status:"), kind = field(doc, "Vorlage-Art:"),
            office = field(doc, "Federführend:"), clerk = field(doc, "Bearbeiter/-in:"),
            consultations = consultations(doc), sections = sections(html, doc),
            documents = generatedDocuments(doc),
            attachments = doc.select("a[href*=___tmp]").map { a ->
                CouncilDocument(a.cleanText(), null, a.attr("href"),
                    a.attr("title").substringAfter("Größe:", "").substringBefore('\n').trim().ifEmpty { null })
            },
        )
    }

    private fun field(doc: Document, label: String): String =
        doc.select("td.kb1").firstOrNull { it.text().trim() == label }?.nextElementSibling()?.also { it.select("script").remove() }?.cleanText().orEmpty()

    private fun generatedDocuments(doc: Document) = doc.select("form[action=do027.asp]").mapNotNull { form ->
        val dolfdnr = form.selectFirst("input[name=DOLFDNR]")?.attr("value")?.toIntOrNull() ?: return@mapNotNull null
        CouncilDocument(form.selectFirst("input[type=submit]")?.attr("value") ?: "Dokument", dolfdnr)
    }

    private fun consultations(doc: Document): List<CouncilConsultation> {
        val header = doc.select("td.kb1").firstOrNull { it.text().trim() == "Beratungsfolge:" } ?: return emptyList()
        val table = header.parent()?.nextElementSibling()?.selectFirst("table") ?: return emptyList()
        val result = mutableListOf<CouncilConsultation>()
        var current: CouncilConsultation? = null
        for (row in table.select("tr.zl11, tr.zl12")) {
            val cells = row.children().filter { it.tagName() == "td" }
            val status = cells.firstOrNull()?.attr("title").orEmpty()
            val dateLink = row.selectFirst("a[href^=si010]")
            if (dateLink == null) {
                current?.let { result += it }
                current = CouncilConsultation(cells.getOrNull(1)?.cleanText().orEmpty(), cells.getOrNull(2)?.cleanText().orEmpty(), status, null, null, null, null)
            } else {
                val base = current ?: continue
                val session = base.copy(
                    status = status.ifEmpty { base.status }, date = dateLink.cleanText(),
                    sessionId = row.selectFirst("input[name=SILFDNR]")?.attr("value")?.toIntOrNull(),
                    sessionName = cells.getOrNull(3)?.cleanText()?.ifEmpty { null },
                    result = cells.getOrNull(4)?.cleanText()?.ifEmpty { null },
                )
                // Ein Gremium kann mehrmals über dieselbe Vorlage beraten: jede Sitzung behalten.
                if (base.date != null) result += base
                current = session
            }
        }
        current?.let { result += it }
        return result
    }

    /** Jeder Textblock ist ein eigenes HTML-Dokument direkt nach `<a name="allrisXX"></a>`. */
    private fun sections(html: String, doc: Document): List<CouncilTextSection> {
        val titles = doc.select("a[href^=#allris]").associate { it.attr("href").removePrefix("#allris") to it.cleanText() }
        return sectionAnchor.findAll(html).mapNotNull { match ->
            val key = match.groupValues[1]
            val start = match.range.last + 1
            val end = sectionEnd.mapNotNull { m -> html.indexOf(m, start).takeIf { it >= 0 } }.minOrNull() ?: html.length
            val fragment = Jsoup.parse(html.substring(start, end))
            fragment.select("h1, h2, h3, h4").remove()
            val paragraphs = fragment.select("p, li").map { it.cleanText() }.filter { it.isNotEmpty() }
                .ifEmpty { listOf(fragment.body().cleanText()).filter { it.isNotEmpty() } }
            if (paragraphs.isEmpty()) null else CouncilTextSection(titles[key] ?: key, paragraphs)
        }.toList()
    }

    private fun Element.cleanText(): String = text().replace(' ', ' ').trim()
}

/**
 * Zugriff auf das Bürgerinfo der gewählten Gemeinde. ALLRIS hält Filter und Blättern in der
 * ASP-Session, deshalb ein Cookie-Speicher je Gemeinde und Listenaufrufe strikt nacheinander.
 */
object Council {
    val isAvailable get() = Features.has(Feature.Politics) && Tenants.config.ris != null
    val host get() = Tenants.config.ris?.url?.let { runCatching { java.net.URI(it).host }.getOrNull() } ?: "Ratsinformationssystem"

    private var clientBase: String? = null
    private var client: HttpClient? = null
    private val lock = Mutex()
    private const val UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    private val base: String get() = (Tenants.config.ris?.url ?: error("Kein Ratsinformationssystem")).trimEnd('/') + "/"

    @Synchronized private fun http(): HttpClient {
        val b = base
        client?.takeIf { clientBase == b }?.let { return it }
        client?.close()
        return HttpClient(OkHttp) {
            install(HttpCookies) { storage = AcceptAllCookiesStorage() }
            install(HttpTimeout) { requestTimeoutMillis = 30_000 }
            // do027.asp leitet auf ein Temp-PDF weiter; gebraucht wird nur die Location.
            followRedirects = false
            expectSuccess = false
        }.also { client = it; clientBase = b }
    }

    suspend fun sessions(year: Int, month: Int) = AllrisParser.sessions(get("si010_e.asp?MM=$month&YY=$year"), year, month)
    suspend fun agenda(sessionId: Int) = AllrisParser.agenda(get("to010.asp?SILFDNR=$sessionId"), sessionId)
    fun agendaUrl(sessionId: Int) = base + "to010.asp?SILFDNR=$sessionId"

    /** Erste Seite, optional nach Betreff gefiltert; ersetzt den Filter der Session. */
    suspend fun papers(search: String = ""): CouncilPaperPage = lock.withLock {
        // Der Amtsfilter ist eine eigene Session-Einstellung; 99999999 heißt „(alle)“.
        get("vo040.asp?ATLFDNRM=99999999")
        val html = if (search.isBlank()) post("vo040.asp", listOf("filtreset" to "(alle)"))
        else post("vo040.asp", listOf("VO040FIL2" to search.trim(), "filtvobetr1" to "filter"))
        AllrisParser.papers(html)
    }

    suspend fun nextPapers(): CouncilPaperPage = lock.withLock { AllrisParser.papers(get("vo040.asp?shownext=true")) }

    suspend fun paper(id: Int) = AllrisParser.paper(get("vo020.asp?VOLFDNR=$id"), id)

    /** Frische Adresse eines PDFs — Temp-Pfade laufen ab, also direkt vor dem Öffnen. */
    suspend fun documentUrl(document: CouncilDocument, paperId: Int?): String {
        document.dolfdnr?.let { dolfdnr ->
            val response = http().post(base + "do027.asp") { ua(); form(listOf("DOLFDNR" to "$dolfdnr", "options" to "64")) }
            return resolve(response.headers[HttpHeaders.Location] ?: error("Dokument nicht verfügbar (HTTP ${response.status.value})"))
        }
        val fresh = paperId?.let { id -> runCatching { paper(id) }.getOrNull()?.attachments?.firstOrNull { it.title == document.title }?.path }
        return resolve(fresh ?: document.path ?: error("Anlage nicht gefunden"))
    }

    // Letzter Stand je Gemeinde (`filesDir/politics/<slug>/…`), damit Start sofort etwas zeigt.
    private val sessionList = ListSerializer(CouncilSession.serializer())
    private val paperList = ListSerializer(CouncilPaper.serializer())
    private fun folder() = "politics/${Tenants.slug}"
    fun cachedSessions(): List<CouncilSession>? = Store.read(folder(), "sessions.json")?.let { runCatching { Http.json.decodeFromString(sessionList, it) }.getOrNull() }
    fun saveSessions(list: List<CouncilSession>) = Store.write(folder(), "sessions.json", Http.json.encodeToString(sessionList, list))
    fun cachedPapers(): List<CouncilPaper>? = Store.read(folder(), "papers.json")?.let { runCatching { Http.json.decodeFromString(paperList, it) }.getOrNull() }
    fun savePapers(list: List<CouncilPaper>) = Store.write(folder(), "papers.json", Http.json.encodeToString(paperList, list))
    /** Höchstens alle 30 Minuten neu laden (Start). */
    fun isFresh(name: String) = Store.file(folder(), name).let { it.exists() && System.currentTimeMillis() - it.lastModified() < 30 * 60_000 }

    /** Laufender und die zwei folgenden Monate. */
    suspend fun upcomingSessions(): List<CouncilSession> {
        val today = Town.today()
        val list = (0L..2L).flatMap { offset -> today.plusMonths(offset).let { sessions(it.year, it.monthValue) } }
            .distinctBy { it.id }.sortedBy { it.start }
        saveSessions(list)
        return list
    }

    private fun resolve(path: String) = if (path.startsWith("http")) path else base + path.removePrefix("/bi/").removePrefix("/")

    private fun HttpRequestBuilder.ua() = header("User-Agent", UA)

    private suspend fun get(path: String): String = decode(http().get(base + path) { ua() })
    private suspend fun post(path: String, fields: List<Pair<String, String>>): String = decode(http().post(base + path) { ua(); form(fields) })

    private suspend fun decode(response: HttpResponse): String {
        if (response.status.value !in 200..299) error("HTTP ${response.status.value}")
        return String(response.bodyAsBytes(), Charsets.ISO_8859_1)
    }

    /** ALLRIS erwartet Formularwerte in ISO-8859-1. */
    private fun HttpRequestBuilder.form(fields: List<Pair<String, String>>) {
        val body = fields.joinToString("&") { (k, v) -> java.net.URLEncoder.encode(k, "ISO-8859-1") + "=" + java.net.URLEncoder.encode(v, "ISO-8859-1") }
        setBody(TextContent(body, ContentType.Application.FormUrlEncoded))
    }
}
