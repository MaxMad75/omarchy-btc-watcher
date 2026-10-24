"""Regression tests for btc-watcher-fetch. Run: python3 -m unittest discover tests"""
import importlib.machinery, importlib.util, os, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
loader = importlib.machinery.SourceFileLoader("fetch", os.path.join(HERE, "..", "bin", "btc-watcher-fetch"))
fetch = importlib.util.module_from_spec(importlib.util.spec_from_loader("fetch", loader))
loader.exec_module(fetch)


class ChangesFrom(unittest.TestCase):
    def test_sample_far_from_window_start_is_rejected(self):
        now = 1_000_000.0
        pts = [[now - 8 * 3600, 100.0], [now - 8 * 3600 + 60, 100.0], [now, 110.0]]
        out, _ = fetch.changes_from(pts, 110.0, now, -0.5)
        self.assertIsNone(out["1h"])
        self.assertEqual(out["24h"], -0.5)

    def test_close_sample_is_used(self):
        now = 1_000_000.0
        pts = [[now - 86400, 100.0], [now - 3600, 105.0], [now, 110.0]]
        out, _ = fetch.changes_from(pts, 110.0, now, None)
        self.assertAlmostEqual(out["1h"], 4.7619, places=3)


class Helpers(unittest.TestCase):
    def test_clean_points_drops_garbage(self):
        self.assertEqual(fetch.clean_points({"a": 1}, 1000), [])
        self.assertEqual(fetch.clean_points([[999, 1.0], "x", [1, 2, 3]], 1000), [[999, 1.0]])

    def test_valid_price(self):
        self.assertFalse(fetch.valid_price([1]))
        self.assertFalse(fetch.valid_price({"value": "1"}))
        self.assertTrue(fetch.valid_price({"value": 1.5}))


if __name__ == "__main__":
    unittest.main()
