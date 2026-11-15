package de.drdothouse.ohrregal.tv

import android.content.Context
import androidx.compose.runtime.Composable

/** Store-Fassung (Amazon, Google Play): Updates kommen über den Store, hier gibt es keinen Updater. */
object Aktualisierung {
    fun pruefen(c: Context) {}

    @Composable
    fun Hinweis() {}
}
