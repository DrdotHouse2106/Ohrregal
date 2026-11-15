package de.drdothouse.ohrregal.tv

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.tv.material3.*

/** Seiten über den Tabs; „Zurück“ auf der Fernbedienung geht eine Seite zurück. */
sealed interface Seite {
    data class AlbumS(val album: Album) : Seite
    data class KuenstlerS(val kuenstler: Kuenstler) : Seite
    data class PlaylistS(val playlist: Playlist) : Seite
    data class PodcastS(val podcast: Eintrag) : Seite
    data object Player : Seite
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Wiedergabe.verbinden(applicationContext)
        Empfaenger.starten(applicationContext)
        Aktualisierung.pruefen(applicationContext)
        setContent {
            MaterialTheme(colorScheme = Thema) {
                Surface(Modifier.fillMaxSize(), colors = SurfaceDefaults.colors(containerColor = Farben.hintergrund)) { App() }
            }
        }
    }
}

@Composable
fun App() {
    val ctx = LocalContext.current
    var zugang by remember { mutableStateOf(Zugang.laden(ctx)) }
    // Zugänge vom iPhone („Fernseher einrichten“) direkt übernehmen.
    LaunchedEffect(Empfaenger.neuerZugang) {
        Empfaenger.neuerZugang?.let { neu -> neu.speichern(ctx); zugang = neu; Empfaenger.neuerZugang = null }
    }
    Empfaenger.anfrage?.let { a -> EinrichtenFrage(a); return }
    if (!zugang.vollstaendig) {
        AnmeldungSeite(zugang) { neu -> neu.speichern(ctx); zugang = neu }
        return
    }
    val navidrome = remember(zugang) { Navidrome(zugang.server, zugang.benutzer, zugang.passwort).also { Wiedergabe.navidrome = it } }
    val abs = remember(zugang) {
        (if (zugang.mitHoerbuechern) Audiobookshelf(zugang.absServer, zugang.absBenutzer, zugang.absPasswort) else null).also { Wiedergabe.abs = it }
    }
    val stapel = remember { mutableStateListOf<Seite>() }
    val oeffne: (Seite) -> Unit = { stapel.add(it) }
    BackHandler(stapel.isNotEmpty()) { stapel.removeAt(stapel.lastIndex) }
    // Startet das iPhone etwas auf dem Fernseher, gleich den Player zeigen.
    LaunchedEffect(Empfaenger.vomIphone) { if (Empfaenger.vomIphone > 0 && stapel.lastOrNull() != Seite.Player) stapel.add(Seite.Player) }

    when (val s = stapel.lastOrNull()) {
        null -> Haupt(navidrome, abs, oeffne) { zugang = it; it.speichern(ctx) }
        is Seite.AlbumS -> TitelSeite(s.album.name, s.album.kuenstler, navidrome.cover(s.album.cover, 600), oeffne) { navidrome.albumTitel(s.album.id) }
        is Seite.PlaylistS -> TitelSeite(s.playlist.name, "${s.playlist.anzahl} Titel", navidrome.cover(s.playlist.cover, 600), oeffne) { navidrome.playlist(s.playlist.id) }
        is Seite.KuenstlerS -> KuenstlerSeite(s.kuenstler, navidrome, oeffne)
        is Seite.PodcastS -> PodcastSeite(s.podcast, abs, oeffne)
        Seite.Player -> PlayerSeite()
    }
}

@Composable
fun Haupt(navidrome: Navidrome, abs: Audiobookshelf?, oeffne: (Seite) -> Unit, zugangGeaendert: (Zugang) -> Unit) {
    val tabs = listOfNotNull("Start", "Musik", if (abs != null) "Hörbücher" else null, if (abs != null) "Podcasts" else null, "Radio", "Einstellungen")
    var tab by rememberSaveable { mutableIntStateOf(0) }
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(start = 40.dp, end = 40.dp, top = 24.dp, bottom = 8.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
            TabRow(selectedTabIndex = tab, modifier = Modifier.weight(1f)) {
                tabs.forEachIndexed { i, name ->
                    Tab(selected = tab == i, onFocus = { tab = i }) {
                        Text(name, modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
                    }
                }
            }
            Aktualisierung.Hinweis()
            Wiedergabe.anzeige?.let { a ->
                Button(onClick = { oeffne(Seite.Player) }) { Text((if (Wiedergabe.spielt) "▶ " else "❚❚ ") + a.titel, maxLines = 1) }
            }
        }
        when (tabs[tab]) {
            "Start" -> StartTab(navidrome, abs, oeffne)
            "Musik" -> MusikTab(navidrome, oeffne)
            "Hörbücher" -> HoerbuecherTab(abs!!, oeffne)
            "Podcasts" -> PodcastsTab(abs!!, oeffne)
            "Radio" -> RadioTab(navidrome, oeffne)
            else -> EinstellungenTab(zugangGeaendert)
        }
    }
}
