package de.drdothouse.ohrregal.tv

import org.json.JSONArray
import org.json.JSONObject
import java.net.URLEncoder

data class Eintrag(val id: String, val titel: String, val autor: String, val podcast: Boolean, val stand: Long)
data class Folge(val id: String, val itemId: String, val titel: String, val podcast: String, val datum: Long, val dauer: Double)
data class Kapitel(val start: Double, val ende: Double, val titel: String)
data class Spur(val url: String, val start: Double, val dauer: Double)
data class Sitzung(val id: String, val titel: String, val autor: String, val position: Double, val dauer: Double, val spuren: List<Spur>, val kapitel: List<Kapitel>)

/** Audiobookshelf: Hörbücher und Podcasts mit Fortschritt. */
class Audiobookshelf(val server: String, private val benutzer: String, private val passwort: String) {
    private var token: String? = null

    suspend fun anmelden(): String {
        val (code, text) = Netz.hole("$server/login", "POST", JSONObject().put("username", benutzer).put("password", passwort))
        if (code != 200) throw Exception("Audiobookshelf: Benutzername oder Passwort falsch.")
        val u = JSONObject(text).getJSONObject("user")
        return (u.text("token") ?: u.getString("accessToken")).also { token = it }
    }

    private suspend fun hole(pfad: String, methode: String = "GET", json: JSONObject? = null): String {
        for (versuch in 0..1) {
            val t = token ?: anmelden()
            val (code, text) = Netz.hole(server + pfad, methode, json, mapOf("Authorization" to "Bearer $t"))
            if (code == 401 && versuch == 0) { token = null; continue }
            if (code !in 200..299) throw Exception("Audiobookshelf meldet Fehler $code.")
            return text
        }
        throw Exception("Anmeldung bei Audiobookshelf abgelehnt.")
    }

    fun cover(id: String, stand: Long = 0) = token?.let { "$server/api/items/$id/cover?token=$it&ts=$stand" }
    private fun datei(pfad: String) = server + pfad + (if ("?" in pfad) "&" else "?") + "token=$token"

    private fun eintrag(j: JSONObject): Eintrag {
        val m = j.getJSONObject("media").getJSONObject("metadata")
        return Eintrag(j.getString("id"), m.optString("title", "Ohne Titel"), m.text("authorName") ?: m.text("author") ?: "",
            j.optString("mediaType") == "podcast", j.optLong("updatedAt"))
    }

    suspend fun bibliotheken(typ: String) = JSONObject(hole("/api/libraries")).liste("libraries").filter { it.optString("mediaType") == typ }.map { it.getString("id") }

    suspend fun eintraege(bibliothek: String, neueste: Boolean = false, anzahl: Int = 60): List<Eintrag> {
        val sortierung = if (neueste) "&sort=addedAt&desc=1" else "&sort=media.metadata.title"
        return JSONObject(hole("/api/libraries/$bibliothek/items?limit=$anzahl&page=0&minified=1$sortierung")).liste("results").map(::eintrag)
    }

    suspend fun angefangen() = JSONObject(hole("/api/me/items-in-progress")).liste("libraryItems").map(::eintrag).filter { !it.podcast }

    private fun folge(j: JSONObject, itemId: String, podcast: String) = Folge(j.getString("id"), itemId, j.optString("title"), podcast,
        if (j.isNull("publishedAt")) j.optLong("addedAt") else j.optLong("publishedAt"),
        j.optDouble("duration", j.optJSONObject("audioFile")?.optDouble("duration") ?: 0.0))

    suspend fun neueFolgen(anzahl: Int = 20): List<Folge> = bibliotheken("podcast").flatMap { b ->
        JSONObject(hole("/api/libraries/$b/recent-episodes?limit=$anzahl&page=0")).liste("episodes").map {
            folge(it, it.getString("libraryItemId"), it.optJSONObject("podcast")?.optJSONObject("metadata")?.optString("title") ?: "")
        }
    }.sortedByDescending { it.datum }.take(anzahl)

    suspend fun folgen(podcast: Eintrag): List<Folge> =
        JSONObject(hole("/api/items/${podcast.id}?expanded=1")).getJSONObject("media").liste("episodes")
            .map { folge(it, podcast.id, podcast.titel) }.sortedByDescending { it.datum }

    /** Startet eine Wiedergabe-Sitzung (Hörbuch oder Folge) an der zuletzt gehörten Stelle. */
    suspend fun starte(id: String, folge: String? = null): Sitzung {
        val json = JSONObject().put("deviceInfo", JSONObject().put("clientName", "Ohrregal TV")).put("forceDirectPlay", true)
            .put("mediaPlayer", "ExoPlayer").put("supportedMimeTypes", JSONArray(listOf("audio/mpeg", "audio/mp4", "audio/x-m4a", "audio/aac", "audio/flac", "audio/x-m4b", "audio/ogg")))
        val s = JSONObject(hole("/api/items/$id/play" + (folge?.let { "/$it" } ?: ""), "POST", json))
        return Sitzung(s.getString("id"), s.optString("displayTitle"), s.optString("displayAuthor"), s.optDouble("currentTime", 0.0), s.optDouble("duration", 0.0),
            s.liste("audioTracks").map { Spur(datei(it.getString("contentUrl")), it.optDouble("startOffset"), it.optDouble("duration")) }.sortedBy { it.start },
            s.liste("chapters").map { Kapitel(it.optDouble("start"), it.optDouble("end"), it.optString("title")) })
    }

    suspend fun synchronisiere(sitzung: String, zeit: Double, gehoert: Double, dauer: Double, schliessen: Boolean = false) {
        runCatching {
            hole("/api/session/$sitzung/${if (schliessen) "close" else "sync"}", "POST",
                JSONObject().put("currentTime", zeit).put("timeListened", gehoert).put("duration", dauer))
        }
    }

    suspend fun suche(bibliothek: String, text: String) =
        JSONObject(hole("/api/libraries/$bibliothek/search?q=${URLEncoder.encode(text, "UTF-8")}")).liste("book").map { eintrag(it.getJSONObject("libraryItem")) }
}
