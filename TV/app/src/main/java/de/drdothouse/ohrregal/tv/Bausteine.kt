package de.drdothouse.ohrregal.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.tv.material3.*
import coil.compose.AsyncImage

/** Farben wie Quallenkino und Ohrregal auf dem iPhone. */
object Farben {
    val hintergrund = Color(0xFF0B0E14)
    val flaeche = Color(0xFF161B24)
    val blau = Color(0xFF2E96E0)
    val violett = Color(0xFF7F76D6)
    val gedaempft = Color(0xFF8A93A6)
}

val Thema = darkColorScheme(primary = Farben.blau, secondary = Farben.violett, background = Farben.hintergrund,
    surface = Farben.flaeche, onSurface = Color.White, onBackground = Color.White)

/** Karte mit Bild, Titel und Untertitel; mit der Fernbedienung anwählbar. */
@Composable
fun Karte(bild: String?, titel: String, untertitel: String, breite: Dp = 180.dp, rund: Boolean = false, onClick: () -> Unit) {
    Column(Modifier.width(breite)) {
        Card(onClick = onClick, modifier = Modifier.size(breite),
            shape = CardDefaults.shape(if (rund) RoundedCornerShape(50) else RoundedCornerShape(10))) {
            AsyncImage(model = bild, contentDescription = null, contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize().background(Farben.flaeche))
        }
        Spacer(Modifier.height(6.dp))
        Text(titel, maxLines = 2, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodyMedium, color = Color.White)
        if (untertitel.isNotEmpty()) Text(untertitel, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodySmall, color = Farben.gedaempft)
    }
}

/** Waagerechte Reihe mit Überschrift, wie auf dem iPhone. */
@Composable
fun <T> Reihe(titel: String, eintraege: List<T>, inhalt: @Composable (T) -> Unit) {
    if (eintraege.isEmpty()) return
    Column(Modifier.padding(vertical = 12.dp)) {
        Text(titel, style = MaterialTheme.typography.headlineSmall, color = Color.White, modifier = Modifier.padding(start = 48.dp, bottom = 12.dp))
        LazyRow(contentPadding = PaddingValues(horizontal = 48.dp), horizontalArrangement = Arrangement.spacedBy(20.dp)) {
            items(eintraege) { inhalt(it) }
        }
    }
}

@Composable
fun Hinweis(text: String) {
    Box(Modifier.fillMaxSize(), contentAlignment = androidx.compose.ui.Alignment.Center) {
        Text(text, color = Farben.gedaempft, style = MaterialTheme.typography.bodyLarge)
    }
}

fun zeitText(s: Double): String {
    val t = s.toLong().coerceAtLeast(0)
    return if (t >= 3600) "%d:%02d:%02d".format(t / 3600, t % 3600 / 60, t % 60) else "%d:%02d".format(t / 60, t % 60)
}

@Composable
fun Bild(url: String?, groesse: Dp, modifier: Modifier = Modifier) {
    AsyncImage(model = url, contentDescription = null, contentScale = ContentScale.Crop,
        modifier = modifier.size(groesse).clip(RoundedCornerShape(10)).background(Farben.flaeche))
}
