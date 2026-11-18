package de.drdothouse.ohrregal.tv

import android.content.Context

/** Zugänge zu Navidrome (Pflicht) und Audiobookshelf (optional), gespeichert auf dem Gerät. */
data class Zugang(
    val server: String = "", val benutzer: String = "", val passwort: String = "",
    val absServer: String = "", val absBenutzer: String = "", val absPasswort: String = "",
) {
    /** Adressen mit https:// (das iPhone schickt sie so, wie sie eingetippt wurden), Namen ohne Leerzeichen. */
    fun bereinigt() = copy(server = adresse(server), benutzer = benutzer.trim(), absServer = adresse(absServer), absBenutzer = absBenutzer.trim())

    val vollstaendig get() = server.isNotBlank() && benutzer.isNotBlank() && passwort.isNotBlank()
    val mitHoerbuechern get() = absServer.isNotBlank() && absBenutzer.isNotBlank() && absPasswort.isNotBlank()

    fun speichern(c: Context) = c.getSharedPreferences("zugang", Context.MODE_PRIVATE).edit()
        .putString("server", server).putString("benutzer", benutzer).putString("passwort", passwort)
        .putString("absServer", absServer).putString("absBenutzer", absBenutzer).putString("absPasswort", absPasswort)
        .apply()

    companion object {
        /** Liste aus dem alten, unverschlüsselten Speicher lesen. */
        fun ausJson(text: String): List<Zugang> {
            val a = org.json.JSONArray(text)
            return (0 until a.length()).map { a.getJSONObject(it) }.map {
                Zugang(it.optString("server"), it.optString("benutzer"), it.optString("passwort"),
                    it.optString("absServer"), it.optString("absBenutzer"), it.optString("absPasswort"))
            }
        }

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
        // Verschlüsselt (Android-Keystore); ältere, unverschlüsselte Einträge werden einmal übernommen und gelöscht.
        val text = p.getString("profile_tresor", null)?.let { Tresor.oeffnen(it) } ?: p.getString("profile", null)?.also { alt ->
            speichern(c, Zugang.ausJson(alt))
            // „profile“ selbst entfernt speichern(), sobald verschlüsselt werden kann (sonst bleibt es die Ablage).
            p.edit().remove("server").remove("benutzer").remove("passwort")
                .remove("absServer").remove("absBenutzer").remove("absPasswort").apply()
        }
        if (text == null) {
            // Bisher gab es nur einen Zugang: als erste Person übernehmen.
            val alt = Zugang.laden(c)
            return (if (alt.vollstaendig) listOf(alt) else emptyList()).also { speichern(c, it) }
        }
        val a = org.json.JSONArray(text)
        return (0 until a.length()).map { a.getJSONObject(it) }.map {
            Zugang(it.optString("server"), it.optString("benutzer"), it.optString("passwort"),
                it.optString("absServer"), it.optString("absBenutzer"), it.optString("absPasswort")).bereinigt()
        }
    }

    private fun speichern(c: Context, liste: List<Zugang>) {
        val text = org.json.JSONArray(liste.map(::json)).toString()
        val p = c.getSharedPreferences("zugang", Context.MODE_PRIVATE).edit()
        val verschluesselt = Tresor.verschliessen(text)
        // Ohne Keystore (Android 5.1) bleibt nur die einfache Ablage.
        if (verschluesselt != null) p.putString("profile_tresor", verschluesselt).remove("profile") else p.putString("profile", text)
        p.apply()
    }

    /** Gleiche Person (Server + Benutzer) wird ersetzt, sonst angehängt. */
    fun hinzufuegen(c: Context, zugang: Zugang): List<Zugang> {
        val z = zugang.bereinigt()
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


/** Verschlüsselt die Zugänge mit einem Schlüssel im Android-Keystore (ab Android 6), der das Gerät nie verlässt. */
object Tresor {
    private const val NAME = "ohrregal-profile"

    private fun schluessel(): javax.crypto.SecretKey? {
        if (android.os.Build.VERSION.SDK_INT < 23) return null
        return runCatching {
            val ks = java.security.KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            (ks.getKey(NAME, null) as? javax.crypto.SecretKey) ?: javax.crypto.KeyGenerator.getInstance("AES", "AndroidKeyStore").run {
                init(android.security.keystore.KeyGenParameterSpec.Builder(NAME,
                    android.security.keystore.KeyProperties.PURPOSE_ENCRYPT or android.security.keystore.KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(android.security.keystore.KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(android.security.keystore.KeyProperties.ENCRYPTION_PADDING_NONE).build())
                generateKey()
            }
        }.getOrNull()
    }

    fun verschliessen(text: String): String? {
        val k = schluessel() ?: return null
        return runCatching {
            val c = javax.crypto.Cipher.getInstance("AES/GCM/NoPadding").apply { init(javax.crypto.Cipher.ENCRYPT_MODE, k) }
            android.util.Base64.encodeToString(c.iv + c.doFinal(text.toByteArray()), android.util.Base64.NO_WRAP)
        }.getOrNull()
    }

    fun oeffnen(paket: String): String? {
        val k = schluessel() ?: return null
        return runCatching {
            val d = android.util.Base64.decode(paket, android.util.Base64.NO_WRAP)
            val c = javax.crypto.Cipher.getInstance("AES/GCM/NoPadding")
            c.init(javax.crypto.Cipher.DECRYPT_MODE, k, javax.crypto.spec.GCMParameterSpec(128, d, 0, 12))
            String(c.doFinal(d, 12, d.size - 12))
        }.getOrNull()
    }
}
