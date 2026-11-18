package de.drdothouse.ohrregal.tv

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.ServerSocket
import java.net.Socket

/**
 * „Vom iPhone auf den Fernseher“: Die TV-App meldet sich im Heimnetz als _ohrregal._tcp und nimmt kleine
 * HTTP-Anfragen an. Das iPhone schickt, was gerade läuft (Titel-IDs, Hörbuch, Sender); gestreamt wird
 * direkt vom eigenen Server. Zugänge übernimmt der Fernseher nur mit dem Code, den er gerade anzeigt.
 */
object Empfaenger {
    private val bereich = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var server: ServerSocket? = null

    const val PORT = 47811

    /** IPv4-Adresse im Heimnetz (mit Port, falls nicht der feste), zum Eintippen auf dem iPhone. */
    val adresse: String
        get() {
            val ip = adresseIp() ?: "?"
            val port = server?.localPort ?: PORT
            return if (port == PORT) ip else "$ip:$port"
        }

    fun eigeneIp(): String? = adresseIp()
    fun eigeneAdresse(): String = "${adresseIp()}:${server?.localPort ?: PORT}"
    val name = "Ohrregal – " + (Build.MODEL ?: "Fernseher")

    private fun adresseIp(): String? = runCatching {
        java.net.NetworkInterface.getNetworkInterfaces().toList().filter { it.isUp && !it.isLoopback }
            .flatMap { it.inetAddresses.toList() }.filterIsInstance<java.net.Inet4Address>()
            .firstOrNull { it.isSiteLocalAddress }?.hostAddress
    }.getOrNull()

    /** Geheimer Code (10 Zeichen, Kryptozufall) für den QR-Code; wechselt bei jedem Start, geht nie übers Netz. */
    val code = java.security.SecureRandom().let { z -> (1..10).map { "abcdefghjkmnpqrstuvwxyz23456789"[z.nextInt(31)] }.joinToString("") }

    /** Fehlversuche beim Einrichten; nach 5 ist 10 Minuten Pause. */
    private var fehlversuche = 0
    private var gesperrtBis = 0L

    /** Inhalt des QR-Codes: Die iPhone-Kamera öffnet damit Ohrregal, das richtet genau diesen Fernseher ein (ohne „Übernehmen“). */
    val qrInhalt: String
        get() = "ohrregal://fernseher?ip=${adresseIp() ?: ""}&port=${server?.localPort ?: PORT}&code=$code"
    /** Neue Zugänge vom iPhone (die Anmeldeseite übernimmt sie). */
    var neuerZugang by mutableStateOf<Zugang?>(null)
    /** Anfrage vom iPhone, die auf dem Fernseher mit OK bestätigt werden muss. */
    var anfrage by mutableStateOf<Anfrage?>(null)

    class Anfrage(val geraet: String, val zugang: Zugang) {
        val antwort = kotlinx.coroutines.CompletableDeferred<Boolean>()
    }
    /** Wird gesetzt, wenn das iPhone eine Wiedergabe startet (dann den Player zeigen). */
    var vomIphone by mutableStateOf(0)

    fun starten(c: Context) {
        if (server != null) return
        // Fester Port, damit man die Adresse auf dem iPhone notfalls von Hand eingeben kann.
        val s = runCatching { ServerSocket(PORT) }.getOrElse { ServerSocket(0) }
        server = s
        val info = NsdServiceInfo().apply {
            serviceName = name
            serviceType = "_ohrregal._tcp"
            port = s.localPort
            // Alle Sticks heißen im Netz „Android.local“; deshalb die eigene IPv4 mitschicken, das iPhone verbindet direkt.
            adresseIp()?.let { setAttribute("ip", it) }
            setAttribute("port", s.localPort.toString())
        }
        val nsd = c.getSystemService(Context.NSD_SERVICE) as NsdManager
        nsd.registerService(info, NsdManager.PROTOCOL_DNS_SD, object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(i: NsdServiceInfo) {}
            override fun onRegistrationFailed(i: NsdServiceInfo, e: Int) {}
            override fun onServiceUnregistered(i: NsdServiceInfo) {}
            override fun onUnregistrationFailed(i: NsdServiceInfo, e: Int) {}
        })
        bereich.launch {
            while (true) {
                val verbindung = runCatching { s.accept() }.getOrNull() ?: continue
                launch { runCatching { bearbeite(verbindung) }; runCatching { verbindung.close() } }
            }
        }
    }

    private suspend fun bearbeite(v: Socket) {
        v.soTimeout = 15000
        val ein = v.getInputStream().bufferedReader()
        val zeile = ein.readLine() ?: return
        val (methode, pfad) = zeile.split(" ").let { (it.getOrNull(0) ?: "") to (it.getOrNull(1) ?: "") }
        var laenge = 0
        while (true) {
            val kopf = ein.readLine() ?: break
            if (kopf.isEmpty()) break
            if (kopf.lowercase().startsWith("content-length:")) laenge = kopf.substringAfter(":").trim().toIntOrNull() ?: 0
        }
        val puffer = CharArray(laenge)
        var gelesen = 0
        while (gelesen < laenge) { val n = ein.read(puffer, gelesen, laenge - gelesen); if (n < 0) break; gelesen += n }
        val json = runCatching { JSONObject(String(puffer, 0, gelesen)) }.getOrDefault(JSONObject())
        val (code, antwort) = if ("$methode $pfad" == "POST /einrichten" && !json.has("verschluesselt")) bestaetigen(json)
            else withContext(Dispatchers.Main) { antworte(methode, pfad, json) }
        val text = antwort.toString().toByteArray()
        v.getOutputStream().apply {
            write("HTTP/1.1 $code OK\r\nContent-Type: application/json\r\nContent-Length: ${text.size}\r\nConnection: close\r\n\r\n".toByteArray())
            write(text); flush()
        }
    }

    /** AES-GCM, Schlüssel = SHA-256 des Codes (wie auf dem iPhone): 12 Byte Nonce, dann Daten mit Prüfsumme. */
    private fun entschluesseln(paket: String): JSONObject {
        val daten = android.util.Base64.decode(paket, android.util.Base64.DEFAULT)
        val schluessel = javax.crypto.spec.SecretKeySpec(java.security.MessageDigest.getInstance("SHA-256").digest(code.toByteArray()), "AES")
        val c = javax.crypto.Cipher.getInstance("AES/GCM/NoPadding")
        c.init(javax.crypto.Cipher.DECRYPT_MODE, schluessel, javax.crypto.spec.GCMParameterSpec(128, daten, 0, 12))
        return JSONObject(String(c.doFinal(daten, 12, daten.size - 12)))
    }

    /** Zugänge ohne Code: Der Fernseher fragt nach, das iPhone wartet bis zu 90 Sekunden auf „Übernehmen“. */
    private suspend fun bestaetigen(j: JSONObject): Pair<Int, JSONObject> {
        // Nur eine offene Frage gleichzeitig, sonst könnte jemand im Netz den Bildschirm mit Fragen füllen.
        if (withContext(Dispatchers.Main) { anfrage != null }) return 409 to JSONObject().put("text", "Auf dem Fernseher wartet schon eine Anfrage.")
        val a = Anfrage(j.optString("geraet", "iPhone"), Zugang(j.optString("server"), j.optString("benutzer"), j.optString("passwort"),
            j.optString("absServer"), j.optString("absBenutzer"), j.optString("absPasswort")))
        withContext(Dispatchers.Main) { anfrage?.antwort?.complete(false); anfrage = a }
        val ja = kotlinx.coroutines.withTimeoutOrNull(90_000) { a.antwort.await() } ?: false
        withContext(Dispatchers.Main) {
            if (anfrage === a) anfrage = null
            if (ja) neuerZugang = a.zugang
        }
        return if (ja) 200 to JSONObject().put("status", "ok")
        else 403 to JSONObject().put("text", "Auf dem Fernseher nicht bestätigt.")
    }

    private fun antworte(methode: String, pfad: String, j: JSONObject): Pair<Int, JSONObject> {
        val eingerichtet = Wiedergabe.navidrome != null
        return when ("$methode $pfad") {
            "GET /status" -> 200 to JSONObject().put("eingerichtet", eingerichtet).put("hoerbuecher", Wiedergabe.abs != null)
                .put("spielt", Wiedergabe.spielt).put("titel", Wiedergabe.anzeige?.titel ?: "")
            "POST /einrichten" -> {
                // QR-Weg: Zugänge sind mit dem Code auf dem Bildschirm verschlüsselt; nur dann ohne Rückfrage.
                if (System.currentTimeMillis() < gesperrtBis) return 429 to JSONObject().put("text", "Zu viele Fehlversuche. Bitte in 10 Minuten noch einmal.")
                val z = runCatching { entschluesseln(j.getString("verschluesselt")) }.getOrNull()
                if (z == null) {
                    if (++fehlversuche >= 5) { gesperrtBis = System.currentTimeMillis() + 10 * 60_000; fehlversuche = 0 }
                    return 403 to JSONObject().put("text", "Der QR-Code passt nicht zu diesem Fernseher. Bitte neu scannen.")
                }
                fehlversuche = 0
                neuerZugang = Zugang(z.optString("server"), z.optString("benutzer"), z.optString("passwort"),
                    z.optString("absServer"), z.optString("absBenutzer"), z.optString("absPasswort"))
                200 to JSONObject().put("status", "ok")
            }
            "POST /spielen" -> {
                if (!eingerichtet) return 409 to JSONObject().put("text", "Ohrregal auf dem Fernseher ist noch nicht eingerichtet.")
                val zeit = j.optDouble("zeit", 0.0)
                when (j.optString("art")) {
                    "musik" -> {
                        val liste = j.liste("titel").map { Titel(it.getString("id"), it.optString("titel"), it.optString("kuenstler"),
                            it.optString("album"), it.text("cover"), it.optLong("dauer")) }
                        Wiedergabe.spiele(liste, j.optInt("ab"), (zeit * 1000).toLong())
                    }
                    "hoerbuch" -> Wiedergabe.spiele(j.getString("id"), j.text("folge"))
                    "radio" -> {
                        val url = j.optString("url")
                        if (!url.startsWith("http://") && !url.startsWith("https://")) return 400 to JSONObject().put("text", "Ungültige Senderadresse.")
                        Wiedergabe.spiele(Sender(j.optString("id"), j.optString("name"), url))
                    }
                    else -> return 400 to JSONObject().put("text", "Unbekannte Art.")
                }
                vomIphone++
                200 to JSONObject().put("status", "ok")
            }
            "GET /gruppe/stand" -> 200 to JSONObject().put("jetzt", System.currentTimeMillis()).put("stand", Wiedergabe.stand() ?: JSONObject.NULL)
            "POST /gruppe/folgen" -> {
                if (!eingerichtet) return 409 to JSONObject().put("text", "Auf diesem Fernseher ist noch keine Person gewählt.")
                Gruppe.folgen(j.getString("leiter"), j.optString("name").removePrefix("Ohrregal – "))
                200 to JSONObject().put("status", "ok")
            }
            "POST /gruppe/verlassen" -> { Gruppe.verlassen(); 200 to JSONObject().put("status", "ok") }
            "POST /steuern" -> {
                when (j.optString("aktion")) {
                    "umschalten" -> Wiedergabe.umschalten()
                    "weiter" -> Wiedergabe.weiter()
                    "zurueck" -> Wiedergabe.zurueck()
                }
                200 to JSONObject().put("status", "ok")
            }
            else -> 404 to JSONObject().put("text", "Unbekannt.")
        }
    }
}
