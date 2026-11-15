package de.drdothouse.ohrregal.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.tv.material3.*
import kotlinx.coroutines.launch
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Lädt einmal und merkt sich Fehler. */
@Composable
fun <T> laden(schluessel: Any?, block: suspend () -> T): Pair<T?, String?> {
    var wert by remember(schluessel) { mutableStateOf<T?>(null) }
    var fehler by remember(schluessel) { mutableStateOf<String?>(null) }
    LaunchedEffect(schluessel) {
        try { wert = block() } catch (e: Exception) { fehler = e.message ?: "Fehler beim Laden" }
    }
    return wert to fehler
}

@Composable
fun StartTab(n: Navidrome, abs: Audiobookshelf?, oeffne: (Seite) -> Unit) {
    val (zuletzt, fehler) = laden(n) { n.alben("recent") }
    val (haeufig, _) = laden(n) { n.alben("frequent") }
    val (neu, _) = laden(n) { n.alben("newest") }
    val (weiter, _) = laden(abs) { abs?.angefangen() ?: emptyList() }
    val (folgen, _) = laden(abs) { runCatching { abs?.neueFolgen(12) }.getOrNull() ?: emptyList() }
    val bereich = rememberCoroutineScope()
    if (fehler != null && zuletzt == null) { Hinweis("Navidrome nicht erreichbar: $fehler"); return }
    LazyColumn(contentPadding = PaddingValues(bottom = 48.dp)) {
        item {
            Button(onClick = { bereich.launch { runCatching { n.zufall() }.onSuccess { Wiedergabe.spiele(it); oeffne(Seite.Player) } } },
                modifier = Modifier.padding(start = 48.dp, top = 8.dp)) { Text("▶  Spiel etwas für mich") }
        }
        item { Reihe("Hörbücher weiterhören", weiter ?: emptyList()) { e -> Karte(abs?.cover(e.id, e.stand), e.titel, e.autor) { Wiedergabe.spiele(e.id); oeffne(Seite.Player) } } }
        item { Reihe("Neue Folgen", folgen ?: emptyList()) { f -> FolgenKarte(f, abs, oeffne) } }
        item { Reihe("Zuletzt gespielt", zuletzt ?: emptyList()) { a -> AlbumKarte(a, n, oeffne) } }
        item { Reihe("Am häufigsten gespielt", haeufig ?: emptyList()) { a -> AlbumKarte(a, n, oeffne) } }
        item { Reihe("Kürzlich hinzugefügt", neu ?: emptyList()) { a -> AlbumKarte(a, n, oeffne) } }
    }
}

@Composable
fun AlbumKarte(a: Album, n: Navidrome, oeffne: (Seite) -> Unit) = Karte(n.cover(a.cover), a.name, a.kuenstler) { oeffne(Seite.AlbumS(a)) }

@Composable
fun FolgenKarte(f: Folge, abs: Audiobookshelf?, oeffne: (Seite) -> Unit) =
    Karte(abs?.cover(f.itemId), f.titel, listOf(f.podcast, datumText(f.datum)).filter { it.isNotEmpty() }.joinToString(" · "), breite = 220.dp) {
        Wiedergabe.spiele(f.itemId, f.id); oeffne(Seite.Player)
    }

fun datumText(ms: Long) = if (ms <= 0) "" else SimpleDateFormat("d. MMM", Locale.GERMAN).format(Date(ms))

@Composable
fun MusikTab(n: Navidrome, oeffne: (Seite) -> Unit) {
    val (playlists, fehler) = laden(n) { n.playlists() }
    val (kuenstler, _) = laden(n) { n.kuenstler() }
    val (alben, _) = laden(n) { n.alben("alphabeticalByName", 100) }
    val (zufall, _) = laden(n) { n.alben("random", 30) }
    if (fehler != null && playlists == null) { Hinweis(fehler); return }
    LazyColumn(contentPadding = PaddingValues(bottom = 48.dp)) {
        item { Reihe("Playlists", playlists ?: emptyList()) { p -> Karte(n.cover(p.cover), p.name, "${p.anzahl} Titel") { oeffne(Seite.PlaylistS(p)) } } }
        item { Reihe("Künstler", kuenstler ?: emptyList()) { k -> Karte(n.cover(k.cover), k.name, "", breite = 150.dp, rund = true) { oeffne(Seite.KuenstlerS(k)) } } }
        item { Reihe("Zufällige Alben", zufall ?: emptyList()) { a -> AlbumKarte(a, n, oeffne) } }
        item { Reihe("Alle Alben", alben ?: emptyList()) { a -> AlbumKarte(a, n, oeffne) } }
    }
}

@Composable
fun HoerbuecherTab(abs: Audiobookshelf, oeffne: (Seite) -> Unit) {
    val (weiter, fehler) = laden(abs) { abs.angefangen() }
    val (bibliotheken, _) = laden(abs) { abs.bibliotheken("book").map { abs.eintraege(it, neueste = true, anzahl = 30) to abs.eintraege(it, anzahl = 200) } }
    if (fehler != null && weiter == null) { Hinweis("Audiobookshelf nicht erreichbar: $fehler"); return }
    val start: (Eintrag) -> Unit = { e -> Wiedergabe.spiele(e.id); oeffne(Seite.Player) }
    LazyColumn(contentPadding = PaddingValues(bottom = 48.dp)) {
        item { Reihe("Weiterhören", weiter ?: emptyList()) { e -> Karte(abs.cover(e.id, e.stand), e.titel, e.autor) { start(e) } } }
        (bibliotheken ?: emptyList()).forEach { (neu, alle) ->
            item { Reihe("Kürzlich hinzugefügt", neu) { e -> Karte(abs.cover(e.id, e.stand), e.titel, e.autor) { start(e) } } }
            item { Reihe("Alle Hörbücher", alle) { e -> Karte(abs.cover(e.id, e.stand), e.titel, e.autor) { start(e) } } }
        }
    }
}

@Composable
fun PodcastsTab(abs: Audiobookshelf, oeffne: (Seite) -> Unit) {
    val (fav, _) = laden(abs) { abs.favoriten() }
    val rang = { id: String -> (fav ?: emptyList()).indexOf(id).let { if (it < 0) Int.MAX_VALUE else it } }
    // Lieblings-Podcasts (vom iPhone gemerkt) und ihre Folgen zuerst.
    val (folgenRoh, fehler) = laden(abs) { abs.neueFolgen(20) }
    val (podcastsRoh, _) = laden(abs) { abs.bibliotheken("podcast").flatMap { abs.eintraege(it, anzahl = 100) } }
    val folgen = folgenRoh?.sortedBy { rang(it.itemId) }
    val podcasts = podcastsRoh?.sortedBy { rang(it.id) }
    if (fehler != null && folgen == null) { Hinweis(fehler); return }
    if (folgen?.isEmpty() == true && podcasts?.isEmpty() == true) { Hinweis("Keine Podcasts in Audiobookshelf."); return }
    LazyColumn(contentPadding = PaddingValues(bottom = 48.dp)) {
        item { Reihe("Neue Folgen", folgen ?: emptyList()) { f -> FolgenKarte(f, abs, oeffne) } }
        item { Reihe("Podcasts", podcasts ?: emptyList()) { p -> Karte(abs.cover(p.id, p.stand), (if (rang(p.id) != Int.MAX_VALUE) "★ " else "") + p.titel, p.autor) { oeffne(Seite.PodcastS(p)) } } }
    }
}

@Composable
fun RadioTab(n: Navidrome, oeffne: (Seite) -> Unit) {
    // Mit eigenem Dienst gibt es Logos; sonst die Sender direkt aus Navidrome.
    val (sender, fehler) = laden(n) {
        val (code, text) = runCatching { Netz.hole(n.server + "/wunsch-api/musik/sender", kopf = n.dienstKopf) }.getOrDefault(0 to "")
        // Ohne eigenen Dienst kommt oft eine HTML-Seite zurück: dann einfach die Navidrome-Sender.
        val dienst = if (code == 200) runCatching { JSONObject(text) }.getOrNull() else null
        if (dienst?.optBoolean("eingerichtet") == true)
            dienst.liste("sender").map { Triple(Sender(it.getString("id"), it.optString("name"), it.optString("streamUrl")), it.text("bild"), Unit) }
        else n.sender().map { Triple(it, null as String?, Unit) }
    }
    if (fehler != null && sender == null) { Hinweis(fehler); return }
    if (sender?.isEmpty() == true) { Hinweis("Keine Sender. Auf dem iPhone unter Musik → Radio suchen und mit dem Stern merken."); return }
    LazyColumn(contentPadding = PaddingValues(bottom = 48.dp)) {
        item { Reihe("Radio", sender ?: emptyList()) { (s, bild, _) -> Karte(bild, s.name, "Internetradio", breite = 160.dp) { Wiedergabe.spiele(s); oeffne(Seite.Player) } } }
    }
}

@Composable
fun TitelSeite(titel: String, untertitel: String, cover: String?, oeffne: (Seite) -> Unit, holen: suspend () -> List<Titel>) {
    val (liste, fehler) = laden(titel + untertitel) { holen() }
    val fokus = remember { FocusRequester() }
    // Mit der Fernbedienung gleich auf „Abspielen“.
    LaunchedEffect(Unit) { runCatching { fokus.requestFocus() } }
    Row(Modifier.fillMaxSize().padding(48.dp)) {
        Column(Modifier.width(320.dp)) {
            Bild(cover, 300.dp)
            Spacer(Modifier.height(16.dp))
            Text(titel, style = MaterialTheme.typography.headlineSmall, color = Color.White)
            Text(untertitel, color = Farben.gedaempft)
            Spacer(Modifier.height(16.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Button(onClick = { liste?.let { Wiedergabe.spiele(it); oeffne(Seite.Player) } }, modifier = Modifier.focusRequester(fokus)) { Text("▶ Abspielen") }
                Button(onClick = { liste?.let { Wiedergabe.spiele(it.shuffled()); oeffne(Seite.Player) } }) { Text("Zufällig") }
            }
        }
        Spacer(Modifier.width(32.dp))
        when {
            fehler != null -> Hinweis(fehler)
            liste == null -> Hinweis("Lädt …")
            else -> LazyColumn(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                itemsIndexed(liste) { i, t ->
                    ListItem(selected = false, onClick = { Wiedergabe.spiele(liste, i); oeffne(Seite.Player) },
                        headlineContent = { Text(t.titel, maxLines = 1) },
                        supportingContent = { Text(t.kuenstler, maxLines = 1) },
                        trailingContent = { Text(zeitText(t.dauer.toDouble())) })
                }
            }
        }
    }
}

@Composable
fun KuenstlerSeite(k: Kuenstler, n: Navidrome, oeffne: (Seite) -> Unit) {
    val (alben, fehler) = laden(k.id) { n.albenVon(k.id) }
    Column(Modifier.fillMaxSize().padding(top = 32.dp)) {
        Text(k.name, style = MaterialTheme.typography.headlineMedium, color = Color.White, modifier = Modifier.padding(start = 48.dp))
        if (fehler != null) Hinweis(fehler) else Reihe("Alben", alben ?: emptyList()) { a -> AlbumKarte(a, n, oeffne) }
    }
}

@Composable
fun PodcastSeite(p: Eintrag, abs: Audiobookshelf?, oeffne: (Seite) -> Unit) {
    val (folgen, fehler) = laden(p.id) { abs?.folgen(p) ?: emptyList() }
    val fokus = remember { FocusRequester() }
    LaunchedEffect(folgen) { if (!folgen.isNullOrEmpty()) runCatching { fokus.requestFocus() } }
    Row(Modifier.fillMaxSize().padding(48.dp)) {
        Column(Modifier.width(320.dp)) {
            Bild(abs?.cover(p.id, p.stand), 300.dp)
            Spacer(Modifier.height(16.dp))
            Text(p.titel, style = MaterialTheme.typography.headlineSmall, color = Color.White)
            Text("${folgen?.size ?: 0} Folgen", color = Farben.gedaempft)
            FavoritKnopf(p.id, abs)
        }
        Spacer(Modifier.width(32.dp))
        when {
            fehler != null -> Hinweis(fehler)
            folgen == null -> Hinweis("Lädt …")
            else -> LazyColumn(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                itemsIndexed(folgen) { i, f ->
                    ListItem(selected = false, onClick = { Wiedergabe.spiele(f.itemId, f.id); oeffne(Seite.Player) },
                        modifier = if (i == 0) Modifier.focusRequester(fokus) else Modifier,
                        headlineContent = { Text(f.titel, maxLines = 2) },
                        supportingContent = { Text(listOf(datumText(f.datum), if (f.dauer > 0) "${(f.dauer / 60).toInt()} Min." else "").filter { it.isNotEmpty() }.joinToString(" · ")) })
                }
            }
        }
    }
}

@Composable
fun PlayerSeite() {
    val a = Wiedergabe.anzeige
    val fokus = remember { FocusRequester() }
    LaunchedEffect(a != null) { if (a != null) runCatching { fokus.requestFocus() } }
    if (a == null) { Hinweis(Wiedergabe.fehler ?: "Lädt …"); return }
    Row(Modifier.fillMaxSize().padding(56.dp), verticalAlignment = Alignment.CenterVertically) {
        Bild(a.cover, 380.dp)
        Spacer(Modifier.width(48.dp))
        Column(Modifier.weight(1f)) {
            Text(a.titel, style = MaterialTheme.typography.headlineMedium, color = Color.White, maxLines = 3)
            Text(Wiedergabe.aktuellesKapitel?.titel ?: a.untertitel, style = MaterialTheme.typography.titleMedium, color = Farben.gedaempft)
            Spacer(Modifier.height(24.dp))
            if (Wiedergabe.dauer > 0) {
                Fortschritt((Wiedergabe.zeit / Wiedergabe.dauer).toFloat())
                Row(Modifier.fillMaxWidth()) {
                    Text(zeitText(Wiedergabe.zeit), color = Farben.gedaempft)
                    Spacer(Modifier.weight(1f))
                    Text("-" + zeitText(Wiedergabe.dauer - Wiedergabe.zeit), color = Farben.gedaempft)
                }
            }
            Spacer(Modifier.height(24.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
                Button(onClick = { Wiedergabe.zurueck() }) { Text(if (Wiedergabe.istHoerbuch) "‹ 15 s" else "⏮") }
                Button(onClick = { Wiedergabe.umschalten() }, modifier = Modifier.focusRequester(fokus)) { Text(if (Wiedergabe.spielt) "❚❚ Pause" else "▶ Abspielen") }
                Button(onClick = { Wiedergabe.weiter() }) { Text(if (Wiedergabe.istHoerbuch) "30 s ›" else "⏭") }
                SchlafKnopf()
            }
            Wiedergabe.fehler?.let { Text(it, color = Farben.violett, modifier = Modifier.padding(top = 16.dp)) }
            if (Wiedergabe.kapitel.size > 1) {
                Spacer(Modifier.height(24.dp))
                LazyColumn(Modifier.height(220.dp)) {
                    items(Wiedergabe.kapitel) { k ->
                        ListItem(selected = Wiedergabe.aktuellesKapitel == k, onClick = { Wiedergabe.springe(k.start) },
                            headlineContent = { Text(k.titel, maxLines = 1) }, trailingContent = { Text(zeitText(k.start)) })
                    }
                }
            }
        }
    }
}

@Composable
fun Fortschritt(anteil: Float) {
    Box(Modifier.fillMaxWidth().height(6.dp).background(Farben.flaeche)) {
        Box(Modifier.fillMaxWidth(anteil.coerceIn(0f, 1f)).fillMaxHeight().background(Farben.blau))
    }
}

/** Schlaf-Timer: jeder Druck schaltet weiter (Aus → 15 → 30 → 45 → 60 → 90 → Ende → Aus). */
@Composable
fun SchlafKnopf() {
    val stufen = listOf<Int?>(null, 15, 30, 45, 60, 90)
    var stufe by remember { mutableIntStateOf(0) }
    var jetzt by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { while (true) { kotlinx.coroutines.delay(1000); jetzt = System.currentTimeMillis() } }
    val text = when {
        Wiedergabe.schlafenAmEnde -> "☾ Ende"
        Wiedergabe.schlafenUm != null -> "☾ " + zeitText(((Wiedergabe.schlafenUm!! - jetzt) / 1000.0))
        else -> "☾ Schlaf-Timer"
    }
    Button(onClick = {
        stufe = (stufe + 1) % (stufen.size + if (Wiedergabe.schlafEnde != null) 1 else 0)
        if (stufe == stufen.size) Wiedergabe.schlafenAmEndeAn() else Wiedergabe.schlafen(stufen[stufe])
    }) { Text(text) }
}

@Composable
fun EinstellungenTab(zugangGeaendert: (Zugang) -> Unit) {
    val ctx = LocalContext.current
    val z = Zugang.laden(ctx)
    Column(Modifier.padding(48.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Navidrome: ${z.server} (${z.benutzer})", color = Color.White)
        Text("Audiobookshelf: " + (if (z.mitHoerbuechern) "${z.absServer} (${z.absBenutzer})" else "nicht eingerichtet"), color = Color.White)
        Text("Version ${ctx.packageManager.getPackageInfo(ctx.packageName, 0).versionName}", color = Farben.gedaempft)
        Text("Einrichten vom iPhone: Ohrregal → Start → Profilsymbol → „Fernseher einrichten“, hier „Übernehmen“ drücken.", color = Farben.gedaempft)
        Button(onClick = { zugangGeaendert(z.copy(passwort = "")) }) { Text("Zugänge ändern") }
    }
}

/** Stern: Podcast als Favorit merken (gleiche Liste wie auf dem iPhone). */
@Composable
fun FavoritKnopf(id: String, abs: Audiobookshelf?) {
    val bereich = rememberCoroutineScope()
    var liste by remember { mutableStateOf<List<String>?>(null) }
    LaunchedEffect(id) { liste = abs?.favoriten() }
    val ist = liste?.contains(id) == true
    Button(onClick = {
        val neu = (liste ?: emptyList()).let { if (ist) it - id else it + id }
        liste = neu
        bereich.launch { abs?.favoritenSpeichern(neu) }
    }, modifier = Modifier.padding(top = 12.dp)) { Text(if (ist) "★ Favorit" else "☆ Zu Favoriten") }
}
