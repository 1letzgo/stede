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
import de.letzgo.stede.data.Backend
import de.letzgo.stede.data.Places
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

enum class AppTab(val title: String, val icon: ImageVector) { Start("Start", Icons.Default.Home), Calendar("Kalender", Icons.Default.CalendarMonth), Community("Gruppen", Icons.Default.Groups), Settings("Einstellungen", Icons.Default.Settings) }

/** Ziele, die auf einen Tab geschoben werden (wie HomeDestination in iOS). */
sealed class Screen {
    data object Weather : Screen()
    data object Train : Screen()
    data object Bus : Screen()
    data object Waste : Screen()
    data class Category(val name: String) : Screen()
    data class CommunityDetail(val id: String) : Screen()
}

@Composable
fun StedeApp() {
    var tab by rememberSaveable { mutableStateOf(AppTab.Start) }
    val stacks = remember { AppTab.entries.associateWith { mutableStateListOf<Screen>() } }
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) {
        Session.start(scope)
        runCatching { Places.sync() }
    }
    val stack: SnapshotStateList<Screen> = stacks.getValue(tab)
    BackHandler(enabled = stack.isNotEmpty()) { stack.removeAt(stack.lastIndex) }
    val open: (Screen) -> Unit = { stack.add(it) }
    val back: () -> Unit = { if (stack.isNotEmpty()) stack.removeAt(stack.lastIndex) }

    Scaffold(
        contentWindowInsets = WindowInsets(0),
        bottomBar = {
            NavigationBar(containerColor = C.surface) {
                AppTab.entries.forEach { t ->
                    NavigationBarItem(selected = tab == t, onClick = { if (tab == t) stacks.getValue(t).clear() else tab = t },
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
                Screen.Train -> TrainScreen(back)
                Screen.Bus -> BusScreen(back)
                Screen.Waste -> WasteScreen(back)
                is Screen.Category -> CategoryScreen(top.name, back)
                is Screen.CommunityDetail -> CommunityDetailScreen(top.id, back)
            }
        }
    }
}
