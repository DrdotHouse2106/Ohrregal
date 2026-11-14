package de.drdothouse.ohrregal.tv

import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService

/** Spielt im Hintergrund weiter (Bildschirmschoner, andere App) und meldet sich bei Fernbedienung und System. */
class WiedergabeDienst : MediaSessionService() {
    private var sitzung: MediaSession? = null

    override fun onCreate() {
        super.onCreate()
        val player = ExoPlayer.Builder(this)
            .setAudioAttributes(AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MUSIC).build(), true)
            .setHandleAudioBecomingNoisy(true)
            .build()
        sitzung = MediaSession.Builder(this, player).build()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo) = sitzung

    override fun onDestroy() {
        sitzung?.run { player.release(); release() }
        sitzung = null
        super.onDestroy()
    }
}
