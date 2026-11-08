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


if __name__ == "__main__":
    unittest.main()
