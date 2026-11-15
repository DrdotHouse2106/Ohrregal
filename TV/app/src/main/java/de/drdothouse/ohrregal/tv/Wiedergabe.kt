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
    private var folgeId: String? = null
    var abs: Audiobookshelf? = null
    var navidrome: Navidrome? = null
    private var gehoertSeitSync = 0.0

    val aktuellesKapitel get() = kapitel.lastOrNull { it.start <= zeit + 0.5 }

    fun verbinden(c: Context) {
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
    }

    fun schlafenAmEndeAn() { schlafenUm = null; schlafenAmEnde = true; controller?.volume = 1f }

    val schlafEnde get() = when {
        kapitel.isNotEmpty() -> "Ende des Kapitels"
        istRadio || dauer <= 0 -> null
        istHoerbuch -> "Ende der Folge"
        else -> "Ende des Titels"
    }

    // MARK: Intern

    private fun eintragGewechselt(index: Int? = null) {
        if (istHoerbuch || istRadio) return
        val i = index ?: controller?.currentMediaItemIndex ?: return
        val t = titel.getOrNull(i) ?: return
        anzeige = Anzeige(t.titel, t.kuenstler, navidrome?.cover(t.cover, 600))
        dauer = t.dauer.toDouble()
        bereich.launch { navidrome?.scrobble(t.id, false) }
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
            if (rest <= 0) { c.pause(); schlafenUm = null; c.volume = 1f }
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
