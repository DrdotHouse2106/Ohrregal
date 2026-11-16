package de.drdothouse.ohrregal.tv

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * Mehrere Fernseher spielen gleichzeitig (z. B. Werkstatt). Ein Fernseher ist Leiter, die anderen folgen:
 * Sie messen den Uhrversatz zum Leiter (Anfrage mit kürzester Laufzeit zählt), laden dasselbe und halten
 * die Stelle über ein leicht geändertes Tempo gleich. Je Gerät lässt sich eine Verzögerung einstellen
 * (Fernseher mit Tonverzögerung).
 */
object Gruppe {
    private val bereich = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var lauf: Job? = null

    data class Fernseher(val name: String, val adresse: String)

    /** Andere Ohrregal-Fernseher im Heimnetz. */
    val gefunden = mutableStateListOf<Fernseher>()
    /** Adresse des Leiters, wenn dieser Fernseher mitspielt. */
    var leiter by mutableStateOf<String?>(null); private set
    var leiterName by mutableStateOf(""); private set
    /** Fernseher, die diesem hier folgen. */
    val mitspieler = mutableStateListOf<Fernseher>()
    var verzoegerungMs by mutableStateOf(0L)

    // MARK: Suchen

    private var sucht = false

    fun suchen(c: Context) {
        if (sucht) return
        sucht = true
        val nsd = c.getSystemService(Context.NSD_SERVICE) as NsdManager
        val warteschlange = ArrayDeque<NsdServiceInfo>()
        var loest = false
        fun naechste() {
            if (loest) return
            val info = warteschlange.removeFirstOrNull() ?: return
            loest = true
            nsd.resolveService(info, object : NsdManager.ResolveListener {
                override fun onResolveFailed(i: NsdServiceInfo, e: Int) { bereich.launch { loest = false; naechste() } }
                override fun onServiceResolved(i: NsdServiceInfo) {
                    val ip = i.attributes["ip"]?.let { String(it) } ?: i.host?.hostAddress
                    val adresse = "$ip:${i.port}"
                    bereich.launch {
                        if (ip != null && !adresse.startsWith(Empfaenger.eigeneIp() + ":") && gefunden.none { it.adresse == adresse })
                            gefunden.add(Fernseher(i.serviceName.removePrefix("Ohrregal – "), adresse))
                        loest = false; naechste()
                    }
                }
            })
        }
        runCatching {
            nsd.discoverServices("_ohrregal._tcp", NsdManager.PROTOCOL_DNS_SD, object : NsdManager.DiscoveryListener {
                override fun onServiceFound(i: NsdServiceInfo) { bereich.launch { warteschlange.add(i); naechste() } }
                override fun onServiceLost(i: NsdServiceInfo) {}
                override fun onDiscoveryStarted(t: String) {}
                override fun onDiscoveryStopped(t: String) {}
                override fun onStartDiscoveryFailed(t: String, e: Int) {}
                override fun onStopDiscoveryFailed(t: String, e: Int) {}
            })
        }
    }

    // MARK: Leiter

    /** Holt einen anderen Fernseher dazu: Er folgt ab jetzt diesem hier. */
    fun dazuholen(f: Fernseher) = bereich.launch {
        val (code, _) = runCatching { Netz.hole("http://${f.adresse}/gruppe/folgen", "POST",
            JSONObject().put("leiter", Empfaenger.eigeneAdresse()).put("name", Empfaenger.name)) }.getOrDefault(0 to "")
        if (code == 200 && mitspieler.none { it.adresse == f.adresse }) mitspieler.add(f)
        else if (code != 200) Wiedergabe.fehler = "„${f.name}“ antwortet nicht. Ist Ohrregal dort geöffnet und eine Person gewählt?"
    }

    fun entlassen(f: Fernseher) = bereich.launch {
        runCatching { Netz.hole("http://${f.adresse}/gruppe/verlassen", "POST", JSONObject()) }
        mitspieler.removeAll { it.adresse == f.adresse }
    }

    // MARK: Mitspieler

    fun folgen(adresse: String, name: String) {
        lauf?.cancel()
        leiter = adresse; leiterName = name
        Wiedergabe.nurMitspielen = true
        lauf = bereich.launch {
            val proben = ArrayDeque<Pair<Long, Long>>()   // (Laufzeit, Versatz)
            while (true) {
                runCatching {
                    val t0 = System.currentTimeMillis()
                    val (code, text) = Netz.hole("http://$adresse/gruppe/stand")
                    val t1 = System.currentTimeMillis()
                    if (code == 200) {
                        val j = JSONObject(text)
                        proben.addLast((t1 - t0) to (j.getLong("jetzt") - (t0 + t1) / 2))
                        if (proben.size > 15) proben.removeFirst()
                        val versatz = proben.minBy { it.first }.second
                        j.optJSONObject("stand")?.let { Wiedergabe.angleichen(it, versatz, verzoegerungMs) } ?: Wiedergabe.pause()
                    }
                }
                delay(1000)
            }
        }
    }

    fun verlassen() {
        lauf?.cancel(); lauf = null
        leiter = null
        Wiedergabe.nurMitspielen = false
        Wiedergabe.stopp()
    }
}
