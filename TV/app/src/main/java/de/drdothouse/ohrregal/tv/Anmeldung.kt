package de.drdothouse.ohrregal.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.focus.focusRequester
import androidx.tv.material3.*
import kotlinx.coroutines.launch

@Composable
fun AnmeldungSeite(alt: Zugang, fertig: (Zugang) -> Unit) {
    var z by remember { mutableStateOf(alt) }
    var meldung by remember { mutableStateOf<String?>(null) }
    var laeuft by remember { mutableStateOf(false) }
    // Eingabefelder erst auf Wunsch: Sonst springt der Fokus hinein und die Bildschirmtastatur verdeckt alles.
    var tippen by remember { mutableStateOf(false) }
    val bereich = rememberCoroutineScope()
    Row(Modifier.fillMaxSize().padding(horizontal = 64.dp, vertical = 40.dp), horizontalArrangement = Arrangement.spacedBy(48.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text("Ohrregal einrichten", style = MaterialTheme.typography.displaySmall, color = Color.White)
            Text("Am einfachsten vom iPhone aus:", color = Color.White, style = MaterialTheme.typography.headlineSmall)
            Text("1. iPhone im selben WLAN wie der Fernseher", color = Color.White, style = MaterialTheme.typography.titleLarge)
            Text("2. Ohrregal auf dem iPhone: Start → Profilsymbol → „Fernseher einrichten“", color = Color.White, style = MaterialTheme.typography.titleLarge)
            Text("3. Hier „Übernehmen“ drücken", color = Color.White, style = MaterialTheme.typography.titleLarge)
            Text("Findet das iPhone den Fernseher nicht, dort diese Adresse eingeben:", color = Color.White, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 16.dp))
            Text(Empfaenger.adresse, color = Farben.blau, style = MaterialTheme.typography.displayMedium)
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (!tippen) {
                Text("Ohne iPhone:", color = Color.White, style = MaterialTheme.typography.headlineSmall)
                Button(onClick = { tippen = true }) { Text("Mit der Fernbedienung eintragen") }
            } else {
                Feld("Navidrome-Adresse", z.server) { z = z.copy(server = it) }
                Feld("Benutzer", z.benutzer) { z = z.copy(benutzer = it) }
                Feld("Passwort", z.passwort, geheim = true) { z = z.copy(passwort = it) }
                Text("Audiobookshelf (optional)", color = Color.White, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 12.dp))
                Feld("Audiobookshelf-Adresse", z.absServer) { z = z.copy(absServer = it) }
                Feld("Benutzer", z.absBenutzer) { z = z.copy(absBenutzer = it) }
                Feld("Passwort", z.absPasswort, geheim = true) { z = z.copy(absPasswort = it) }
                Button(enabled = !laeuft, onClick = {
                    laeuft = true; meldung = null
                    bereich.launch {
                        try {
                            val neu = z.copy(server = Zugang.adresse(z.server), benutzer = z.benutzer.trim(), absServer = Zugang.adresse(z.absServer), absBenutzer = z.absBenutzer.trim())
                            Navidrome(neu.server, neu.benutzer, neu.passwort).ping()
                            if (neu.mitHoerbuechern) Audiobookshelf(neu.absServer, neu.absBenutzer, neu.absPasswort).anmelden()
                            fertig(neu)
                        } catch (e: Exception) {
                            meldung = e.message ?: "Verbindung fehlgeschlagen."
                        } finally { laeuft = false }
                    }
                }) { Text(if (laeuft) "Verbinde …" else "Verbinden und speichern") }
            }
            meldung?.let { Text(it, color = Farben.violett, style = MaterialTheme.typography.titleMedium) }
        }
    }
}

@Composable
private fun Feld(name: String, wert: String, geheim: Boolean = false, aenderung: (String) -> Unit) {
    Column {
        Text(name, color = Color.White, style = MaterialTheme.typography.bodyMedium)
        BasicTextField(value = wert, onValueChange = aenderung, singleLine = true,
            textStyle = TextStyle(color = Color.White, fontSize = 22.sp), cursorBrush = SolidColor(Farben.blau),
            visualTransformation = if (geheim) PasswordVisualTransformation() else VisualTransformation.None,
            keyboardOptions = KeyboardOptions(keyboardType = if (geheim) KeyboardType.Password else KeyboardType.Uri),
            modifier = Modifier.fillMaxWidth().background(Farben.flaeche, RoundedCornerShape(8.dp))
                .border(1.dp, Farben.gedaempft.copy(alpha = 0.4f), RoundedCornerShape(8.dp)).padding(12.dp))
    }
}

/** Abfrage auf dem Fernseher, wenn das iPhone die Zugänge schickt; „Übernehmen“ hat den Fokus. */
@Composable
fun EinrichtenFrage(a: Empfaenger.Anfrage) {
    val fokus = remember { androidx.compose.ui.focus.FocusRequester() }
    LaunchedEffect(a) { runCatching { fokus.requestFocus() } }
    Column(Modifier.fillMaxSize().padding(horizontal = 160.dp, vertical = 80.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text("Ohrregal einrichten?", style = MaterialTheme.typography.displaySmall, color = Color.White)
        Text("„${a.geraet}“ möchte Ohrregal auf diesem Fernseher einrichten:", color = Color.White, style = MaterialTheme.typography.titleMedium)
        Text("Navidrome: ${a.zugang.server} (${a.zugang.benutzer})", color = Farben.gedaempft)
        if (a.zugang.mitHoerbuechern) Text("Audiobookshelf: ${a.zugang.absServer} (${a.zugang.absBenutzer})", color = Farben.gedaempft)
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp), modifier = Modifier.padding(top = 16.dp)) {
            Button(onClick = { a.antwort.complete(true) }, modifier = Modifier.focusRequester(fokus)) { Text("Übernehmen") }
            Button(onClick = { a.antwort.complete(false) }) { Text("Ablehnen") }
        }
    }
}
