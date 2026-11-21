package de.drdothouse.ohrregal.tv

import org.json.JSONObject
import java.net.URLEncoder
import java.security.MessageDigest

data class Album(val id: String, val name: String, val kuenstler: String, val cover: String?)
data class Titel(val id: String, val titel: String, val kuenstler: String, val album: String, val cover: String?, val dauer: Long)
data class Kuenstler(val id: String, val name: String, val cover: String?)
data class Playlist(val id: String, val name: String, val cover: String?, val anzahl: Int)
data class Sender(val id: String, val name: String, val url: String)

/** Subsonic-/OpenSubsonic-Schnittstelle von Navidrome (Token-Anmeldung, Passwort verlässt das Gerät nicht). */
class Navidrome(val server: String, val benutzer: String, private val passwort: String) {
    private val salt = (1..12).map { "abcdefghijklmnopqrstuvwxyz0123456789".random() }.joinToString("")
    private val token = MessageDigest.getInstance("MD5").digest((passwort + salt).toByteArray()).joinToString("") { "%02x".format(it) }

    fun adresse(methode: String, parameter: Map<String, String> = emptyMap()): String {
        val alle = mapOf("u" to benutzer, "t" to token, "s" to salt, "v" to "1.16.1", "c" to "OhrregalTV", "f" to "json") + parameter
        return "$server/rest/$methode?" + alle.entries.joinToString("&") { "${it.key}=${URLEncoder.encode(it.value, "UTF-8")}" }
    }

    /** Kopfzeilen für den eigenen Dienst (Wunsch-API), gleiche Anmeldung wie Navidrome. */
    val dienstKopf get() = mapOf("X-Subsonic-U" to benutzer, "X-Subsonic-T" to token, "X-Subsonic-S" to salt)

    private suspend fun hole(methode: String, parameter: Map<String, String> = emptyMap()): JSONObject {
        val (_, text) = Netz.hole(adresse(methode, parameter))
        val antwort = JSONObject(text).getJSONObject("subsonic-response")
        if (antwort.optString("status") != "ok") {
            val code = antwort.optJSONObject("error")?.optInt("code")
            throw Exception(if (code == 40) "Benutzername oder Passwort falsch." else antwort.optJSONObject("error")?.optString("message") ?: "Navidrome-Fehler")
        }
        return antwort
    }

    suspend fun ping() { hole("ping") }

    fun stream(id: String) = adresse("stream", mapOf("id" to id))
    fun cover(id: String?, groesse: Int = 400) = id?.let { adresse("getCoverArt", mapOf("id" to it, "size" to "$groesse")) }

    private fun album(j: JSONObject) = Album(j.getString("id"), j.optString("name", j.optString("title")), j.optString("artist"), j.text("coverArt"))
    private fun titel(j: JSONObject) = Titel(j.getString("id"), j.optString("title"), j.optString("artist"), j.optString("album"), j.text("coverArt"), j.optLong("duration"))

    suspend fun alben(typ: String, anzahl: Int = 30) =
        hole("getAlbumList2", mapOf("type" to typ, "size" to "$anzahl")).optJSONObject("albumList2")?.liste("album")?.map(::album) ?: emptyList()

    suspend fun albumTitel(id: String) = hole("getAlbum", mapOf("id" to id)).getJSONObject("album").liste("song").map(::titel)

    suspend fun kuenstler(): List<Kuenstler> =
        hole("getArtists").getJSONObject("artists").liste("index").flatMap { it.liste("artist") }
            .map { Kuenstler(it.getString("id"), it.optString("name"), it.text("coverArt")) }

    suspend fun albenVon(kuenstler: String) = hole("getArtist", mapOf("id" to kuenstler)).getJSONObject("artist").liste("album").map(::album)

    suspend fun playlists() = hole("getPlaylists").optJSONObject("playlists")?.liste("playlist")
        ?.map { Playlist(it.getString("id"), it.optString("name"), it.text("coverArt"), it.optInt("songCount")) } ?: emptyList()

    suspend fun playlist(id: String) = hole("getPlaylist", mapOf("id" to id)).getJSONObject("playlist").liste("entry").map(::titel)

    suspend fun aehnlich(id: String, anzahl: Int = 40) = hole("getSimilarSongs2", mapOf("id" to id, "count" to "$anzahl")).optJSONObject("similarSongs2")?.liste("song")?.map(::titel) ?: emptyList()

    suspend fun zufall(anzahl: Int = 50) = hole("getRandomSongs", mapOf("size" to "$anzahl")).optJSONObject("randomSongs")?.liste("song")?.map(::titel) ?: emptyList()

    suspend fun sender() = hole("getInternetRadioStations").optJSONObject("internetRadioStations")?.liste("internetRadioStation")
        ?.map { Sender(it.getString("id"), it.optString("name"), it.optString("streamUrl")) } ?: emptyList()

    suspend fun suche(text: String): Triple<List<Kuenstler>, List<Album>, List<Titel>> {
        val e = hole("search3", mapOf("query" to text, "artistCount" to "10", "albumCount" to "20", "songCount" to "30")).optJSONObject("searchResult3") ?: JSONObject()
        return Triple(e.liste("artist").map { Kuenstler(it.getString("id"), it.optString("name"), it.text("coverArt")) }, e.liste("album").map(::album), e.liste("song").map(::titel))
    }

    suspend fun scrobble(id: String, fertig: Boolean) { runCatching { hole("scrobble", mapOf("id" to id, "submission" to "$fertig")) } }
}
