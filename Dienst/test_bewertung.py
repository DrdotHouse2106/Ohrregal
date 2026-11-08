"""Tests für die Bewertung der Suchtreffer. Nur erfundene Titel.
Aufruf: python3 -m unittest test_bewertung.py"""
import unittest

import hoerbuch_wunsch as h

W = {"titel": "Die Glocken von Morhaven", "autor": "Lena Brückmann", "reihe": None, "teil": None,
     "sprache": "de", "laufzeitMin": 600}


def r(titel, mb=600, **x):
    return {"title": titel, "size": mb * 1_000_000, "grabs": 0, "age": 10, **x}


class Bewertung(unittest.TestCase):
    def test_ungekuerzt_vor_gekuerzt(self):
        a, _ = h.bewerte(r("Lena.Brueckmann.-.Die.Glocken.von.Morhaven.(Ungekuerzt)"), W)
        b, hinweis = h.bewerte(r("Lena Brueckmann - Die Glocken von Morhaven (gekuerzt)"), W)
        self.assertGreater(a, b)
        self.assertIn("gekürzt", hinweis)

    def test_hoerspiel_wird_verworfen(self):
        p, _ = h.bewerte(r("Lena Brueckmann - Die Glocken von Morhaven - Hoerspiel"), W)
        self.assertIsNone(p)

    def test_falscher_titel(self):
        p, _ = h.bewerte(r("Lena Brueckmann - Die Schatten von Morhaven"), W)
        self.assertIsNone(p)

    def test_groesse_passt_nicht(self):
        p, _ = h.bewerte(r("Lena Brueckmann - Die Glocken von Morhaven", mb=20), W)
        self.assertIsNone(p)

    def test_englisch_bei_deutschem_wunsch(self):
        p, _ = h.bewerte(r("Lena Brueckmann - Die Glocken von Morhaven ENGLISH"), W)
        self.assertIsNone(p)

    def test_teil_der_reihe_gibt_punkte(self):
        w = dict(W, reihe="Morhaven", teil="2")
        mit, _ = h.bewerte(r("Lena Brueckmann - Morhaven 02 - Die Glocken von Morhaven"), w)
        ohne, _ = h.bewerte(r("Lena Brueckmann - Die Glocken von Morhaven"), w)
        self.assertGreater(mit, ohne)

    def test_kurztitel_und_nachname(self):
        self.assertEqual(h.kurztitel("Die Glocken: Ein Morhaven-Roman"), "Die Glocken")
        self.assertEqual(h.nachname("Lena Brückmann, Tom Weller"), "brueckmann")


class Hoerspiel(unittest.TestCase):
    W = {"titel": "Die vier ??? und das Nebelschiff", "autor": "Mara Quell", "reihe": "Die vier ???",
         "teil": "42", "sprache": "de", "laufzeitMin": 70, "hoerspiel": 1}

    def test_hoerspiel_wird_bevorzugt(self):
        hs, _ = h.bewerte(r("Die.vier.Fragezeichen.042.und.das.Nebelschiff.Hoerspiel", mb=70), self.W)
        normal, _ = h.bewerte(r("Die.vier.Fragezeichen.042.und.das.Nebelschiff", mb=70), self.W)
        self.assertIsNotNone(hs)
        self.assertGreater(hs, normal)

    def test_folge_nur_mit_nummer(self):
        p, _ = h.bewerte(r("Die vier Fragezeichen - Folge 42 - Hoerspiel", mb=70), self.W)
        self.assertIsNotNone(p)

    def test_falsche_folge(self):
        p, _ = h.bewerte(r("Die vier Fragezeichen - Folge 41 - Hoerspiel", mb=70), self.W)
        self.assertIsNone(p)

    def test_buch_wunsch_lehnt_hoerspiel_weiter_ab(self):
        p, _ = h.bewerte(r("Lena Brueckmann - Die Glocken von Morhaven - Hoerspiel"), W)
        self.assertIsNone(p)

    def test_flac_erlaubt_aber_mp3_vorn(self):
        flac, _ = h.bewerte(r("Die Vier Fragezeichen-042 und das Nebelschiff-DE-AUDIOBOOK-CD-FLAC", mb=480), self.W)
        mp3, _ = h.bewerte(r("Die Vier Fragezeichen-042 und das Nebelschiff-DE-AUDIOBOOK-MP3", mb=70), self.W)
        self.assertIsNotNone(flac)
        self.assertGreater(mp3, flac)

    def test_fragezeichen_werden_wort(self):
        self.assertEqual(h.norm("Die vier ???"), "die vier fragezeichen")


if __name__ == "__main__":
    unittest.main()
