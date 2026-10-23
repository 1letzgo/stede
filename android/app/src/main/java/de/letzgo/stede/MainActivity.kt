package de.letzgo.stede

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import de.letzgo.stede.data.Audience
import de.letzgo.stede.data.Backend
import de.letzgo.stede.data.Brand
import de.letzgo.stede.data.CouncilSession
import de.letzgo.stede.data.Feature
import de.letzgo.stede.data.Features
import de.letzgo.stede.data.Tides
import de.letzgo.stede.data.Places
import de.letzgo.stede.data.ContentFiles
import de.letzgo.stede.data.Tenants
import de.letzgo.stede.ui.*
import io.github.jan.supabase.auth.handleDeeplinks

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        Backend.supabase.handleDeeplinks(intent)
        setContent { StedeTheme { StedeApp() } }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Backend.supabase.handleDeeplinks(intent)
    }
}

enum class AppTab(val title: String, val icon: ImageVector) {
    Start("Start", Icons.Default.Home), Calendar("Kalender", Icons.Default.CalendarMonth), Community("Gruppen", Icons.Default.Groups),
    Settings("Einstellungen", Icons.Default.Settings);

    /** Gruppen nur mit dem Baustein `groups`. Plus hat keinen Tab, sondern steht in den Einstellungen. */
    val isAvailable get() = when (this) { Community -> Features.has(Feature.Groups); else -> true }
}

/** Ziele, die auf einen Tab geschoben werden (wie HomeDestination in iOS). */
sealed class Screen {
    data object Weather : Screen()
    data object Tides : Screen()
    data object Ferry : Screen()
    data object Train : Screen()
    data object Bus : Screen()
    data object Waste : Screen()
    data class Category(val name: String) : Screen()
    /** `tasks`: gleich im Reiter „Aufgaben“ öffnen (aus „Meine Aufgaben“). */
    data class CommunityDetail(val id: String, val tasks: Boolean = false) : Screen()
    data object MyTasks : Screen()
    data object CouncilSessions : Screen()
    data object CouncilPapers : Screen()
    data class CouncilSessionDetail(val session: CouncilSession) : Screen()
    data class CouncilPaperDetail(val id: Int, val number: String) : Screen()

}

@Composable
fun StedeApp() {
    var tab by rememberSaveable { mutableStateOf(AppTab.Start) }
    val scope = rememberCoroutineScope()
    val context = androidx.compose.ui.platform.LocalContext.current
    LaunchedEffect(Unit) {
        Session.start(scope)
        Tenants.refresh()
        // Vor der ersten Gemeindewahl gibt es nichts nachzuladen.
        if (!Tenants.hasChosen) return@LaunchedEffect
        PlusStore.start(context)
        runCatching { Places.sync() }
        runCatching { ContentFiles.sync() }
        if (Features.has(Feature.Tides)) runCatching { Tides.events() }
    }
    // Gemeindewechsel: Mandant und Rollen neu laden.
    val slug = Tenants.slug
    var sessionSlug by remember { mutableStateOf(slug) }
    LaunchedEffect(slug) { if (slug != sessionSlug) { sessionSlug = slug; Session.tenantChanged() } }

    // Beim ersten Start fragt die App nach der Gemeinde.
    if (!Tenants.hasChosen) { TenantOnboardingScreen(); return }
    // Danach: Tourist oder Einwohner — bestimmt, welche Bausteine sichtbar sind.
    val audience = Audience.current ?: run { AudienceOnboardingScreen(); return }
    // Neue Gemeinde oder andere Ansicht → alle Screens und ihr Zustand frisch.
    key(slug, audience) { StedeTabs(if (AppTab.Community == tab && !tab.isAvailable) AppTab.Settings else tab) { tab = it } }
    AppUpdateCheck()
}

@Composable
private fun StedeTabs(tab: AppTab, setTab: (AppTab) -> Unit) {
    val stacks = remember { AppTab.entries.associateWith { mutableStateListOf<Screen>() } }
    val stack: SnapshotStateList<Screen> = stacks.getValue(tab)
    BackHandler(enabled = stack.isNotEmpty()) { stack.removeAt(stack.lastIndex) }
    val open: (Screen) -> Unit = { stack.add(it) }
    val back: () -> Unit = { if (stack.isNotEmpty()) stack.removeAt(stack.lastIndex) }
    // Schloss in Tagesleiste oder Kalender: zu den Einstellungen, dort steht „<App>+“ ganz oben.
    LaunchedEffect(AppNav.plusRequested) {
        if (AppNav.plusRequested > 0 && Features.has(Feature.Plus)) {
            stacks.getValue(AppTab.Settings).clear()
            setTab(AppTab.Settings)
        }
    }

    Scaffold(
        contentWindowInsets = WindowInsets(0),
        bottomBar = {
            NavigationBar(containerColor = C.surface) {
                AppTab.entries.filter { it.isAvailable }.forEach { t ->
                    NavigationBarItem(selected = tab == t, onClick = { if (tab == t) stacks.getValue(t).clear() else setTab(t) },
                        icon = { Icon(t.icon, null) }, label = { Text(t.title) },
                        colors = NavigationBarItemDefaults.colors(selectedIconColor = C.ink, selectedTextColor = C.ink, indicatorColor = C.teal.copy(alpha = 0.18f)))
                }
            }
        },
    ) { pad ->
        Box(Modifier.padding(pad).consumeWindowInsets(pad)) {
            when (val top = stack.lastOrNull()) {
                null -> when (tab) {
                    AppTab.Start -> StartScreen(open)
                    AppTab.Calendar -> CalendarScreen()
                    AppTab.Community -> CommunityScreen(open)
                    AppTab.Settings -> SettingsScreen()
                }
                Screen.Weather -> WeatherScreen(back)
                Screen.Tides -> TideScreen(back)
                Screen.Ferry -> FerryScreen(back)
                Screen.Train -> TrainScreen(back)
                Screen.Bus -> BusScreen(back)
                Screen.Waste -> WasteScreen(back) { stack.clear(); setTab(AppTab.Settings) }
                is Screen.Category -> CategoryScreen(top.name, back)
                Screen.MyTasks -> MyTasksScreen(open, back)
                Screen.CouncilSessions -> CouncilSessionsScreen(open, back)
                Screen.CouncilPapers -> CouncilPapersScreen(open, back)
                is Screen.CouncilSessionDetail -> CouncilSessionScreen(top.session, open, back)
                is Screen.CouncilPaperDetail -> CouncilPaperScreen(top.id, top.number, back)
                is Screen.CommunityDetail -> CommunityDetailScreen(top.id, back, if (top.tasks) CommunityTab.Tasks else CommunityTab.Events)
            }
        }
    }
}
