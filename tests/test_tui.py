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

    @staticmethod
    async def _settle(app, pilot):
        await pilot.pause(0.3)
        await app.workers.wait_for_complete()
        await pilot.pause(0.3)


if __name__ == "__main__":
    unittest.main()
