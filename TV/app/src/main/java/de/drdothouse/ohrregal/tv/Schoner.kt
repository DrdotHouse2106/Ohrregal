package de.drdothouse.ohrregal.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import kotlinx.coroutines.delay
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Eigener Bildschirmschoner: Während der Wiedergabe bleibt der Bildschirm an (sonst schläft der Fire TV nach
 * 20 Minuten ein). Nach 3 Minuten ohne Taste wird es dunkel, nur Uhr, Titel und Cover wandern langsam
 * (gegen Einbrennen). Jede Taste beendet ihn.
 */
object Schoner {
    var letzteTaste by mutableStateOf(System.currentTimeMillis())
    var aktiv by mutableStateOf(false)
    const val NACH_MS = 3 * 60_000L

    fun taste() { letzteTaste = System.currentTimeMillis(); aktiv = false }
}

@Composable
fun SchonerUeberwachung() {
    LaunchedEffect(Unit) {
        while (true) {
            delay(5000)
            if (!Schoner.aktiv && Wiedergabe.spielt && System.currentTimeMillis() - Schoner.letzteTaste > Schoner.NACH_MS) Schoner.aktiv = true
        }
    }
}

@Composable
fun BildschirmSchoner() {
    var jetzt by remember { mutableLongStateOf(System.currentTimeMillis()) }
    var ecke by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) {
        var n = 0
        while (true) { delay(1000); jetzt = System.currentTimeMillis(); if (++n % 30 == 0) ecke = (ecke + 1) % 4 }
    }
    val ausrichtung = listOf(Alignment.TopStart, Alignment.TopEnd, Alignment.BottomEnd, Alignment.BottomStart)[ecke]
    val a = Wiedergabe.anzeige
    Box(Modifier.fillMaxSize().background(Color.Black).padding(48.dp), contentAlignment = ausrichtung) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            a?.cover?.let { Bild(it, 96.dp) }
            Spacer(Modifier.width(20.dp))
            Column {
                Text(SimpleDateFormat("HH:mm", Locale.GERMAN).format(Date(jetzt)), style = MaterialTheme.typography.displayMedium, color = Color(0xFF9AA3B5))
                a?.let {
                    Text(it.titel, style = MaterialTheme.typography.titleMedium, color = Color(0xFF7D8596), maxLines = 1)
                    Text(it.untertitel, style = MaterialTheme.typography.bodyMedium, color = Color(0xFF5E6575), maxLines = 1)
                }
            }
        }
    }
}
