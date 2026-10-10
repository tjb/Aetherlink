"""Unit tests for the parts of sqldojo.core that don't need a database.

    python3 -m unittest discover -s tests
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqldojo import core  # noqa: E402


class StripSqlTest(unittest.TestCase):
    def test_removes_comments_and_trailing_semicolons(self):
        sql = "-- header\nSELECT 1 /* inline */ AS x; -- trailing\n;\n"
        self.assertEqual(core.strip_sql(sql), "SELECT 1   AS x")

    def test_keeps_semicolons_and_comment_markers_inside_strings(self):
        sql = "SELECT ';' AS a, '--not a comment' AS b, $$;$$ AS c, \"we;ird\" FROM t;"
        self.assertEqual(core.strip_sql(sql), sql[:-1])

    def test_escaped_quotes(self):
        self.assertEqual(core.strip_sql("SELECT 'it''s; fine'"), "SELECT 'it''s; fine'")

    def test_nested_block_comments(self):
        self.assertEqual(core.strip_sql("/* a /* b */ c */SELECT 1"), "SELECT 1")

    def test_rejects_multiple_statements(self):
        with self.assertRaises(core.QueryError):
            core.strip_sql("CREATE INDEX ON events (user_id); SELECT 1")

    def test_only_comments_is_empty(self):
        self.assertEqual(core.strip_sql("-- nothing here\n\n"), "")


class NormalizeTest(unittest.TestCase):
    def test_numbers_compare_after_rounding(self):
        self.assertEqual(core.normalize("12.30", 2), core.normalize("12.3", 2))
        self.assertEqual(core.normalize("5", 2), core.normalize("5.000", 2))
        self.assertEqual(core.normalize("2.345", 2), "2.35")  # half up
        self.assertEqual(core.normalize("-0.001", 2), "0")
        self.assertEqual(core.normalize("1e3", 0), "1000")

    def test_non_numbers_are_untouched(self):
        self.assertEqual(core.normalize("2025-01-01", 2), "2025-01-01")
        self.assertEqual(core.normalize(" padded ", 2), " padded ")
        self.assertIsNone(core.normalize(core.NULL, 2))


class FakeQuestion:
    def __init__(self, ordered=False, decimals=2):
        self.ordered, self.decimals = ordered, decimals


class CompareTest(unittest.TestCase):
    expected = core.Result(["a", "b"], [["1", "x"], ["2", "y"]], 1.0)

    def test_unordered_match(self):
        ok, _ = core.compare(self.expected, core.Result(["a", "b"], [["2", "y"], ["1.00", "x"]], 1.0),
                             FakeQuestion())
        self.assertTrue(ok)

    def test_ordered_mismatch_explains_order(self):
        ok, msgs = core.compare(self.expected, core.Result(["a", "b"], [["2", "y"], ["1", "x"]], 1.0),
                                FakeQuestion(ordered=True))
        self.assertFalse(ok)
        self.assertIn("wrong order", " ".join(m for _, m in msgs))

    def test_column_count(self):
        ok, msgs = core.compare(self.expected, core.Result(["a"], [["1"], ["2"]], 1.0), FakeQuestion())
        self.assertFalse(ok)
        self.assertIn("Expected 2 columns", msgs[0][1])

    def test_reports_missing_and_extra_rows(self):
        ok, msgs = core.compare(self.expected, core.Result(["a", "b"], [["1", "x"], ["3", "z"]], 1.0),
                                FakeQuestion())
        self.assertFalse(ok)
        text = " ".join(m for _, m in msgs)
        self.assertIn("(2, y)", text)
        self.assertIn("(3, z)", text)

    def test_null_is_not_empty_string(self):
        ok, _ = core.compare(core.Result(["a"], [[core.NULL]], 1.0), core.Result(["a"], [[""]], 1.0),
                             FakeQuestion())
        self.assertFalse(ok)


class QuestionBankTest(unittest.TestCase):
    def test_every_question_is_well_formed(self):
        qs = core.load_questions()
        self.assertGreater(len(qs), 0)
        self.assertEqual([q.id for q in qs], list(range(1, len(qs) + 1)), "ids should be 1..n without gaps")
        for q in qs:
            with self.subTest(q=q.code):
                self.assertTrue(q.dir.name.startswith(q.code + "-"), "directory must start with the id")
                self.assertTrue(q.solution_path.exists())
                self.assertTrue(q.hints, "every question needs hints")
                self.assertIn(q.level, core.LEVELS)
                self.assertIn("Expected columns", q.prompt)
                self.assertTrue(q.solution_path.read_text().startswith(f"-- Q{q.code} · {q.title}"),
                                "solution.sql should start with '-- Qnnn · <title>'")
                core.strip_sql(q.expected_path.read_text())  # single statement
                if q.is_perf:
                    self.assertTrue((q.dir / "expected.sql").exists(), "perf questions grade against expected.sql")


if __name__ == "__main__":
    unittest.main()
