package de.letzgo.stede.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Place
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.letzgo.stede.data.Brand
import de.letzgo.stede.data.ContentFiles
import de.letzgo.stede.data.Places
import de.letzgo.stede.data.Tenants
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

/**
 * Gemeindewechsel wie TenantSwitch in iOS: erst die Inhalte der neuen Gemeinde laden, dann umschalten —
 * so zeigt die App nach dem Wechsel sofort Orte, Karte, Haltestellen und Straßen.
 */
object TenantSwitch {
    suspend fun activate(slug: String) {
        Tenants.refresh()
        coroutineScope {
            val files = async { ContentFiles.sync(slug) }
            val places = async { Places.sync(slug) }
            files.await(); places.await()
        }
        Tenants.select(slug)
    }
}

/** Liste der Ammerland-Gemeinden — beim ersten Start bildschirmfüllend, sonst als Sheet aus den Einstellungen. */
@Composable
fun TenantPickerList(onboarding: Boolean, contentPadding: PaddingValues = PaddingValues(16.dp), onDone: () -> Unit = {}) {
    val scope = rememberCoroutineScope()
    var tenants by remember { mutableStateOf(Tenants.all) }
    var loadingSlug by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) { Tenants.refresh(); tenants = Tenants.all }

    fun choose(slug: String) {
        if (loadingSlug != null) return
        if (!onboarding && slug == Tenants.slug) { onDone(); return }
        loadingSlug = slug
        scope.launch {
            TenantSwitch.activate(slug)
            loadingSlug = null
            onDone()
        }
    }

    LazyColumn(contentPadding = contentPadding, verticalArrangement = Arrangement.spacedBy(Spacing)) {
        if (onboarding) item {
            Column(Modifier.padding(top = 32.dp, bottom = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("Willkommen bei stede", fontSize = 32.sp, fontWeight = FontWeight.Bold, color = C.text)
                Text("Wähle deine Gemeinde im ${Brand.current.regionName}. Du kannst sie später in den Einstellungen wechseln.", color = C.secondary)
            }
        }
        items(tenants, key = { it.slug }) { t ->
            RowCard(Modifier.fillMaxWidth().clickable(enabled = loadingSlug == null) { choose(t.slug) }) {
                Icon(Icons.Default.Place, null, tint = C.ink, modifier = Modifier.size(24.dp))
                Column(Modifier.weight(1f)) {
                    Text(t.municipality, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = C.text)
                    Text(t.officialName, color = C.secondary, fontSize = 13.sp)
                }
                when {
                    loadingSlug == t.slug -> CircularProgressIndicator(Modifier.size(20.dp), color = C.ink, strokeWidth = 2.dp)
                    !onboarding && t.slug == Tenants.slug -> Icon(Icons.Default.Check, null, tint = C.ink)
                }
            }
        }
        item {
            Text("Straße, Haltestelle und Bahnhof wählst du nach einem Wechsel neu.", color = C.secondary, fontSize = 13.sp, modifier = Modifier.padding(horizontal = 4.dp))
        }
    }
}

/** Erster Start: bildschirmfüllende Gemeindewahl. */
@Composable
fun TenantOnboardingScreen() {
    Scaffold(containerColor = C.sand) { pad ->
        TenantPickerList(onboarding = true, contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 16.dp + pad.calculateTopPadding(), bottom = 16.dp + pad.calculateBottomPadding()))
    }
}

/** Sheet aus den Einstellungen. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TenantPickerSheet(onDismiss: () -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = C.sand, dragHandle = null) {
        SheetHeader("Gemeinde", leading = "Abbrechen" to onDismiss, trailing = null)
        TenantPickerList(onboarding = false, onDone = onDismiss)
    }
}
