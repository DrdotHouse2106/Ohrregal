package de.drdothouse.ohrregal.tv

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/** Kleine HTTP-Hilfe ohne Zusatzbibliothek. */
object Netz {
    suspend fun hole(url: String, methode: String = "GET", json: JSONObject? = null, kopf: Map<String, String> = emptyMap()): Pair<Int, String> =
        withContext(Dispatchers.IO) {
            val v = URL(url).openConnection() as HttpURLConnection
            v.requestMethod = methode
            v.connectTimeout = 15000
            v.readTimeout = 30000
            kopf.forEach { (k, w) -> v.setRequestProperty(k, w) }
            if (json != null) {
                v.doOutput = true
                v.setRequestProperty("Content-Type", "application/json")
                v.outputStream.use { it.write(json.toString().toByteArray()) }
            }
            val code = v.responseCode
            val text = (if (code in 200..299) v.inputStream else v.errorStream)?.bufferedReader()?.use { it.readText() } ?: ""
            code to text
        }
}

fun JSONObject.text(k: String): String? = if (has(k) && !isNull(k)) opt(k)?.toString() else null
fun JSONObject.liste(k: String): List<JSONObject> = (optJSONArray(k) ?: JSONArray()).let { a -> (0 until a.length()).map { a.getJSONObject(it) } }
