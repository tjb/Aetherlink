"""Headless smoke test for the terminal IDE. Needs Textual and a generated database.

    python3 -m unittest tests/test_tui.py
"""
import asyncio
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from sqldojo import core  # noqa: E402

try:
    from sqldojo.tui import DojoApp
except ImportError:  # Textual not installed
    DojoApp = None


@unittest.skipIf(DojoApp is None, "textual is not installed")
@unittest.skipUnless(core.db_meta(), "no generated database")
class TuiSmokeTest(unittest.TestCase):
    def setUp(self):
        # Keep the real answers/ and progress untouched.
        self.tmp = Path(tempfile.mkdtemp())
        self._saved = core.ANSWERS_DIR, core.PROGRESS_FILE
        core.ANSWERS_DIR, core.PROGRESS_FILE = self.tmp, self.tmp / "progress.json"

    def tearDown(self):
        core.ANSWERS_DIR, core.PROGRESS_FILE = self._saved
        shutil.rmtree(self.tmp)

    def test_solve_a_question(self):
        asyncio.run(self._solve())

    async def _solve(self):
        app = DojoApp()
        async with app.run_test(size=(160, 48)) as pilot:
            await self._settle(app, pilot)
            self.assertTrue(app.meta, "the app should find the database")
            self.assertEqual(app.current.id, 1, "starts on the first unsolved question")

            editor = app.query_one("#editor")
            editor.load_text("SELECT 1 AS wrong")
            await pilot.press("ctrl+r")
            await self._settle(app, pilot)
            self.assertIn("1", str(app.query_one("#result-info").render()))

            await pilot.press("ctrl+t")
            await self._settle(app, pilot)
            q1 = core.get_question(1)
            self.assertFalse(core.is_solved(core.load_progress(), q1))

            await pilot.press("ctrl+g")
            await self._settle(app, pilot)
            self.assertEqual(len(core.revealed_hints(q1)), 1)

            editor.load_text(q1.solution_path.read_text())
            await pilot.press("ctrl+t")
            await self._settle(app, pilot)
            self.assertTrue(core.is_solved(core.load_progress(), q1))
            self.assertTrue((self.tmp / "001.sql").read_text().startswith("-- Q001"))

            await pilot.press("ctrl+n")
            await self._settle(app, pilot)
            self.assertEqual(app.current.id, 2)

            app.load_question(core.get_question(5))
            await self._settle(app, pilot)

        # a new session picks up where the last one left off
        app = DojoApp()
        async with app.run_test(size=(160, 48)) as pilot:
            await self._settle(app, pilot)
            self.assertEqual(app.current.id, 5)

    def test_concurrency_lab(self):
        asyncio.run(self._concurrency_lab())

    async def _concurrency_lab(self):
        """A Level 9 lab: checking runs the worker step in 4 concurrent sessions."""
        q = core.get_question(58)
        app = DojoApp()
        async with app.run_test(size=(160, 48)) as pilot:
            await self._settle(app, pilot)
            app.load_question(q)
            await self._settle(app, pilot)
            titles = [cmd.title for cmd in app.get_system_commands(app.screen)]
            self.assertIn("Lab step: worker", titles)
            app.query_one("#editor").load_text(q.solution_path.read_text())
            await pilot.press("ctrl+t")
            await self._settle(app, pilot)
            self.assertTrue(core.is_solved(core.load_progress(), q))

    def test_scratch_and_peek(self):
        asyncio.run(self._scratch_and_peek())

    async def _scratch_and_peek(self):
        """Scratch runs the statement under the cursor, caps rows, is read-only on plain questions,
        never touches the answer; the Schema tab peeks at tables and columns."""
        q = core.get_question(1)
        app = DojoApp()
        async with app.run_test(size=(160, 48)) as pilot:
            await self._settle(app, pilot)
            app.load_question(q)
            await self._settle(app, pilot)
            await pilot.press("f2")
            self.assertTrue(app.in_scratch())
            scratch = app.query_one("#scratch")
            info = app.query_one("#result-info")
            table = app.query_one("#results")

            scratch.load_text("SELECT 1 AS a;\n\nSELECT 2 AS b, 3 AS c;\n")
            scratch.cursor_location = (2, 3)
            await pilot.press("ctrl+r")
            await self._settle(app, pilot)
            self.assertEqual([str(c.label) for c in table.columns.values()], ["b", "c"])

            scratch.load_text("SELECT generate_series(1, 5000) AS n;")
            await pilot.press("ctrl+r")
            await self._settle(app, pilot)
            self.assertEqual(table.row_count, 1000)
            self.assertIn("there are more", str(info.render()))

            # values that look like Rich markup are shown as they are, and huge values don't crash
            scratch.load_text("SELECT '[a-z]+' AS p, '[/b]' AS q, repeat('x', 200000) AS big;")
            await pilot.press("ctrl+r")
            await self._settle(app, pilot)
            self.assertEqual([str(c) for c in table.get_row_at(0)[:2]], ["[a-z]+", "[/b]"])

            # the cursor after a ';' with a trailing comment runs that statement, not the next one
            scratch.load_text("SELECT 1 AS one; -- first\nSELECT 2 AS two;\n")
            scratch.cursor_location = (0, 25)
            await pilot.press("ctrl+r")
            await self._settle(app, pilot)
            self.assertEqual([str(c.label) for c in table.columns.values()], ["one"])

            scratch.load_text("DELETE FROM users WHERE false;")
            await pilot.press("ctrl+r")
            await self._settle(app, pilot)
            self.assertIn("read-only", str(info.render()))

            app.save_scratch()
            self.assertIn("DELETE FROM users", q.scratch_path.read_text())
            self.assertNotIn("DELETE", q.answer_path.read_text())

            # Ctrl+T grades the Answer tab, even from Scratch
            app.query_one("#editor").load_text(q.solution_path.read_text())
            await pilot.press("ctrl+t")
            await self._settle(app, pilot)
            self.assertTrue(core.is_solved(core.load_progress(), q))

            tree = app.query_one("#schema")
            orders = next(n for n in tree.root.children if n.data == {"table": "orders"})
            tree.select_node(orders)
            await self._settle(app, pilot)
            self.assertIn("order_id", [str(c.label) for c in table.columns.values()])
            status = next(n for n in orders.children if n.data["column"] == "status")
            tree.select_node(status)
            await self._settle(app, pilot)
            self.assertEqual(str(next(iter(table.columns.values())).label), "status")
            self.assertIn("delivered", [str(table.get_row_at(i)[0]) for i in range(table.row_count)])
            tree.select_node(orders)  # collapsing the table keeps the column's values on screen
            await self._settle(app, pilot)
            self.assertFalse(orders.is_expanded)
            self.assertEqual(str(next(iter(table.columns.values())).label), "status")

    def test_fits_a_small_terminal(self):
        asyncio.run(self._small_terminal())

    async def _small_terminal(self):
        app = DojoApp()
        async with app.run_test(size=(80, 24)) as pilot:
            await self._settle(app, pilot)
            for widget in ("#editor", "#status", "#bottom"):
                region = app.query_one(widget).region
                self.assertGreater(region.height, 0, widget)
                self.assertLessEqual(region.bottom, 23, f"{widget} is off screen: {region}")

    @staticmethod
    async def _settle(app, pilot):
        await pilot.pause(0.3)
        await app.workers.wait_for_complete()
        await pilot.pause(0.3)


if __name__ == "__main__":
    unittest.main()
