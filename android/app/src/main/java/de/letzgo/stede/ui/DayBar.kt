package de.letzgo.stede.ui

import android.app.DatePickerDialog
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import de.letzgo.stede.data.Town
import java.time.LocalDate

/** Schwebende Tages-/Wochenkapsel über der Tab-Leiste — wie DayNavigator in iOS. */
@Composable
fun DayBar(day: LocalDate, week: Boolean = false, latest: LocalDate? = null, modifier: Modifier = Modifier, onChange: (LocalDate) -> Unit) {
    val context = LocalContext.current
    val step = if (week) 7L else 1L
    val canForward = latest == null || day.plusDays(step) <= latest.plusDays(if (week) 6 else 0)
    val label = if (week) {
        val start = Town.weekStart(day); val today = Town.today()
        if (!today.isBefore(start) && today.isBefore(start.plusDays(7))) "Diese Woche" else "${start.dayOfMonth}.–${start.plusDays(6).format(Town.fmt("d. MMM"))}"
    } else if (day == Town.today()) "Heute" else day.format(Town.fmt("d. MMM yyyy"))
    Row(modifier.shadow(6.dp, RoundedCornerShape(50)).background(C.surface, RoundedCornerShape(50)).border(1.dp, C.tertiary.copy(alpha = 0.2f), RoundedCornerShape(50)).padding(horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = { onChange(day.minusDays(step)) }) { Icon(Icons.Default.ChevronLeft, if (week) "Vorherige Woche" else "Vorheriger Tag", tint = C.ink) }
        Row(Modifier.clickable {
            DatePickerDialog(context, { _, y, m, d -> onChange(LocalDate.of(y, m + 1, d)) }, day.year, day.monthValue - 1, day.dayOfMonth).show()
        }.padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(Icons.Default.CalendarMonth, null, tint = C.ink, modifier = Modifier.size(18.dp))
            Text(label, fontWeight = FontWeight.SemiBold, fontSize = 16.sp, color = C.ink)
        }
        IconButton(onClick = { if (canForward) onChange(day.plusDays(step)) }, enabled = canForward) { Icon(Icons.Default.ChevronRight, if (week) "Nächste Woche" else "Nächster Tag", tint = C.ink.copy(alpha = if (canForward) 1f else 0.35f)) }
    }
}
