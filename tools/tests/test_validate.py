import os, sys, unittest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import validate


def lab(f, cid, printing, rarity="Rare", value=1.0):
    return {"frame": f, "cardId": cid, "printing": printing, "rarity": rarity, "value": value}


def pred(f, cid, printing, flagged=False):
    return {"frame": f, "cardId": cid, "printing": printing, "flagged": flagged}


class ValidateTests(unittest.TestCase):
    def test_printing_mismatch_is_a_miss(self):
        r = validate.evaluate([lab("a", "x-1", "reverseHolo")], [pred("a", "x-1", "normal")])
        self.assertEqual(r["foil_accuracy"], 0.0)
        self.assertFalse(r["gate_pass"])

    def test_gate_passes_at_90_percent(self):
        labels = [lab(str(i), "x-%d" % i, "holo") for i in range(10)]
        preds = [pred(str(i), "x-%d" % i, "holo") for i in range(9)] + [pred("9", "x-0", "holo")]
        r = validate.evaluate(labels, preds)
        self.assertEqual(r["foil_accuracy"], 0.9)
        self.assertTrue(r["gate_pass"])

    def test_flagged_is_not_silent_and_not_tap_free(self):
        r = validate.evaluate([lab("a", "x-1", "holo", value=60)], [pred("a", "x-2", "holo", flagged=True)])
        self.assertEqual(r["totals"]["flagged"], 1)
        self.assertEqual(r["totals"]["silent_wrong"], 0)
        self.assertEqual(r["silent_misses_over_floor"], [])

    def test_silent_miss_over_value_floor_fails_gate(self):
        labels = [lab(str(i), "x-%d" % i, "holo") for i in range(20)]
        labels[0]["value"] = 52.5
        preds = [pred(str(i), "x-%d" % i, "holo") for i in range(20)]
        preds[0] = pred("0", "wrong", "holo")
        r = validate.evaluate(labels, preds)
        self.assertEqual(r["foil_accuracy"], 0.95)
        self.assertEqual(r["silent_misses_over_floor"], ["0"])
        self.assertFalse(r["gate_pass"])

    def test_missing_prediction_counts_as_miss(self):
        r = validate.evaluate([lab("a", "x-1", "holo")], [])
        self.assertEqual(r["totals"]["missing"], 1)
        self.assertFalse(r["gate_pass"])

    def test_buckets(self):
        r = validate.evaluate(
            [lab("a", "c", "normal", "Common"), lab("b", "d", "reverseHolo", "Common")],
            [pred("a", "c", "normal"), pred("b", "d", "reverseHolo")])
        self.assertIn("common", r["by_bucket"])
        self.assertIn("reverse holo", r["by_bucket"])


if __name__ == "__main__":
    unittest.main()
