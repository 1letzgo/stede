package de.letzgo.stede.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Luggage
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.letzgo.stede.data.*

/** Erster Start: „Zu Besuch“ oder „Ich wohne hier“ — wie AudiencePickerView in iOS. */
@Composable
fun AudienceOnboardingScreen() {
    // Nach einem Update kennt der Cache neue Bausteine (etwa Gruppen) noch nicht — erst frisch laden.
    var configVersion by remember { mutableStateOf(0) }
    LaunchedEffect(Unit) { Tenants.refresh(); configVersion++ }
    Scaffold(containerColor = C.sand) { pad ->
        Column(Modifier.padding(pad).verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(Spacing)) {
            Text("Willkommen bei ${Brand.current.displayName}", fontSize = 32.sp, fontWeight = FontWeight.Bold, color = C.text, modifier = Modifier.padding(top = 32.dp))
            Text("Bist du in ${Tenants.config.municipality} zu Besuch oder wohnst du hier? Danach richtet sich, was die App zeigt. Du kannst es später in den Einstellungen ändern.",
                color = C.secondary, modifier = Modifier.padding(bottom = 8.dp))
            key(configVersion) { AudienceOptions(onboarding = true) }
        }
    }
}

/** Die beiden Karten — im Onboarding und unter Einstellungen → Ansicht. */
@Composable
fun AudienceOptions(onboarding: Boolean = false) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing)) {
        Audience.entries.forEach { a ->
            val selected = !onboarding && Audience.current == a
            StedeCard(highlighted = selected, onClick = { Audience.select(a) }) {
                Row(verticalAlignment = if (onboarding) Alignment.Top else Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    IconChip(if (a == Audience.Tourist) Icons.Default.Luggage else Icons.Default.Home, if (a == Audience.Tourist) C.teal else C.green)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(a.title, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = C.text)
                        // Erklärung nur im Wizard; in den Einstellungen genügt der Titel.
                        if (onboarding) Text(detail(a), fontSize = 14.sp, color = C.secondary)
                    }
                    if (selected) Icon(Icons.Default.Check, null, tint = C.ink)
                }
            }
        }
    }
}

/** Beschreibt nur, was es in dieser Gemeinde wirklich gibt. */
private fun detail(a: Audience): String = when (a) {
    Audience.Tourist -> "Termine, Ausflüge, Gastro, Wetter und alles für unterwegs."
    Audience.Resident -> {
        val allowed = (Tenants.config.features ?: Brand.current.defaultFeatures).intersect(Brand.current.allowedFeatures).enabled
        val extras = listOf(Feature.Waste to "Abfuhr", Feature.Politics to "Politik", Feature.Groups to "Gruppen").filter { it.first in allowed }.map { it.second }
        when (extras.size) {
            0 -> "Alles für den Alltag vor Ort."
            1 -> "Alles für Gäste und zusätzlich ${extras[0]}."
            else -> "Alles für Gäste und zusätzlich ${extras.dropLast(1).joinToString(", ")} und ${extras.last()}."
        }
    }
}
