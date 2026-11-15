package de.drdothouse.ohrregal.tv

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import androidx.tv.material3.Button
import androidx.tv.material3.Text
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Nur in der APK von GitHub: Beim Start nach einer neuen Version im Release „tv“ schauen,
 * sie im Hintergrund laden und dann „Neue Version installieren“ anbieten. Installieren bestätigt man selbst.
 */
object Aktualisierung {
    private const val INFO = "https://github.com/DrdotHouse2106/Ohrregal/releases/download/tv/version.json"
    private val bereich = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    private var name by mutableStateOf<String?>(null)
    private var datei by mutableStateOf<File?>(null)

    fun pruefen(c: Context) = bereich.launch {
        runCatching {
            val (code, text) = Netz.hole(INFO)
            if (code != 200) return@launch
            val j = JSONObject(text)
            @Suppress("DEPRECATION")
            val jetzt = c.packageManager.getPackageInfo(c.packageName, 0).versionCode
            if (j.optInt("versionCode") <= jetzt) return@launch
            datei = laden(c, j.getString("apk"))
            name = j.optString("versionName")
        }
    }

    private suspend fun laden(c: Context, adresse: String): File = withContext(Dispatchers.IO) {
        // Bis Android 6 kann der Installer nur Dateien im öffentlichen Cache lesen.
        val ordner = if (Build.VERSION.SDK_INT < 24) (c.externalCacheDir ?: c.cacheDir) else File(c.cacheDir, "updates")
        ordner.mkdirs()
        val ziel = File(ordner, "ohrregal-tv.apk")
        val v = URL(adresse).openConnection() as HttpURLConnection
        v.instanceFollowRedirects = true
        v.inputStream.use { ein -> ziel.outputStream().use { ein.copyTo(it) } }
        ziel
    }

    private fun installieren(c: Context) {
        val f = datei ?: return
        val uri = if (Build.VERSION.SDK_INT < 24) Uri.fromFile(f) else FileProvider.getUriForFile(c, c.packageName + ".updates", f)
        c.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    @Composable
    fun Hinweis() {
        val c = LocalContext.current
        if (datei != null) Button(onClick = { installieren(c) }, modifier = Modifier.padding(start = 8.dp)) { Text("Neue Version ${name ?: ""} installieren") }
    }
}
