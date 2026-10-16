package de.letzgo.stede.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import de.letzgo.stede.data.AppUpdate
import de.letzgo.stede.data.Brand
import kotlinx.coroutines.launch
import java.io.File

/**
 * Neue Version von GitHub: lädt die APK in der App (mit Fortschritt und Prüfsumme) und übergibt sie
 * dem Paketinstaller. Fehlt die Freigabe „Unbekannte Apps installieren“, führt der Dialog dorthin
 * und installiert, sobald man zurückkommt.
 */
@Composable
fun AppUpdateDialog(release: AppUpdate.Release, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var progress by remember { mutableStateOf<Float?>(null) }
    var downloading by remember { mutableStateOf(false) }
    var file by remember { mutableStateOf<File?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var waitingForPermission by remember { mutableStateOf(false) }

    fun installOrAsk(apk: File) {
        if (AppUpdate.canInstall(context)) { waitingForPermission = false; AppUpdate.install(context, apk) }
        else { waitingForPermission = true; AppUpdate.openInstallPermission(context) }
    }

    // Zurück aus den Einstellungen: mit Freigabe gleich installieren.
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(waitingForPermission) {
        if (!waitingForPermission) return@LaunchedEffect
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            file?.let { if (AppUpdate.canInstall(context)) installOrAsk(it) }
        }
    }

    AlertDialog(
        onDismissRequest = { if (!downloading) onDismiss() },
        properties = DialogProperties(dismissOnClickOutside = !downloading),
        title = { Text("Neue Version von ${Brand.current.displayName}") },
        text = {
            Column(Modifier.heightIn(max = 360.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(release.name, color = C.text)
                if (release.notes.isNotEmpty()) Text(release.notes, color = C.secondary)
                when {
                    error != null -> Text(error!!, color = C.red)
                    downloading -> {
                        Text("Wird geladen …", color = C.secondary)
                        progress?.let { LinearProgressIndicator(progress = { it }, Modifier.fillMaxWidth(), color = C.teal) }
                            ?: LinearProgressIndicator(Modifier.fillMaxWidth(), color = C.teal)
                    }
                    waitingForPermission -> Text("Erlaube ${Brand.current.displayName} in den Android-Einstellungen, Apps zu installieren, und komm dann zurück.", color = C.secondary)
                    file != null -> Text("Geladen. Android fragt gleich, ob die neue Version installiert werden soll.", color = C.secondary)
                }
            }
        },
        confirmButton = {
            val apk = file
            TextButton(enabled = !downloading, onClick = {
                if (apk != null) installOrAsk(apk)
                else scope.launch {
                    downloading = true; error = null; progress = null
                    runCatching { AppUpdate.download(context, release) { progress = it } }
                        .onSuccess { file = it; installOrAsk(it) }
                        .onFailure { error = it.message ?: "Die neue Version konnte nicht geladen werden." }
                    downloading = false
                }
            }) { Text(when { apk != null -> "Installieren"; error != null -> "Erneut versuchen"; else -> "Aktualisieren" }) }
        },
        dismissButton = {
            if (!downloading) TextButton({ if (file == null) AppUpdate.skip(release); onDismiss() }) { Text("Später") }
        },
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
