package de.letzgo.stede.ui

import android.content.Intent
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage

val CardShape = RoundedCornerShape(20.dp)
val ChipShape = RoundedCornerShape(12.dp)
val ChipHeight = 36.dp
val Spacing = 12.dp
val CardPadding = 16.dp

/** Weiße Karte wie `.stedeCard`; hervorgehoben in blassem Türkis. */
@Composable
fun StedeCard(modifier: Modifier = Modifier, highlighted: Boolean = false, padding: Dp = CardPadding, onClick: (() -> Unit)? = null,
              /** Kopf über die volle Breite, ohne Innenabstand — etwa ein Foto. */
              header: (@Composable () -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    if (header == null) Column(modifier.cardSurface(highlighted, onClick).padding(padding), content = content)
    else Column(modifier.cardSurface(highlighted, onClick)) { header(); Column(Modifier.padding(padding), content = content) }
}

/** Kartenfläche wie `.stedeCard`: weiß mit feiner Kontur, hervorgehoben blass türkis ohne Kontur. */
@Composable
fun Modifier.cardSurface(highlighted: Boolean = false, onClick: (() -> Unit)? = null): Modifier {
    var m = fillMaxWidth().clip(CardShape).background(if (highlighted) C.teal.copy(alpha = 0.16f) else C.surface)
    if (!highlighted) m = m.border(1.dp, C.text.copy(alpha = 0.06f), CardShape)
    if (onClick != null) m = m.clickable { onClick() }
    return m
}

/** Einzeilige Listenkarte (Mitglied, Zusage, Anfrage) — wie `.stedeRowCard()`. */
@Composable
fun RowCard(modifier: Modifier = Modifier, content: @Composable RowScope.() -> Unit) {
    Row(modifier.cardSurface().padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp), content = content)
}

/** Eingabefeld in Karten: sandfarbene Kapsel statt Material-Rahmen (StedeTextField). */
@Composable
fun StedeTextField(value: String, onChange: (String) -> Unit, placeholder: String, modifier: Modifier = Modifier) {
    androidx.compose.foundation.text.BasicTextField(value, onChange, singleLine = true,
        textStyle = androidx.compose.ui.text.TextStyle(color = C.text, fontSize = 16.sp),
        cursorBrush = androidx.compose.ui.graphics.SolidColor(C.teal),
        modifier = modifier.heightIn(min = ChipHeight).background(C.sand, RoundedCornerShape(50)).padding(horizontal = 14.dp),
        decorationBox = { inner -> Box(Modifier.heightIn(min = ChipHeight), contentAlignment = Alignment.CenterStart) { if (value.isEmpty()) Text(placeholder, color = C.tertiary); inner() } })
}

@Composable
fun Pill(text: String, color: Color) {
    Text(text, color = color, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis,
        modifier = Modifier.background(color.copy(alpha = 0.14f), RoundedCornerShape(50)).padding(horizontal = 8.dp, vertical = 4.dp))
}

@Composable
fun IconChip(icon: ImageVector, color: Color, size: Dp = 38.dp) {
    Box(Modifier.size(size).background(color.copy(alpha = 0.16f), ChipShape), contentAlignment = Alignment.Center) {
        Icon(icon, null, tint = color, modifier = Modifier.size(size * 0.55f))
    }
}

/** Farbige Kapsel zum Antippen — gefüllt wenn gewählt, sonst blass (StedeColorChip). */
@Composable
fun ColorChip(title: String?, color: Color, modifier: Modifier = Modifier, icon: ImageVector? = null, selected: Boolean = false, prominent: Boolean = false, enabled: Boolean = true, onClick: () -> Unit) {
    val filled = selected || prominent
    Row(modifier.heightIn(min = ChipHeight).clip(RoundedCornerShape(50)).background(if (filled) color else color.copy(alpha = 0.16f))
        .clickable(enabled = enabled) { onClick() }.padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally)) {
        icon?.let { Icon(it, title, tint = if (filled) Color.White else color, modifier = Modifier.size(18.dp)) }
        title?.let { Text(it, color = if (filled) Color.White else color, fontWeight = FontWeight.SemiBold, fontSize = 15.sp, maxLines = 1) }
    }
}

/** Auswahl-Chip einer Umschalterzeile: dunkel gefüllt wenn gewählt, sonst weiß. */
@Composable
fun SelectionChip(title: String, selected: Boolean, modifier: Modifier = Modifier, icon: ImageVector? = null, compact: Boolean = false, onClick: () -> Unit) {
    Row(modifier.heightIn(min = ChipHeight).clip(RoundedCornerShape(50)).background(if (selected) C.deep else C.surface).clickable { onClick() }.padding(horizontal = if (compact) 4.dp else 14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally)) {
        icon?.let { Icon(it, null, tint = if (selected) Color.White else C.ink, modifier = Modifier.size(18.dp)) }
        if (title.isNotEmpty()) Text(title, color = if (selected) Color.White else C.ink, fontWeight = FontWeight.SemiBold, fontSize = if (compact) 13.sp else 15.sp, maxLines = 1, softWrap = false, textAlign = TextAlign.Center)
    }
}

/** Gleich breite Umschalterzeile (Bahn-Richtung, Kalender-Filter, Community-Reiter). */
@Composable
fun <T> Switcher(options: List<T>, selected: T, title: (T) -> String, onSelect: (T) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(if (options.size > 3) 6.dp else 8.dp)) {
        options.forEach { o -> SelectionChip(title(o), o == selected, Modifier.weight(1f), compact = options.size > 2) { onSelect(o) } }
    }
}

@Composable
fun SectionHeader(title: String, icon: ImageVector? = null) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.padding(top = 4.dp)) {
        icon?.let { Icon(it, null, tint = C.secondary, modifier = Modifier.size(20.dp)) }
        Text(title, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = C.text)
    }
}

@Composable
fun SourceFooter(text: String) {
    Text(text, fontSize = 11.sp, color = C.secondary, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp))
}

@Composable
fun InfoCard(text: String) { StedeCard { Text(text, color = C.secondary) } }

@Composable
fun Rounded(text: String, size: Int, weight: FontWeight = FontWeight.SemiBold, color: Color = C.text, modifier: Modifier = Modifier) =
    Text(text, fontSize = size.sp, fontWeight = weight, fontFamily = FontFamily.SansSerif, color = color, modifier = modifier)

/** Logo der Community oder Initialen auf türkiser Kachel. */
@Composable
fun CommunityAvatar(logoUrl: String?, name: String, size: Dp = 38.dp) {
    if (logoUrl != null) AsyncImage(logoUrl, null, Modifier.size(size).clip(ChipShape), contentScale = ContentScale.Crop)
    else Box(Modifier.size(size).background(C.teal.copy(alpha = 0.16f), ChipShape), contentAlignment = Alignment.Center) {
        Text(initials(name), color = C.teal, fontWeight = FontWeight.Bold, fontSize = if (size > 50.dp) 22.sp else 15.sp)
    }
}

/** Profilbild als Kreis, ohne Bild die Initialen in der Rollenfarbe (PersonAvatar). */
@Composable
fun PersonAvatar(url: String?, name: String, color: Color = C.ink, size: Dp = 38.dp) {
    Box(Modifier.size(size).clip(androidx.compose.foundation.shape.CircleShape).background(color.copy(alpha = 0.16f)), contentAlignment = Alignment.Center) {
        Text(initials(name), color = color, fontWeight = FontWeight.Bold, fontSize = if (size > 50.dp) 22.sp else 15.sp)
        if (url != null) AsyncImage(url, null, Modifier.matchParentSize(), contentScale = ContentScale.Crop)
    }
}

fun initials(name: String): String {
    val words = name.split(' ', '-').filter { it.isNotBlank() && it.first().isLetterOrDigit() }
    return if (words.size >= 2) words.take(2).joinToString("") { it.first().uppercase() } else name.trim().take(2).uppercase()
}

@Composable
fun EventPhoto(url: String, height: Dp, modifier: Modifier = Modifier, credit: String? = null) {
    Box(modifier.fillMaxWidth().height(height)) {
        AsyncImage(url, null, Modifier.fillMaxSize().background(C.teal.copy(alpha = 0.12f)), contentScale = ContentScale.Crop)
        PhotoCredit(credit, Modifier.align(Alignment.BottomEnd))
    }
}

/** Urheber und Lizenz übernommener Fotos, klein unten rechts im Bild. */
@Composable
fun PhotoCredit(text: String?, modifier: Modifier = Modifier) {
    if (text == null) return
    Text(text, color = Color.White, fontSize = 11.sp, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
        modifier = modifier.padding(6.dp).background(Color.Black.copy(alpha = 0.45f), RoundedCornerShape(50)).padding(horizontal = 6.dp, vertical = 2.dp))
}

/** Beitragsbild in der Detailansicht: volle Breite, Höhe nach Seitenverhältnis — nichts abgeschnitten. */
@Composable
fun FullEventPhoto(url: String, modifier: Modifier = Modifier, credit: String? = null) {
    Box(modifier.fillMaxWidth()) {
        AsyncImage(url, null, Modifier.fillMaxWidth().background(C.teal.copy(alpha = 0.12f)), contentScale = ContentScale.FillWidth)
        PhotoCredit(credit, Modifier.align(Alignment.BottomEnd))
    }
}

/** Kopfleiste im Petrol der Stadt: Titel mittig, weiße Symbole. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StedeTopBar(title: String, onBack: (() -> Unit)? = null, subtitle: String? = null, actions: @Composable RowScope.() -> Unit = {}) {
    CenterAlignedTopAppBar(
        title = {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(title, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                subtitle?.takeIf { it.isNotBlank() }?.let { Text(it, fontSize = 13.sp, color = Color.White.copy(alpha = 0.7f), maxLines = 1, overflow = TextOverflow.Ellipsis) }
            }
        },
        navigationIcon = { if (onBack != null) IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Zurück", tint = Color.White) } },
        actions = actions,
        // Flach wie die iOS-Leiste (44 pt) statt Material-Standard 64 dp.
        expandedHeight = 48.dp,
        colors = TopAppBarDefaults.centerAlignedTopAppBarColors(containerColor = C.bar, titleContentColor = Color.White, actionIconContentColor = Color.White, navigationIconContentColor = Color.White),
    )
}

/** Kopf eines Sheets in der Petrol-Leiste wie die Seiten: links optional eine Aktion, rechts „Fertig“. */
@Composable
fun SheetHeader(title: String, leading: Pair<String, () -> Unit>? = null, trailing: Pair<String, () -> Unit>?) {
    Box(Modifier.fillMaxWidth().background(C.bar).padding(horizontal = 8.dp, vertical = 6.dp)) {
        leading?.let { TextButton(onClick = it.second, modifier = Modifier.align(Alignment.CenterStart)) { Text(it.first, color = Color.White) } }
        Text(title, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, modifier = Modifier.align(Alignment.Center), color = Color.White)
        trailing?.let { TextButton(onClick = it.second, modifier = Modifier.align(Alignment.CenterEnd)) { Text(it.first, color = Color.White, fontWeight = FontWeight.SemiBold) } }
    }
}

@Composable
fun rememberOpenUrl(): (String) -> Unit {
    val context = LocalContext.current
    return { url ->
        runCatching { CustomTabsIntent.Builder().build().launchUrl(context, Uri.parse(url)) }
            .onFailure { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
    }
}

@Composable
fun rememberOpenIntent(): (String) -> Unit {
    val context = LocalContext.current
    return { uri -> runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(uri)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) } }
}

/** Kapsel für Aktionen in Karten: Telefon, Website, Karte (StedeActionChip). */
@Composable
fun ActionChip(title: String, icon: ImageVector, onClick: () -> Unit) {
    Row(Modifier.heightIn(min = 30.dp).clip(RoundedCornerShape(50)).background(C.teal.copy(alpha = 0.16f)).clickable { onClick() }.padding(horizontal = 10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        Icon(icon, null, tint = C.ink, modifier = Modifier.size(15.dp))
        Text(title, color = C.ink, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
fun Loading(text: String = "Lade …") { Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) { Text(text, color = C.secondary) } }

fun Modifier.tileBorder(color: Color) = this.border(1.dp, color.copy(alpha = 0.55f), CardShape)
