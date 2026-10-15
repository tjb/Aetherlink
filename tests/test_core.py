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


class ScriptTest(unittest.TestCase):
    def test_split_statements(self):
        self.assertEqual(core.split_statements("DELETE FROM t; -- c\nSELECT ';' ; /* x; */ SELECT $$a;b$$"),
                         ["DELETE FROM t", "SELECT ';'", "SELECT $$a;b$$"])

    def test_script_sandbox(self):
        for bad in ["BEGIN", "COMMIT", "ROLLBACK", "SET ROLE dojo", "set local role x", "RESET ROLE",
                    "SET SESSION AUTHORIZATION dojo", "\\c dojo"]:
            with self.subTest(bad=bad), self.assertRaises(core.QueryError):
                core.validate_script("SELECT 1;\n" + bad)
        core.validate_script("SAVEPOINT a; DELETE FROM t; ROLLBACK TO a; SELECT setval('s', 1, false)")


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


class StatementAtTest(unittest.TestCase):
    TEXT = ("-- users\nSELECT * FROM users LIMIT 5;\n\n"
            "-- statuses\nSELECT status, count(*)\nFROM orders\nGROUP BY 1;\n\n"
            "SELECT 'a;b' AS x, $$;$$ AS y, \"we;ird\" AS z;\n")

    def at(self, needle, after=0):
        """The statement when the cursor sits just before `needle` (+ after characters)."""
        return core.statement_at(self.TEXT, self.TEXT.index(needle) + after)

    def test_cursor_inside_a_statement(self):
        self.assertEqual(self.at("FROM orders"), ("SELECT status, count(*)\nFROM orders\nGROUP BY 1;", 5))

    def test_cursor_right_after_the_semicolon_runs_that_statement(self):
        self.assertEqual(self.at("LIMIT 5;", after=8)[0], "SELECT * FROM users LIMIT 5;")

    def test_blank_line_belongs_to_the_statement_above(self):
        blank = self.TEXT.index(";\n\n-- statuses") + 2
        self.assertEqual(core.statement_at(self.TEXT, blank)[0], "SELECT * FROM users LIMIT 5;")

    def test_comment_line_belongs_to_the_statement_below(self):
        self.assertEqual(self.at("-- statuses")[1], 5)
        self.assertEqual(self.at("-- users")[1], 2)

    def test_semicolons_inside_strings_and_dollar_quotes(self):
        self.assertEqual(self.at("'a;b'")[0], "SELECT 'a;b' AS x, $$;$$ AS y, \"we;ird\" AS z;")

    def test_end_of_text_and_a_final_statement_without_semicolon(self):
        self.assertEqual(core.statement_at(self.TEXT, len(self.TEXT))[1], 9)
        self.assertEqual(core.statement_at("SELECT 1;\nSELECT 2", 15), ("SELECT 2", 2))

    def test_cursor_after_the_semicolon_with_a_trailing_comment_or_spaces(self):
        self.assertEqual(core.statement_at("SELECT 1; -- one row\nSELECT 2;\n", 20), ("SELECT 1;", 1))
        self.assertEqual(core.statement_at("SELECT 1;  \r\nSELECT 2;\n", 11), ("SELECT 1;", 1))

    def test_escape_strings(self):
        sql = "SELECT E'it\\'s; fine' AS a;\nSELECT 2 AS b;\n"
        self.assertEqual(core.statement_at(sql, 3), ("SELECT E'it\\'s; fine' AS a;", 1))
        self.assertEqual(core.split_statements(sql), ["SELECT E'it\\'s; fine' AS a", "SELECT 2 AS b"])
        # a plain string ending in a backslash is not an escape
        self.assertEqual(core.split_statements("SELECT 'a\\'; SELECT 1"), ["SELECT 'a\\'", "SELECT 1"])

    def test_nothing_to_run(self):
        self.assertIsNone(core.statement_at("-- just a comment\n\n", 3))
        self.assertIsNone(core.statement_at("", 0))


class ScratchTest(unittest.TestCase):
    def test_plain_queries_are_capped(self):
        for sql in ("SELECT * FROM events", "with x as (select 1) select * from x", "TABLE users",
                    "(SELECT 1) UNION (SELECT 2)", "VALUES (1), (2)",
                    "SELECT * FROM orders WHERE status = 'update' AND note = 'insert into'"):
            with self.subTest(sql=sql):
                wrapped, ok = core.limit_rows(sql, 1000)
                self.assertTrue(ok)
                self.assertTrue(wrapped.startswith("WITH scratch AS MATERIALIZED ("))  # keeps the plan
                self.assertTrue(wrapped.endswith("LIMIT 1001"))

    def test_writes_are_left_alone(self):
        for sql in ("INSERT INTO t VALUES (1)", "SELECT * INTO t2 FROM t", "EXPLAIN SELECT 1",
                    "WITH d AS (DELETE FROM t RETURNING *) SELECT * FROM d", "SET work_mem = '1GB'"):
            with self.subTest(sql=sql):
                self.assertEqual(core.limit_rows(sql, 1000), (sql, False))

    def test_session_statements_are_refused(self):
        """Each Scratch query runs on its own: BEGIN/SET would silently not carry over."""
        q = core.get_question(31)
        for sql in ("BEGIN", "rollback;", "SET work_mem = '1GB'", "LOCK orders", "-- note\nSAVEPOINT a"):
            with self.subTest(sql=sql), self.assertRaises(core.QueryError):
                core.scratch_query(q, sql)

    def test_read_only_only_on_plain_postgres_questions(self):
        self.assertTrue(core.scratch_is_read_only(core.get_question(1)))
        self.assertFalse(core.scratch_is_read_only(core.get_question(30)))  # performance: make indexes
        self.assertFalse(core.scratch_is_read_only(core.get_question(35)))  # lab
        self.assertFalse(core.scratch_is_read_only(core.get_question(47)))  # DuckDB

    def test_peek_sql(self):
        self.assertEqual(core.ident('we"ird'), '"we""ird"')
        small = core.peek_column_sql("orders", "status", "text", (5, 0.0), 450_000)[0]
        self.assertIn("GROUP BY 1\nORDER BY 2 DESC, 1", small)  # by position: a column named rows is fine
        self.assertIn("LIMIT 201", small)  # one more than shown, to tell when there are more
        self.assertNotIn("TABLESAMPLE", small)
        big = core.peek_column_sql("events", "event_type", "text", (6, 0.0), 29_000_000)[0]
        self.assertIn("TABLESAMPLE SYSTEM", big)
        self.assertIn("approx_rows", big)
        many, what = core.peek_column_sql("users", "signup_at", "timestamp with time zone", (-1, 0.0), 500_000)
        self.assertIn('min("signup_at") AS min', many)
        self.assertIn("count(DISTINCT", many)  # exact on small tables, not the planner's guess
        self.assertIn("exact", what)
        sampled, what = core.peek_column_sql("events", "occurred_at", "timestamp(3) with time zone",
                                             (-0.9, 0.0), 29_000_000)
        self.assertIn("AS sample_min", sampled)
        self.assertNotIn("DISTINCT", sampled)
        self.assertIn("of the sample", what)
        self.assertNotIn("min(", core.peek_column_sql("t", "flag", "boolean", None, None)[0])
        self.assertNotIn("min(", core.peek_column_sql("t", "during", "daterange", (-1, 0.0), 1000)[0])
        # n_distinct as a fraction of the rows: 25 of 82 is few values
        self.assertIn("GROUP BY 1", core.peek_column_sql("categories", "parent_id", "integer", (-0.3049, 0.0), 82)[0])
        keys = core.peek_column_sql("events", "properties", "jsonb", (-0.1, 0.0), 29_000_000)[0]
        self.assertIn("LEFT JOIN LATERAL jsonb_object_keys", keys)  # arrays and scalars still show up
        self.assertIn("AS k(key)", keys)


class PlanTest(unittest.TestCase):
    def test_parallel_step(self):
        self.assertEqual(core.parallel_step("parallel:worker*4"), ("worker", 4))
        self.assertEqual(core.parallel_step("parallel: writers * 3"), ("writers", 3))
        self.assertEqual(core.parallel_step("parallel:deliver"), ("deliver", 2))


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
                self.assertTrue(q.solution_path.read_text().startswith(f"-- Q{q.code} · {q.title}"),
                                "solution.sql should start with '-- Qnnn · <title>'")
                if q.is_lab:
                    self.assertTrue(q.check_path.exists(), "labs need check.sql")
                    self.assertTrue(q.setup_path is not None or q.lake_paths,
                                    "labs need setup.sql (or lake_paths for DuckDB labs)")
                    if q.kind == "script":
                        self.assertTrue(q.run_as, "script labs need run_as")
                        core.validate_script(q.solution_path.read_text())
                    if q.kind == "pipeline":
                        self.assertEqual(q.plan[0], "setup")
                        self.assertEqual(q.plan[-1], "check")
                        self.assertIn("answer, answer", ", ".join(q.plan), "run the answer twice in a row")
                        for st in q.plan:
                            if st.startswith("parallel:"):
                                self.assertGreater(core.parallel_step(st)[1], 1)
                    continue
                self.assertIn("Expected columns", q.prompt)
                core.strip_sql(q.expected_path.read_text())  # single statement
                if q.is_perf:
                    self.assertTrue((q.dir / "expected.sql").exists(), "perf questions grade against expected.sql")
                if q.engine == "duckdb" and q.max_files_read:
                    self.assertTrue(q.max_files_read.isdigit() or q.max_files_read.startswith("glob:lake/"))


if __name__ == "__main__":
    unittest.main()
