package de.drdothouse.ohrregal.tv

import android.content.ComponentName
import android.content.Context
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Was gerade läuft, für die Anzeige. */
data class Anzeige(val titel: String, val untertitel: String, val cover: String?)

/**
 * Steuert die Wiedergabe über den Dienst: Musik (Warteschlange), Hörbücher und Podcast-Folgen (Sitzung bei
 * Audiobookshelf, mehrere Dateien als eine Zeitleiste) und Radio. Dazu Schlaf-Timer und Fortschritt.
 */
object Wiedergabe {
    private val bereich = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var controller: MediaController? = null
    private var wartend: (() -> Unit)? = null

    var anzeige by mutableStateOf<Anzeige?>(null); private set
    var spielt by mutableStateOf(false); private set
    var zeit by mutableStateOf(0.0); private set
    var dauer by mutableStateOf(0.0); private set
    var istHoerbuch by mutableStateOf(false); private set
    var istRadio by mutableStateOf(false); private set
    var kapitel by mutableStateOf<List<Kapitel>>(emptyList()); private set
    var schlafenUm by mutableStateOf<Long?>(null); private set
    var schlafenAmEnde by mutableStateOf(false); private set
    var fehler by mutableStateOf<String?>(null)

    private var titel: List<Titel> = emptyList()
    private var spuren: List<Spur> = emptyList()
    private var sitzung: String? = null
    private var itemId: String? = null
    private var sender: Sender? = null
    /** In einer Gruppe als Mitspieler: kein Fortschritt an Audiobookshelf, kein Weiterschalten (das macht der Leiter). */
    var nurMitspielen = false
    private var folgeId: String? = null
    var abs: Audiobookshelf? = null
    var navidrome: Navidrome? = null
    private var gehoertSeitSync = 0.0

    val aktuellesKapitel get() = kapitel.lastOrNull { it.start <= zeit + 0.5 }

    private var einstellungen: android.content.SharedPreferences? = null

    // MARK: Schlafmarken (wie auf dem iPhone): Lesezeichen beim Stellen und Abschalten, am nächsten Tag fragen.

    class SchlafNacht(val item: String, val gestellt: Double, val abgeschaltet: Double?, val abgeschaltetUm: Long)
    var schlafFrage by mutableStateOf<SchlafNacht?>(null); private set

    private fun uhr() = java.text.SimpleDateFormat("d. MMM HH:mm", java.util.Locale.GERMAN).format(java.util.Date())

    private fun markeGestellt() {
        val item = itemId ?: return; if (folgeId != null) return
        val a = abs ?: return
        val alt = einstellungen?.getString("nacht.$item", null)?.let { org.json.JSONObject(it) }
        einstellungen?.edit()?.putString("nacht.$item", org.json.JSONObject().put("gestellt", zeit).toString())?.apply()
        val z = zeit
        bereich.launch {
            if (alt != null && !alt.has("abgeschaltet")) a.lesezeichenLoeschen(item, alt.getDouble("gestellt"))
            a.lesezeichenSetzen(item, z, "☾ Timer gestellt · ${uhr()}")
            aufraeumen(item)
        }
    }

    private fun markeAbgeschaltet() {
        val item = itemId ?: return; if (folgeId != null) return
        val a = abs ?: return
        val alt = einstellungen?.getString("nacht.$item", null)?.let { org.json.JSONObject(it) } ?: return
        einstellungen?.edit()?.putString("nacht.$item", alt.put("abgeschaltet", zeit).put("um", System.currentTimeMillis()).toString())?.apply()
        val z = zeit
        bereich.launch { a.lesezeichenSetzen(item, z, "☾ Abgeschaltet · ${uhr()}"); aufraeumen(item) }
    }

    /** Nur die Schlafmarken der letzten 3 Abende behalten. */
    private suspend fun aufraeumen(item: String) {
        val a = abs ?: return
        val marken = runCatching { a.lesezeichen(item) }.getOrDefault(emptyList()).filter { it.second.startsWith("☾ ") }
        marken.take((marken.size - 6).coerceAtLeast(0)).forEach { a.lesezeichenLoeschen(item, it.first) }
    }

    private fun schlafFragePruefen(item: String) {
        val j = einstellungen?.getString("nacht.$item", null)?.let { org.json.JSONObject(it) }
        schlafFrage = if (j != null && j.has("abgeschaltet") && System.currentTimeMillis() - j.optLong("um") > 3_600_000)
            SchlafNacht(item, j.getDouble("gestellt"), j.getDouble("abgeschaltet"), j.optLong("um")) else null
    }

    fun schlafFrageBeantworten(ziel: Double?) {
        val n = schlafFrage ?: return
        schlafFrage = null
        einstellungen?.edit()?.remove("nacht.${n.item}")?.apply()
        if (ziel != null) springe(ziel)
    }

    fun verbinden(c: Context) {
        einstellungen = c.getSharedPreferences("wiedergabe", Context.MODE_PRIVATE)
        if (controller != null) return
        val token = SessionToken(c, ComponentName(c, WiedergabeDienst::class.java))
        val zukunft = MediaController.Builder(c, token).buildAsync()
        zukunft.addListener({
            val m = zukunft.get()
            controller = m
            m.addListener(object : Player.Listener {
                override fun onIsPlayingChanged(isPlaying: Boolean) {
                    spielt = isPlaying
                    if (!isPlaying) synchronisiere()
                }
                override fun onMediaItemTransition(item: MediaItem?, reason: Int) { eintragGewechselt() }
                override fun onPlaybackStateChanged(state: Int) { if (state == Player.STATE_ENDED && istHoerbuch) zuEnde() }
                override fun onPlayerError(error: androidx.media3.common.PlaybackException) { fehler = "Wiedergabe gestört: ${error.errorCodeName}" }
            })
            wartend?.invoke(); wartend = null
        }, ContextCompat.getMainExecutor(c))
        bereich.launch { while (true) { delay(500); tick() } }
    }

    private fun mitController(aktion: (MediaController) -> Unit) {
        controller?.let(aktion) ?: run { wartend = { controller?.let(aktion) } }
    }

    private fun eintrag(url: String, titel: String, untertitel: String, cover: String?) = MediaItem.Builder().setUri(url)
        .setMediaMetadata(MediaMetadata.Builder().setTitle(titel).setArtist(untertitel).setArtworkUri(cover?.let(Uri::parse)).build()).build()

    // MARK: Starten

    fun spiele(liste: List<Titel>, ab: Int = 0, startMs: Long = 0) {
        val n = navidrome ?: return
        beendeSitzung()
        titel = liste; spuren = emptyList(); kapitel = emptyList(); istHoerbuch = false; istRadio = false
        mitController { c ->
            c.setMediaItems(liste.map { eintrag(n.stream(it.id), it.titel, it.kuenstler, n.cover(it.cover, 600)) }, ab, startMs)
            c.setPlaybackSpeed(1f); c.prepare(); c.play()
        }
        eintragGewechselt(ab)
    }

    fun spiele(sender: Sender) {
        beendeSitzung()
        this.sender = sender
        titel = emptyList(); spuren = emptyList(); kapitel = emptyList(); istHoerbuch = false; istRadio = true
        anzeige = Anzeige(sender.name, "Internetradio", null); dauer = 0.0
        mitController { c -> c.setMediaItem(eintrag(sender.url, sender.name, "Internetradio", null)); c.prepare(); c.play() }
    }

    /** Hörbuch (folge = null) oder Podcast-Folge an der zuletzt gehörten Stelle. */
    fun spiele(id: String, folge: String? = null, cover: String? = null) {
        val a = abs ?: return
        bereich.launch {
            try {
                beendeSitzung()
                val s = a.starte(id, folge)
                sitzung = s.id; spuren = s.spuren; kapitel = s.kapitel; titel = emptyList()
                itemId = id; folgeId = folge
                if (folge == null && !nurMitspielen) schlafFragePruefen(id) else schlafFrage = null
                istHoerbuch = true; istRadio = false; dauer = s.dauer
                anzeige = Anzeige(s.titel, s.autor, cover ?: a.cover(id))
                val start = s.position
                val stelle = spuren.indexOfLast { it.start <= start }.coerceAtLeast(0)
                mitController { c ->
                    c.setMediaItems(spuren.map { eintrag(it.url, s.titel, s.autor, anzeige?.cover) }, stelle, ((start - spuren[stelle].start) * 1000).toLong())
                    c.prepare(); c.play()
                }
            } catch (e: Exception) {
                fehler = e.message
            }
        }
    }

    // MARK: Steuerung

    /** Beim Personenwechsel: alles anhalten und Fortschritt melden. */
    fun stopp() {
        beendeSitzung()
        controller?.run { stop(); clearMediaItems() }
        anzeige = null; titel = emptyList(); spuren = emptyList(); kapitel = emptyList(); istHoerbuch = false; istRadio = false
    }

    fun pause() = mitController { it.pause() }

    fun umschalten() = mitController { if (it.isPlaying) it.pause() else it.play() }

    /** Musik: nächster Titel. Hörbuch: 30 s vor. */
    fun weiter() = mitController { if (istHoerbuch) springe(zeit + 30) else if (it.hasNextMediaItem()) it.seekToNextMediaItem() }

    /** Musik: Anfang bzw. vorheriger Titel. Hörbuch: 15 s zurück. */
    fun zurueck() = mitController { if (istHoerbuch) springe(zeit - 15) else if (it.currentPosition > 3000 || !it.hasPreviousMediaItem()) it.seekTo(0) else it.seekToPreviousMediaItem() }

    /** Sprung auf der Gesamtzeitleiste (Hörbücher aus mehreren Dateien). */
    fun springe(ziel: Double) = mitController { c ->
        val z = ziel.coerceIn(0.0, if (dauer > 0) dauer else Double.MAX_VALUE)
        if (!istHoerbuch) { c.seekTo((z * 1000).toLong()); return@mitController }
        val i = spuren.indexOfLast { it.start <= z }.coerceAtLeast(0)
        c.seekTo(i, ((z - spuren[i].start) * 1000).toLong())
        zeit = z
    }

    fun schlafen(minuten: Int?) {
        schlafenAmEnde = false
        schlafenUm = minuten?.let { System.currentTimeMillis() + it * 60_000L }
        controller?.volume = 1f
        if (minuten != null && istHoerbuch && !nurMitspielen) markeGestellt()
    }

    fun schlafenAmEndeAn() { schlafenUm = null; schlafenAmEnde = true; controller?.volume = 1f }

    val schlafEnde get() = when {
        kapitel.isNotEmpty() -> "Ende des Kapitels"
        istRadio || dauer <= 0 -> null
        istHoerbuch -> "Ende der Folge"
        else -> "Ende des Titels"
    }

    // MARK: Gruppe (mehrere Fernseher gleichzeitig)

    private fun schluessel(): String = when {
        istRadio -> "radio:" + (sender?.url ?: "")
        istHoerbuch -> "hoerbuch:$itemId/${folgeId ?: ""}"
        else -> "musik:" + titel.joinToString(",") { it.id }.hashCode()
    }

    /** Was gerade läuft, mit genauer Stelle jetzt (für Mitspieler). */
    fun stand(): org.json.JSONObject? {
        val c = controller ?: return null
        if (anzeige == null || c.mediaItemCount == 0) return null
        val i = c.currentMediaItemIndex
        val pos = (if (istHoerbuch) spuren.getOrNull(i)?.start ?: 0.0 else 0.0) + c.currentPosition / 1000.0
        val j = org.json.JSONObject().put("schluessel", schluessel()).put("zeit", System.currentTimeMillis())
            .put("position", pos).put("spielt", c.isPlaying).put("tempo", c.playbackParameters.speed.toDouble()).put("index", i)
        when {
            istRadio -> j.put("art", "radio").put("name", sender?.name).put("url", sender?.url)
            istHoerbuch -> j.put("art", "hoerbuch").put("id", itemId).put("folge", folgeId)
            else -> j.put("art", "musik").put("titel", org.json.JSONArray(titel.map {
                org.json.JSONObject().put("id", it.id).put("titel", it.titel).put("kuenstler", it.kuenstler).put("album", it.album).put("cover", it.cover).put("dauer", it.dauer)
            }))
        }
        return j
    }

    /**
     * Mitspieler: dasselbe laden und auf die Stelle des Leiters ziehen. `versatz` = Uhr des Leiters minus eigene Uhr.
     * Kleine Abweichungen gleicht leicht geändertes Tempo aus (unhörbar), große ein Sprung.
     */
    fun angleichen(s: org.json.JSONObject, versatz: Long, verzoegerungMs: Long) {
        val c = controller ?: return
        val leiterTempo = s.optDouble("tempo", 1.0)
        val soll = s.getDouble("position") + (if (s.optBoolean("spielt")) (System.currentTimeMillis() + versatz - s.getLong("zeit")) / 1000.0 * leiterTempo else 0.0) - verzoegerungMs / 1000.0
        if (s.optString("schluessel") != schluessel() || anzeige == null) {
            when (s.optString("art")) {
                "musik" -> spiele(s.liste("titel").map { Titel(it.getString("id"), it.optString("titel"), it.optString("kuenstler"), it.optString("album"), it.text("cover"), it.optLong("dauer")) },
                    s.optInt("index"), (soll * 1000).toLong().coerceAtLeast(0))
                "hoerbuch" -> spiele(s.getString("id"), s.text("folge"))
                "radio" -> spiele(Sender("", s.optString("name"), s.optString("url")))
            }
            return
        }
        if (!s.optBoolean("spielt")) { if (c.isPlaying) c.pause(); return }
        if (!c.isPlaying) c.play()
        if (istRadio) return
        val i = c.currentMediaItemIndex
        if (!istHoerbuch && i != s.optInt("index")) { c.seekTo(s.optInt("index"), (soll * 1000).toLong().coerceAtLeast(0)); return }
        val ist = (if (istHoerbuch) spuren.getOrNull(i)?.start ?: 0.0 else 0.0) + c.currentPosition / 1000.0
        val diff = ist - soll
        when {
            kotlin.math.abs(diff) > 1.0 -> { springe(soll + 0.15); c.setPlaybackSpeed(leiterTempo.toFloat()) }
            kotlin.math.abs(diff) > 0.025 -> c.setPlaybackSpeed((leiterTempo * (1 - diff.coerceIn(-0.05, 0.05))).toFloat())
            else -> c.setPlaybackSpeed(leiterTempo.toFloat())
        }
    }

    // MARK: Intern

    private fun eintragGewechselt(index: Int? = null) {
        if (istHoerbuch || istRadio) return
        val i = index ?: controller?.currentMediaItemIndex ?: return
        val t = titel.getOrNull(i) ?: return
        anzeige = Anzeige(t.titel, t.kuenstler, navidrome?.cover(t.cover, 600))
        dauer = t.dauer.toDouble()
        if (!nurMitspielen) bereich.launch { navidrome?.scrobble(t.id, false) }
    }

    private fun tick() {
        val c = controller ?: return
        val i = c.currentMediaItemIndex
        val sekunden = c.currentPosition / 1000.0
        zeit = if (istHoerbuch) (spuren.getOrNull(i)?.start ?: 0.0) + sekunden else sekunden
        if (!istHoerbuch && !istRadio && c.duration > 0) dauer = c.duration / 1000.0
        if (!c.isPlaying) return
        schlafenUm?.let { um ->
            val rest = (um - System.currentTimeMillis()) / 1000.0
            c.volume = (rest / 10).coerceIn(0.0, 1.0).toFloat()
            if (rest <= 0) { c.pause(); schlafenUm = null; c.volume = 1f; if (istHoerbuch) markeAbgeschaltet() }
        }
        if (schlafenAmEnde) {
            val ende = aktuellesKapitel?.ende ?: dauer
            if (ende > 0 && zeit >= ende - 1) { c.pause(); schlafenAmEnde = false }
        }
        if (istHoerbuch) {
            gehoertSeitSync += 0.5 * c.playbackParameters.speed
            if (gehoertSeitSync >= 15) synchronisiere()
        }
    }

    /** Ende von Hörbuch oder Folge: als gehört markieren, bei Podcasts die nächste ungehörte Folge starten. */
    private fun zuEnde() {
        if (nurMitspielen) return
        val a = abs ?: return
        val id = itemId ?: return
        val folge = folgeId
        zeit = dauer
        synchronisiere(schliessen = true)
        sitzung = null
        bereich.launch {
            a.markiereGehoert(id, folge)
            if (folge != null) runCatching { a.naechsteFolge(id, folge) }.getOrNull()?.let { spiele(id, it.id) }
        }
    }

    private fun synchronisiere(schliessen: Boolean = false) {
        if (nurMitspielen) return
        val s = sitzung ?: return
        val a = abs ?: return
        val z = zeit; val g = gehoertSeitSync; val d = dauer
        gehoertSeitSync = 0.0
        bereich.launch { a.synchronisiere(s, z, g, d, schliessen) }
    }

    private fun beendeSitzung() {
        if (sitzung != null) synchronisiere(schliessen = true)
        sitzung = null
    }
}
