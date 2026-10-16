package de.letzgo.stede.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import de.letzgo.stede.data.AppUpdate
import de.letzgo.stede.data.Brand

/** Hinweis auf eine neuere APK von GitHub; „Herunterladen“ lädt sie im Browser, Android installiert nach Rückfrage. */
@Composable
fun AppUpdateDialog(release: AppUpdate.Release, onDismiss: () -> Unit) {
    val openUrl = rememberOpenUrl()
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Neue Version von ${Brand.current.displayName}") },
        text = {
            Column(Modifier.heightIn(max = 320.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(release.name, color = C.text)
                if (release.notes.isNotEmpty()) Text(release.notes, color = C.secondary)
                Text("Nach dem Herunterladen die Datei öffnen und „Installieren“ tippen.", color = C.secondary)
            }
        },
        confirmButton = { TextButton({ openUrl(release.apkUrl); onDismiss() }) { Text("Herunterladen") } },
        dismissButton = { TextButton({ AppUpdate.skip(release); onDismiss() }) { Text("Später") } },
    )
}

/** Prüft beim Start (höchstens alle sechs Stunden) und zeigt den Hinweis. */
@Composable
fun AppUpdateCheck() {
    val context = LocalContext.current
    var release by remember { mutableStateOf<AppUpdate.Release?>(null) }
    LaunchedEffect(Unit) { release = AppUpdate.checkOnLaunch(context) }
    release?.let { AppUpdateDialog(it) { release = null } }
}
