import json, os, sys, tempfile, unittest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import sync

FIX = os.path.join(os.path.dirname(__file__), "..", "fixtures", "sv_sample.json")


class SyncTests(unittest.TestCase):
    def run_sync(self):
        d = tempfile.mkdtemp()
        self.assertEqual(sync.main(["--fixture", FIX, "--out", d]), 0)
        return d

    def test_splits_sets(self):
        d = self.run_sync()
        idx = json.load(open(f"{d}/sets.json"))
        self.assertEqual([s["id"] for s in idx], ["sv1", "sv2"])
        self.assertEqual(idx[0]["cards"], 6)

    def test_printing_keys_normalized(self):
        d = self.run_sync()
        p = json.load(open(f"{d}/prices/sv1.json"))["cards"]
        self.assertEqual(set(p["sv1-1"]), {"normal", "reverseHolo"})
        self.assertEqual(set(p["sv1-3"]), {"holo"})
        self.assertEqual(p["sv1-5"]["holo"]["market"], 52.5)

    def test_unpriced_card_omitted_from_prices_kept_in_catalog(self):
        d = self.run_sync()
        p = json.load(open(f"{d}/prices/sv1.json"))["cards"]
        c = json.load(open(f"{d}/catalog/sv1.json"))
        self.assertNotIn("sv1-6", p)
        self.assertIn("sv1-6", [x["id"] for x in c])

    def test_catalog_sorted_by_number(self):
        d = self.run_sync()
        nums = [c["number"] for c in json.load(open(f"{d}/catalog/sv1.json"))]
        self.assertEqual(nums, ["1", "2", "15", "81", "244", "257"])


if __name__ == "__main__":
    unittest.main()
