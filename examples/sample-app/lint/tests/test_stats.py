"""Unit tests for stats.py."""

import unittest

import stats

ITEMS = [
    {"id": 1, "name": "apple", "price": "2.0"},
    {"id": 2, "name": "pear", "price": "4.0"},
    {"id": 3, "name": "fig"},
    {"id": 4, "name": "plum", "price": "n/a"},
]


class StatsTest(unittest.TestCase):
    def test_average_skips_items_without_a_valid_price(self):
        self.assertEqual(stats.average_price(ITEMS, []), 3.0)

    def test_average_of_nothing_is_zero(self):
        self.assertEqual(stats.average_price([], []), 0.0)

    def test_cheapest_returns_n_items_by_price(self):
        priced = ITEMS[:3]
        self.assertEqual([i["id"] for i in stats.cheapest(priced, 1)], [1])

    def test_to_json_sorts_keys(self):
        self.assertEqual(stats.to_json([{"b": 1, "a": 2}]), '[{"a": 2, "b": 1}]')


if __name__ == "__main__":
    unittest.main()
