package de.drdothouse.ohrregal.tv

import android.content.Context

/** Zugänge zu Navidrome (Pflicht) und Audiobookshelf (optional), gespeichert auf dem Gerät. */
data class Zugang(
    val server: String = "", val benutzer: String = "", val passwort: String = "",
    val absServer: String = "", val absBenutzer: String = "", val absPasswort: String = "",
) {
    val vollstaendig get() = server.isNotBlank() && benutzer.isNotBlank() && passwort.isNotBlank()
    val mitHoerbuechern get() = absServer.isNotBlank() && absBenutzer.isNotBlank() && absPasswort.isNotBlank()

    fun speichern(c: Context) = c.getSharedPreferences("zugang", Context.MODE_PRIVATE).edit()
        .putString("server", server).putString("benutzer", benutzer).putString("passwort", passwort)
        .putString("absServer", absServer).putString("absBenutzer", absBenutzer).putString("absPasswort", absPasswort)
        .apply()

    companion object {
        fun laden(c: Context): Zugang {
            val p = c.getSharedPreferences("zugang", Context.MODE_PRIVATE)
            fun s(k: String) = p.getString(k, "") ?: ""
            return Zugang(s("server"), s("benutzer"), s("passwort"), s("absServer"), s("absBenutzer"), s("absPasswort"))
        }

        /** „musik.example.de“ → „https://musik.example.de“; http bleibt nur im Heimnetz. */
        fun adresse(text: String): String {
            var t = text.trim().trimEnd('/')
            if (t.isEmpty()) return t
            if (!t.startsWith("http://") && !t.startsWith("https://")) t = "https://$t"
            val host = t.substringAfter("://").substringBefore("/").substringBefore(":")
            val heimnetz = host.endsWith(".local") || host.startsWith("192.168.") || host.startsWith("10.") ||
                Regex("^172\\.(1[6-9]|2\\d|3[01])\\.").containsMatchIn(host)
            if (t.startsWith("http://") && !heimnetz) t = "https://" + t.removePrefix("http://")
            return t.removeSuffix("/app")
        }
    }
}

/** Mehrere Personen pro Fernseher (wie bei Quallenkino): jede mit eigenen Zugängen, beim Start „Wer hört?“. */
object Profile {
    private fun json(z: Zugang) = org.json.JSONObject().put("server", z.server).put("benutzer", z.benutzer).put("passwort", z.passwort)
        .put("absServer", z.absServer).put("absBenutzer", z.absBenutzer).put("absPasswort", z.absPasswort)

    fun alle(c: Context): List<Zugang> {
        val p = c.getSharedPreferences("zugang", Context.MODE_PRIVATE)
        val text = p.getString("profile", null)
        if (text == null) {
            // Bisher gab es nur einen Zugang: als erste Person übernehmen.
            val alt = Zugang.laden(c)
            return (if (alt.vollstaendig) listOf(alt) else emptyList()).also { speichern(c, it) }
        }
        val a = org.json.JSONArray(text)
        return (0 until a.length()).map { a.getJSONObject(it) }.map {
            Zugang(it.optString("server"), it.optString("benutzer"), it.optString("passwort"),
                it.optString("absServer"), it.optString("absBenutzer"), it.optString("absPasswort"))
        }
    }

    private fun speichern(c: Context, liste: List<Zugang>) =
        c.getSharedPreferences("zugang", Context.MODE_PRIVATE).edit().putString("profile", org.json.JSONArray(liste.map(::json)).toString()).apply()

    /** Gleiche Person (Server + Benutzer) wird ersetzt, sonst angehängt. */
    fun hinzufuegen(c: Context, z: Zugang): List<Zugang> {
        val neu = alle(c).filterNot { it.server == z.server && it.benutzer == z.benutzer } + z
        speichern(c, neu)
        return neu
    }

    fun entfernen(c: Context, z: Zugang): List<Zugang> {
        val neu = alle(c).filterNot { it.server == z.server && it.benutzer == z.benutzer }
        speichern(c, neu)
        return neu
    }
}
