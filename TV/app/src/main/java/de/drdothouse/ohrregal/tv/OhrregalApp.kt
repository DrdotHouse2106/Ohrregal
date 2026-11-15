package de.drdothouse.ohrregal.tv

import android.app.Application
import android.os.Build
import coil.ImageLoader
import coil.ImageLoaderFactory
import okhttp3.OkHttpClient
import java.security.KeyStore
import java.security.cert.CertificateFactory
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocketFactory
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager

/**
 * Alte Geräte (Fire TV Stick 2. Generation, Android 5.1) kennen das Let's-Encrypt-Stammzertifikat
 * ISRG Root X1 nicht. Bis Android 7.0 wird es deshalb zu den System-Zertifikaten ergänzt,
 * für Server-Anfragen, Streams (ExoPlayer nutzt HttpURLConnection) und Bilder (Coil/OkHttp).
 */
class OhrregalApp : Application(), ImageLoaderFactory {
    private var fabrik: SSLSocketFactory? = null
    private var vertrauen: X509TrustManager? = null

    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT < 25) runCatching { zertifikateErgaenzen() }
    }

    private fun zertifikateErgaenzen() {
        val speicher = KeyStore.getInstance(KeyStore.getDefaultType()).apply { load(null, null) }
        val system = KeyStore.getInstance("AndroidCAStore").apply { load(null) }
        system.aliases().toList().forEach { speicher.setCertificateEntry(it, system.getCertificate(it)) }
        val isrg = resources.openRawResource(R.raw.isrg_root_x1).use { CertificateFactory.getInstance("X.509").generateCertificate(it) }
        speicher.setCertificateEntry("isrg_root_x1", isrg)
        val tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm()).apply { init(speicher) }
        val ssl = SSLContext.getInstance("TLS").apply { init(null, tmf.trustManagers, null) }
        HttpsURLConnection.setDefaultSSLSocketFactory(ssl.socketFactory)
        fabrik = ssl.socketFactory
        vertrauen = tmf.trustManagers.filterIsInstance<X509TrustManager>().first()
    }

    override fun newImageLoader(): ImageLoader = ImageLoader.Builder(this).okHttpClient {
        OkHttpClient.Builder().apply {
            val f = fabrik; val v = vertrauen
            if (f != null && v != null) sslSocketFactory(f, v)
        }.build()
    }.build()
}
