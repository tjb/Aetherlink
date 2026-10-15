"""The SQL Dojo terminal IDE (Textual)."""
from __future__ import annotations

from typing import Dict, List, Optional

from rich.text import Text
from textual import on, work
from textual.app import App, ComposeResult, SystemCommand
from textual.binding import Binding
from textual.containers import Horizontal, Vertical, VerticalScroll
from textual.css.query import NoMatches
from textual.screen import ModalScreen
from textual.widgets import (Button, DataTable, Footer, Header, Input, Label, Markdown,
                             OptionList, RichLog, Static, TabbedContent, TabPane, TextArea, Tree)
from textual.widgets.option_list import Option

from . import core
from .core import DojoError, QueryError

MAX_GRID_ROWS = 1000

HELP = """\
# SQL Dojo

Pick a question on the left, write **one query** in the Answer tab, and check it.
Your answer is saved automatically to `answers/NNN.sql`.

The **Scratch** tab (`F2` switches) is for exploring: write as many queries as you like, end each
with `;`, and `Ctrl+R` runs the one under the cursor (or the text you selected). Scratch is never
graded, is saved to `answers/scratch/NNN.sql`, and shows up to 1,000 rows. On ordinary questions it's
**read-only**, so an experiment can't damage the dataset. Each query runs on its own (autocommit):
for `BEGIN ... ROLLBACK` or `SET`, use `./dojo psql`.

| Keys | |
|---|---|
| `Ctrl+R` / `F5` | **Run** your answer (in Scratch: the query under the cursor) |
| `F2` | Switch between the **Answer** and **Scratch** tabs |
| `Ctrl+T` / `F6` | **Check** your answer against the reference (from either tab) |
| `Ctrl+E` / `F7` | **Explain**: `EXPLAIN (ANALYZE, BUFFERS)` your query |
| `Ctrl+G` / `F8` | Reveal the next **hint** |
| `Ctrl+O` / `F9` | Show the reference **solution** and explanation |
| `Ctrl+N` | **Next** unsolved question |
| `Esc` | Cancel a running query |
| `Ctrl+P` | Command palette: start/regenerate the database, reset indexes, ... |
| `Tab` / `Shift+Tab` | Move between panes |
| `Ctrl+Q` | Quit |

**Schema tab** (left): `Enter` on a table shows its first 100 rows. `Enter` on a column shows its
values with their counts, most common first (or a summary when there are too many values; tables
over a million rows are sampled, and the label says so). `i` inserts the name into the editor.

**Labs** (⚗, Level 6): `Ctrl+R` runs every statement in the editor (autocommit, as the
superuser, with psql's output). `Ctrl+T` checks the database state. In *script* labs it runs your
script as the lab's role inside a transaction and rolls back. *Reset this lab* (command palette)
starts a lab over.

**Performance questions** (⏱): create indexes or materialized views in a psql shell
(`./dojo psql` in another terminal), then check. Your query runs 3 times and the best time counts.
Undo everything with *Reset objects I created* in the command palette.

Press `Esc` to close.
"""


class SchemaTree(Tree):
    """Tables and columns. Enter peeks at the data; i inserts the name into the editor."""
    BINDINGS = [Binding("i", "insert_name", "Insert name")]

    def action_insert_name(self) -> None:
        node = self.cursor_node
        if node is not None and node.data:
            self.app.insert_name(node.data)


class HelpScreen(ModalScreen[None]):
    BINDINGS = [Binding("escape,f1,q", "app.pop_screen", "Close")]

    def compose(self) -> ComposeResult:
        with VerticalScroll(id="help-dialog"):
            yield Markdown(HELP)


class SolutionScreen(ModalScreen[None]):
    BINDINGS = [Binding("escape,q", "app.pop_screen", "Close")]

    def __init__(self, q: core.Question):
        super().__init__()
        self.q = q

    def compose(self) -> ComposeResult:
        with Vertical(id="solution-dialog"):
            yield Static(f"[b]Reference solution · Q{self.q.code} · {self.q.title}[/b]   [dim]Esc to close[/dim]")
            yield TextArea.code_editor(self.q.solution_path.read_text(encoding="utf-8"),
                                       language="sql", read_only=True, theme="vscode_dark")


class ConfirmScreen(ModalScreen[bool]):
    BINDINGS = [Binding("escape", "cancel", "Cancel")]

    def __init__(self, message: str, yes: str = "Yes"):
        super().__init__()
        self.message, self.yes = message, yes

    def compose(self) -> ComposeResult:
        with Vertical(id="confirm-dialog"):
            yield Static(self.message)
            with Horizontal(classes="buttons"):
                yield Button(self.yes, id="yes", variant="warning")
                yield Button("Cancel", id="no")

    @on(Button.Pressed)
    def pressed(self, event: Button.Pressed) -> None:
        self.dismiss(event.button.id == "yes")

    def action_cancel(self) -> None:
        self.dismiss(False)


class SetupScreen(ModalScreen[bool]):
    """Start the container and (re)generate the dataset, streaming the output."""
    BINDINGS = [Binding("escape", "skip", "Skip")]

    def __init__(self, regenerate: bool = False):
        super().__init__()
        self.regenerate = regenerate
        self.busy = False

    def compose(self) -> ComposeResult:
        title = "Regenerate the dataset" if self.regenerate else "Set up the practice database"
        with Vertical(id="setup-dialog"):
            yield Static(f"[b]{title}[/b]")
            yield Static(
                "This starts Postgres 17 in Docker (container [b]sql-dojo-db[/b], port 5433) and generates "
                "the Larkspur dataset inside it. [b]Scale 1[/b] ≈ 6M events, ~0.8 GB, under a minute. "
                "Scale 10 ≈ 58M events, ~8 GB (needs ~12 GB free inside Docker while generating), ~7 minutes. You can change it later from the command "
                "palette (Ctrl+P).", classes="muted")
            if self.regenerate:
                yield Static("[b $warning]This replaces the data and drops indexes/views you created.[/]")
            with Horizontal(classes="buttons"):
                yield Label("Scale ")
                yield Input(value="1", id="scale", restrict=r"[0-9.]*", max_length=6)
                yield Button("Start", id="start", variant="primary")
                yield Button("Skip", id="skip")
            yield RichLog(id="setup-log", wrap=True, markup=False, highlight=False)

    @on(Button.Pressed, "#start")
    @on(Input.Submitted, "#scale")
    def start(self) -> None:
        if self.busy:
            return
        try:
            scale = float(self.query_one("#scale", Input).value or "1")
        except ValueError:
            self.notify("Scale must be a number like 1 or 0.2", severity="error")
            return
        self.busy = True
        self.query_one("#start", Button).disabled = True
        self.run_setup(scale)

    @on(Button.Pressed, "#skip")
    def action_skip(self) -> None:
        if not self.busy:
            self.dismiss(False)

    @work(thread=True, exclusive=True, group="setup")
    def run_setup(self, scale: float) -> None:
        log = self.query_one("#setup-log", RichLog)

        def out(line: str) -> None:
            self.app.call_from_thread(log.write, line)
        try:
            if not core.using_custom_psql():
                out("$ docker compose up -d --wait")
            core.start_database(out)
            meta = core.db_meta()
            if meta and not self.regenerate:
                out(f"Data already generated (scale={meta.get('scale')}).")
            else:
                out(f"Generating the dataset at scale {scale:g}...")
                core.generate_data(scale, out)
            out("Ready.")
            self.app.call_from_thread(self.dismiss, True)
        except DojoError as e:
            out(f"ERROR: {e}")
            self.busy = False
            self.app.call_from_thread(setattr, self.query_one("#start", Button), "disabled", False)


class DojoApp(App):
    TITLE = "SQL Dojo"
    CSS = """
    #sidebar { width: 42; border-right: tall $panel; }
    #questions { height: 1fr; border: none; }
    #schema { height: 1fr; }
    #main { width: 1fr; }
    #question-scroll { height: 2fr; min-height: 6; padding: 0 1; border-bottom: tall $panel; }
    #editors { height: 3fr; min-height: 6; }
    #editor, #scratch { height: 1fr; border: none; }
    #status { height: 1; padding: 0 1; background: $panel; color: $text-muted; }
    #bottom { height: 2fr; min-height: 8; }
    #result-info { height: auto; padding: 0 1; }
    #results { height: 1fr; }
    #script-out { height: 1fr; display: none; }
    #check-log, #plan-log { height: 1fr; }
    #hints-md { padding: 0 1; }
    HelpScreen, SolutionScreen, ConfirmScreen, SetupScreen { align: center middle; }
    #help-dialog { width: 90; max-height: 90%; border: thick $primary; background: $surface; padding: 0 1; }
    #solution-dialog { width: 110; height: 85%; border: thick $primary; background: $surface; }
    #solution-dialog > Static { padding: 0 1; height: auto; }
    #confirm-dialog { width: 64; height: auto; border: thick $warning; background: $surface; padding: 1 2; }
    #setup-dialog { width: 96; height: 80%; border: thick $primary; background: $surface; padding: 1 2; }
    #setup-dialog > Static { margin-bottom: 1; }
    .muted { color: $text-muted; }
    .buttons { height: auto; margin-bottom: 1; }
    .buttons Label { padding: 1 1 0 0; }
    .buttons Button { margin-right: 1; }
    #scale { width: 14; margin-right: 1; }
    #setup-log { height: 1fr; border: round $panel; }
    """
    BINDINGS = [
        Binding("ctrl+r", "run", "Run", priority=True),
        Binding("ctrl+t", "check", "Check", priority=True),
        Binding("ctrl+e", "explain", "Explain", priority=True),
        Binding("ctrl+g", "hint", "Hint", priority=True),
        Binding("ctrl+o", "solution", "Solution", priority=True),
        Binding("ctrl+n", "next", "Next", priority=True),
        Binding("f2", "toggle_scratch", "Scratch"),
        Binding("f1", "help", "Help"),
        # F-key aliases (the editor uses F5-F7 itself, hence priority)
        Binding("f5", "run", show=False, priority=True),
        Binding("f6", "check", show=False, priority=True),
        Binding("f7", "explain", show=False, priority=True),
        Binding("f8", "hint", show=False, priority=True),
        Binding("f9", "solution", show=False, priority=True),
        Binding("ctrl+s", "save", show=False, priority=True),
        Binding("escape", "cancel", show=False),
    ]

    def __init__(self):
        super().__init__()
        self.questions: List[core.Question] = core.load_questions()
        self.current: Optional[core.Question] = None
        self.meta: Dict[str, str] = {}
        self._save_timer = None
        self._scratch_timer = None
        self._loading_text = False
        self.busy = False

    # ------------------------------------------------------------------ layout
    def compose(self) -> ComposeResult:
        yield Header()
        with Horizontal():
            with TabbedContent("Questions", "Schema", id="sidebar"):
                yield OptionList(id="questions")
                yield SchemaTree("tables", id="schema")
            with Vertical(id="main"):
                with VerticalScroll(id="question-scroll"):
                    yield Markdown(id="question-md")
                with TabbedContent(id="editors"):
                    with TabPane("Answer", id="tab-answer"):
                        yield TextArea.code_editor("", language="sql", theme="vscode_dark", id="editor")
                    with TabPane("Scratch", id="tab-scratch"):
                        yield TextArea.code_editor("", language="sql", theme="vscode_dark", id="scratch")
                yield Static("", id="status")
                with TabbedContent(id="bottom"):
                    with TabPane("Results", id="tab-results"):
                        yield Static("[dim]Run your query with Ctrl+R (or F5).[/dim]", id="result-info")
                        yield DataTable(id="results", zebra_stripes=True, cursor_type="row")
                        yield RichLog(id="script-out", wrap=False, markup=False, highlight=False)
                    with TabPane("Check", id="tab-check"):
                        yield RichLog(id="check-log", wrap=True, markup=False)
                    with TabPane("Plan", id="tab-plan"):
                        yield RichLog(id="plan-log", wrap=False, markup=False, highlight=False)
                    with TabPane("Hints", id="tab-hints"):
                        with VerticalScroll():
                            yield Markdown(id="hints-md")
        yield Footer()

    def on_mount(self) -> None:
        self.query_one("#schema", Tree).show_root = False
        self.refresh_question_list()
        last = core.last_question_id()
        first = core.resume_question() or (self.questions[0] if self.questions else None)
        if first:
            self.load_question(first)
            if last is not None:
                note = (f"Picking up where you left off: Q{first.code}" if first.id == last
                        else f"Q{last:03d} is done. Next up: Q{first.code}")
                self.notify(note, title="Welcome back")
        self.active_editor().focus()
        self.check_database()

    # ------------------------------------------------------------ questions
    def refresh_question_list(self) -> None:
        progress = core.load_progress()
        ol = self.query_one("#questions", OptionList)
        highlighted = ol.highlighted
        ol.clear_options()
        level = None
        for q in self.questions:
            if q.level != level:
                level = q.level
                ol.add_option(Option(Text(f"{q.level}. {q.level_name}", style="bold"), disabled=True))
            entry = progress.get(q.code, {})
            if core.is_solved(progress, q):
                mark = Text("✔ ", style="green")
            elif entry.get("attempts"):
                mark = Text("… ", style="yellow")
            else:
                mark = Text("  ")
            badge = (" ⏱", "yellow") if q.is_perf else ((" ⚗", "magenta") if q.is_lab else ("", ""))
            label = Text.assemble(mark, (f"{q.id:>2} ", "dim"), q.title, badge)
            ol.add_option(Option(label, id=f"q{q.id}"))
        if highlighted is not None:
            ol.highlighted = highlighted
        solved = sum(core.is_solved(progress, q) for q in self.questions)
        scale = f"scale {self.meta['scale']} · " if self.meta else "no database · "
        self.sub_title = f"{scale}{solved}/{len(self.questions)} solved"

    @on(OptionList.OptionSelected, "#questions")
    def question_selected(self, event: OptionList.OptionSelected) -> None:
        if event.option.id:
            self.load_question(core.get_question(event.option.id[1:]))
            self.active_editor().focus()

    def load_question(self, q: core.Question) -> None:
        self.save_answer()
        self.save_scratch()
        self.current = q
        core.ensure_stub(q)
        core.remember_question(q)
        self._loading_text = True
        self.query_one("#editor", TextArea).load_text(q.answer_path.read_text(encoding="utf-8"))
        self.query_one("#scratch", TextArea).load_text(self.scratch_text(q))
        self.query_one("#question-md", Markdown).update(q.markdown())
        self.query_one("#question-scroll").scroll_home(animate=False)
        self.render_hints()
        self.query_one("#results", DataTable).clear(columns=True)
        self.query_one("#results").display = not q.is_lab
        self.query_one("#script-out", RichLog).clear()
        self.query_one("#script-out").display = q.is_lab
        self.query_one("#result-info", Static).update(self.intro_text(q))
        self.query_one("#check-log", RichLog).clear()
        self.query_one("#plan-log", RichLog).clear()
        self.query_one("#bottom", TabbedContent).active = "tab-results"
        ol = self.query_one("#questions", OptionList)
        try:
            ol.highlighted = ol.get_option_index(f"q{q.id}")
        except Exception:
            pass
        self.set_status(f"answers/{q.code}.sql")
        if self.meta and (q.engine == "duckdb" or q.setup_path or q.lake_paths):
            self.ensure_lab(q)

    @staticmethod
    def intro_text(q: core.Question) -> str:
        """What Ctrl+R does on this question (shown above the results)."""
        if q.kind == "state":
            return "[dim]Ctrl+R runs every statement in the editor (autocommit, as the superuser).[/dim]"
        if q.kind == "script":
            return (f"[dim]Ctrl+R runs your script as yourself (superuser, autocommit). Ctrl+T runs it as "
                    f"{q.run_as} and rolls back.[/dim]")
        if q.kind == "pipeline":
            return ("[dim]Ctrl+R runs your script against the lab as it is now. Land data with Ctrl+P → Lab step. "
                    "Ctrl+T replays the whole pipeline.[/dim]")
        return "[dim]Run your query with Ctrl+R (or F5).[/dim]"

    @work(thread=True, exclusive=True, group="lab")
    def ensure_lab(self, q: core.Question, force: bool = False) -> None:
        try:
            if q.engine == "duckdb" and not core.engine_ready(q):
                self.build_lake_now(rebuild=False)
            if (q.setup_path or q.lake_paths) and (force or not core.lab_is_set_up(q)):
                core.setup_lab(q)
                self.call_from_thread(self.notify, f"Lab for Q{q.code} is ready.")
        except core.NeedsDuckDB:
            self.call_from_thread(self.notify, "DuckDB isn't installed. Quit and run ./dojo lake once.",
                                  severity="error", timeout=10)
        except DojoError as e:
            self.call_from_thread(self.notify, str(e), severity="error", timeout=10)

    def build_lake_now(self, rebuild: bool) -> None:
        """Runs in a worker thread: export Postgres into lake/raw with progress in the status bar."""
        from . import lake
        self.call_from_thread(self.notify, "Building the data lake in lake/ (one time; a minute or so per "
                                           "unit of scale)...", title="Level 8", timeout=8)
        lake.build(lambda line: self.call_from_thread(self.set_status, line.strip()), rebuild=rebuild)
        self.call_from_thread(self.notify, "The data lake is ready.", title="Level 8")
        if self.current is not None:
            self.call_from_thread(self.set_status, f"answers/{self.current.code}.sql")

    @work(thread=True, exclusive=True, group="lab")
    def rebuild_lake(self) -> None:
        try:
            self.build_lake_now(rebuild=True)
        except (DojoError, core.NeedsDuckDB) as e:
            self.call_from_thread(self.notify, str(e) or "DuckDB isn't installed", severity="error", timeout=10)

    @work(thread=True, exclusive=True, group="db")
    def lab_step(self, q: core.Question, step: str) -> None:
        try:
            output, error = core.run_lab_step(q, step), None
        except DojoError as e:
            output, error = "", str(e)
        self.call_from_thread(self.show_script_output, f"-- lab step: {step}\n{output}", error)
        self.call_from_thread(self.notify, f"Ran {step}" if not error else f"{step} failed",
                              severity="information" if not error else "error")

    def render_hints(self) -> None:
        q = self.current
        if not q:
            return
        shown = core.revealed_hints(q)
        if not q.hints:
            text = "*This question has no hints.*"
        elif not shown:
            text = f"*{len(q.hints)} hints available. Press **Ctrl+G** (or F8) to reveal one at a time.*"
        else:
            text = "\n\n".join(f"**Hint {i}/{len(q.hints)}.** {h}" for i, h in enumerate(shown, 1))
            if len(shown) < len(q.hints):
                text += "\n\n*Ctrl+G for the next one.*"
        self.query_one("#hints-md", Markdown).update(text)

    # ---------------------------------------------------------------- editor
    def set_status(self, text: str) -> None:
        db = f"DB ready (scale {self.meta['scale']})" if self.meta else "DB not ready (Ctrl+P → Start database)"
        self.query_one("#status", Static).update(f"{text}   ·   {db}")

    @on(TextArea.Changed, "#editor")
    def editor_changed(self) -> None:
        if self._loading_text:
            self._loading_text = False
            return
        if self._save_timer:
            self._save_timer.stop()
        self._save_timer = self.set_timer(0.8, self.save_answer)

    def save_answer(self) -> None:
        if self.current is None:
            return
        try:
            text = self.query_one("#editor", TextArea).text
        except NoMatches:  # shutting down
            return
        path = self.current.answer_path
        if not path.exists() or path.read_text(encoding="utf-8") != text:
            path.write_text(text, encoding="utf-8")

    def scratch_text(self, q: core.Question) -> str:
        if q.scratch_path.exists():
            return q.scratch_path.read_text(encoding="utf-8")
        return self.scratch_starter(q)

    @staticmethod
    def scratch_starter(q: core.Question) -> str:
        lines = [f"-- Scratch for Q{q.code} · {q.title}. Never graded: explore freely.",
                 "-- Ctrl+R runs the query under the cursor (or the selected text). End each query with ;"]
        if core.scratch_is_read_only(q):
            lines.append("-- Read-only on this question, so experiments can't change the data.")
        lines.append("-- Schema tab (left): Enter on a table shows its rows, on a column its values.")
        example = q.tables[0] if q.tables else ""
        if example and all(part.isidentifier() for part in example.split(".")):
            lines += ["", f"SELECT * FROM {example} LIMIT 10;"]
        return "\n".join(lines) + "\n"

    @on(TextArea.Changed, "#scratch")
    def scratch_changed(self) -> None:
        if self._scratch_timer:
            self._scratch_timer.stop()
        self._scratch_timer = self.set_timer(0.8, self.save_scratch)

    def save_scratch(self) -> None:
        """Save Scratch once it differs from what's on disk (or, for a new file, from the starter)."""
        q = self.current
        if q is None:
            return
        try:
            text = self.query_one("#scratch", TextArea).text
        except NoMatches:  # shutting down
            return
        path = q.scratch_path
        before = path.read_text(encoding="utf-8") if path.exists() else self.scratch_starter(q)
        if text != before:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")

    def in_scratch(self) -> bool:
        return self.query_one("#editors", TabbedContent).active == "tab-scratch"

    def active_editor(self) -> TextArea:
        return self.query_one("#scratch" if self.in_scratch() else "#editor", TextArea)

    def action_toggle_scratch(self) -> None:
        tabs = self.query_one("#editors", TabbedContent)
        tabs.active = "tab-answer" if tabs.active == "tab-scratch" else "tab-scratch"
        self.active_editor().focus()

    @on(TabbedContent.TabActivated, "#editors")
    def editor_tab_changed(self) -> None:
        if self.current is not None:
            self.set_status(f"answers/scratch/{self.current.code}.sql (never graded)" if self.in_scratch()
                            else f"answers/{self.current.code}.sql")

    def scratch_statement(self) -> Optional[tuple]:
        """(sql, first line) of the selection, or of the statement under the cursor."""
        ed = self.query_one("#scratch", TextArea)
        selected = ed.selected_text
        if selected.strip():
            if len(core.split_statements(selected)) > 1:
                self.notify("The selection holds several statements. Select one, or put the cursor in it.",
                            severity="warning")
                return None
            start = min(ed.selection.start, ed.selection.end)
            return selected, start[0] + 1
        offset = ed.document.get_index_from_location(ed.cursor_location)
        found = core.statement_at(ed.text, offset)
        if found is None:
            self.notify("Nothing to run: write a query in Scratch first.", severity="warning")
        return found

    def insert_name(self, data: dict) -> None:
        name = data.get("column") or data.get("table")
        editor = self.active_editor()
        editor.insert(name)
        editor.focus()

    def action_save(self) -> None:
        self.save_answer()
        self.save_scratch()
        self.notify(f"Saved answers/{self.current.code}.sql" if self.current else "Nothing to save")

    def _can_query(self) -> bool:
        if self.current is None:
            return False
        if self.busy:
            self.notify("A query is still running. Esc cancels it.", severity="warning")
            return False
        if not self.meta:
            self.notify("The database isn't ready. Ctrl+P → Start database.", severity="warning")
            return False
        self.save_answer()
        return True

    # --------------------------------------------------------------- actions
    def action_run(self) -> None:
        if self.in_scratch():
            self.run_scratch()
            return
        if self._can_query() and self.current.is_lab:
            self.busy = True
            self.query_one("#bottom", TabbedContent).active = "tab-results"
            self.query_one("#results", DataTable).display = False
            self.query_one("#result-info", Static).update(self.intro_text(self.current))
            out = self.query_one("#script-out", RichLog)
            out.display = True
            out.clear()
            out.write(Text("Running...", style="dim"))
            self.run_script_worker(self.current, self.query_one("#editor", TextArea).text)
        elif self._can_query():
            self.busy = True
            self.query_one("#bottom", TabbedContent).active = "tab-results"
            self.query_one("#results", DataTable).loading = True
            self.run_query_worker(self.current, self.query_one("#editor", TextArea).text)

    def run_scratch(self) -> None:
        if not self._can_query():
            return
        self.save_scratch()
        found = self.scratch_statement()
        if found is None:
            return
        sql, line = found
        self.busy = True
        self.query_one("#bottom", TabbedContent).active = "tab-results"
        self.query_one("#results", DataTable).display = True
        self.query_one("#script-out").display = False
        self.query_one("#results", DataTable).loading = True
        mode = " · read-only" if core.scratch_is_read_only(self.current) else ""
        self.scratch_worker(self.current, sql, f"Scratch · line {line}{mode}")

    @work(thread=True, exclusive=True, group="db")
    def scratch_worker(self, q: core.Question, sql: str, label: str) -> None:
        try:
            res = core.scratch_query(q, sql)
            self.call_from_thread(self.show_result, res, None, label)
        except DojoError as e:
            self.call_from_thread(self.show_result, None, str(e), label)
        except core.NeedsDuckDB:
            self.call_from_thread(self.show_result, None, "DuckDB isn't installed. Quit and run ./dojo lake once.")
        except Exception as e:  # never let an odd result take the whole IDE down
            self.call_from_thread(self.show_result, None, f"{type(e).__name__}: {e}", label)

    # ------------------------------------------------------------- peeking
    @on(Tree.NodeSelected, "#schema")
    def schema_selected(self, event: Tree.NodeSelected) -> None:
        if event.node.allow_expand and not event.node.is_expanded:
            return  # that was a collapse: keep the results you were reading
        if event.node.data and self._can_query():
            self.busy = True
            self.query_one("#bottom", TabbedContent).active = "tab-results"
            self.query_one("#results", DataTable).display = True
            self.query_one("#script-out").display = False
            self.query_one("#results", DataTable).loading = True
            self.peek_worker(dict(event.node.data))

    @work(thread=True, exclusive=True, group="db")
    def peek_worker(self, data: dict) -> None:
        table, column = data["table"], data.get("column")
        name = f"{table}.{column}" if column else table
        self.call_from_thread(self.query_one("#result-info", Static).update, Text(f"Reading {name}...", style="dim"))
        try:
            res, sql, label = core.run_peek(table, column, data.get("type", ""))
            self.call_from_thread(self.show_result, res, None, label, sql)
        except Exception as e:  # never let an odd column take the whole IDE down
            msg = str(e) if isinstance(e, DojoError) else f"{type(e).__name__}: {e}"
            self.call_from_thread(self.show_result, None, msg, name)

    @work(thread=True, exclusive=True, group="db")
    def run_query_worker(self, q: core.Question, sql: str) -> None:
        try:
            res = core.answer_query(q, sql)
            self.call_from_thread(self.show_result, res, None)
        except DojoError as e:
            self.call_from_thread(self.show_result, None, str(e))
        except core.NeedsDuckDB:
            self.call_from_thread(self.show_result, None, "DuckDB isn't installed. Quit and run ./dojo lake once.")

    @work(thread=True, exclusive=True, group="db")
    def run_script_worker(self, q: core.Question, sql: str) -> None:
        try:
            output, error = core.answer_script(q, sql), None
        except DojoError as e:
            output, error = "", str(e)
        except core.NeedsDuckDB:
            output, error = "", "DuckDB isn't installed. Quit and run ./dojo lake once."
        self.call_from_thread(self.show_script_output, output, error)

    def show_script_output(self, output: str, error: Optional[str]) -> None:
        self.busy = False
        self.query_one("#results", DataTable).display = False
        if self.current is not None:
            self.query_one("#result-info", Static).update(self.intro_text(self.current))
        out = self.query_one("#script-out", RichLog)
        out.display = True
        out.clear()
        for line in (error or output or "(no output)").splitlines():
            if error or line.startswith(("ERROR", "FATAL")):
                style = "red"
            elif line.startswith(("Time:", "NOTICE", "WARNING", "INFO", "DETAIL", "HINT")):
                style = "dim"
            else:
                style = ""
            out.write(Text(line, style=style))

    def show_result(self, res: Optional[core.Result], error: Optional[str], label: Optional[str] = None,
                    sql: Optional[str] = None) -> None:
        """Show rows in the grid. label says where they came from (Scratch, a peek); sql is shown
        under it so you can copy it into Scratch and tweak it."""
        self.busy = False
        table = self.query_one("#results", DataTable)
        table.loading = False
        table.display = True
        self.query_one("#script-out").display = False
        info = self.query_one("#result-info", Static)
        table.clear(columns=True)
        line = Text()
        if label:
            line.append(f"{label}  ", style="bold cyan")
        if error:
            line.append(error, style="red")
            info.update(line)
            return
        if not res.header:
            line.append(f"Done in {core.fmt_ms(res.ms)} (the statement returned no rows).", style="dim")
            info.update(line)
            return
        table.add_columns(*[Text(h) for h in res.header])
        for row in res.rows[:MAX_GRID_ROWS]:
            table.add_row(*[Text("NULL", style="dim italic") if v == core.NULL else Text(v) for v in row])
        if res.truncated:
            more = f" (the first {len(res.rows):,}; there are more)"
        elif len(res.rows) > MAX_GRID_ROWS:
            more = f" (showing the first {MAX_GRID_ROWS})"
        else:
            more = ""
        line.append_text(Text.from_markup(f"[b]{len(res.rows):,}[/b] rows{more} in [b]{core.fmt_ms(res.ms)}[/b]"))
        if sql:  # one line, cut to the pane's width, so it never squeezes the grid
            flat, width = " ".join(sql.split()), max(info.content_size.width, 20)
            line.append("\n" + (flat if len(flat) <= width else flat[:width - 1] + "…"), style="dim")
        info.update(line)

    def action_check(self) -> None:
        if self._can_query():
            self.busy = True
            log = self.query_one("#check-log", RichLog)
            log.clear()
            log.write(Text(f"Checking Q{self.current.code} · {self.current.title}...", style="bold"))
            self.query_one("#bottom", TabbedContent).active = "tab-check"
            self.check_worker(self.current, self.query_one("#editor", TextArea).text)

    @work(thread=True, exclusive=True, group="db")
    def check_worker(self, q: core.Question, sql: str) -> None:
        log = self.query_one("#check-log", RichLog)
        try:
            g = core.grade(q, sql, on_status=lambda s: self.call_from_thread(log.write, Text(s, style="dim")))
            self.call_from_thread(self.show_grade, q, g, None)
        except DojoError as e:
            self.call_from_thread(self.show_grade, q, None, str(e))

    def show_grade(self, q: core.Question, g: Optional[core.Grade], error: Optional[str]) -> None:
        self.busy = False
        log = self.query_one("#check-log", RichLog)
        if error or g is None:
            log.write(Text(error or "unknown error", style="red"))
            return
        if g.error:
            title = {"query": "✘ Your query failed:", "script": "✘ Your script failed:"}.get(q.kind, "✘ Not checked:")
            log.write(Text(title, style="bold red"))
            log.write(Text(g.error, style="red"))
            self.refresh_question_list()
            return
        if q.is_lab:
            if g.output:
                self.show_script_output(g.output, None)
            for name, ok, detail in g.checks:
                log.write(Text.assemble(("✔ " if ok else "✘ ", "green" if ok else "red"), name,
                                        (f"  ({detail})" if detail else "", "dim")))
            if g.passed:
                log.write(Text(f"✔ Lab complete!   attempt {g.attempts}", style="bold green"))
                log.write(Text("Ctrl+O: read the explanation   Ctrl+N: next question", style="dim"))
                self.notify(f"Q{q.code} complete!" if g.first_solve else "Still passing!", title="✔ Lab complete")
            else:
                log.write(Text("✘ Not yet.", style="bold red"))
            self.refresh_question_list()
            return
        self.show_result(g.actual, None)
        runs = f" (best of {len(g.timings)})" if len(g.timings) > 1 else ""
        log.write(Text(f"yours      {len(g.actual.rows):>7} rows  {core.fmt_ms(g.best_ms):>10}{runs}"))
        log.write(Text(f"reference  {len(g.expected.rows):>7} rows  {core.fmt_ms(g.expected.ms):>10}", style="dim"))
        styles = {"error": "red", "warn": "yellow", "info": "dim", "row": "white"}
        for kind, text in g.messages:
            log.write(Text(("    " if kind == "row" else "") + text, style=styles.get(kind, "")))
        if g.correct and not g.fast_enough:
            log.write(Text(f"✔ Correct result, but too slow: {core.fmt_ms(g.best_ms)} > target "
                           f"{core.fmt_ms(g.target_ms)}. Look at the plan (Ctrl+E).", style="bold yellow"))
        elif g.passed:
            target = f" (target {core.fmt_ms(g.target_ms)})" if g.target_ms else ""
            hints = f"{g.hints} hint{'s' if g.hints != 1 else ''}" if g.hints else "no hints"
            log.write(Text(f"✔ Correct!{target}   attempt {g.attempts}, {hints}", style="bold green"))
            log.write(Text("Ctrl+O: compare with the reference solution   Ctrl+N: next question", style="dim"))
            self.notify(f"Q{q.code} solved!" if g.first_solve else "Still correct!", title="✔ Correct")
        else:
            log.write(Text("✘ Not quite.", style="bold red"))
            if len(core.revealed_hints(q)) < len(q.hints):
                log.write(Text("Stuck? Ctrl+G reveals a hint.", style="dim"))
        self.refresh_question_list()

    def action_explain(self, analyze: bool = True) -> None:
        if self.in_scratch():
            if self._can_query():
                found = self.scratch_statement()
                if found is None:
                    return
                self.busy = True
                log = self.query_one("#plan-log", RichLog)
                log.clear()
                log.write(Text(f"EXPLAIN (Scratch, line {found[1]})...", style="dim"))
                self.query_one("#bottom", TabbedContent).active = "tab-plan"
                self.explain_worker(found[0], analyze, scratch=True)
            return
        if self.current is not None and self.current.is_lab:
            self.notify("Explain works on single queries. In a lab, put EXPLAIN in the editor and run it.")
            return
        if self._can_query():
            self.busy = True
            log = self.query_one("#plan-log", RichLog)
            log.clear()
            log.write(Text("EXPLAIN (ANALYZE, BUFFERS)..." if analyze else "EXPLAIN...", style="dim"))
            self.query_one("#bottom", TabbedContent).active = "tab-plan"
            self.explain_worker(self.query_one("#editor", TextArea).text, analyze)

    @work(thread=True, exclusive=True, group="db")
    def explain_worker(self, sql: str, analyze: bool, scratch: bool = False) -> None:
        log = self.query_one("#plan-log", RichLog)
        try:
            if scratch:
                plan = core.scratch_explain(self.current, sql, analyze=analyze)
            else:
                plan = core.answer_explain(self.current, sql, analyze=analyze)
            self.call_from_thread(log.clear)
            for line in plan.splitlines():
                style = "bold" if "Seq Scan" in line or "Sort Method: external" in line else ""
                self.call_from_thread(log.write, Text(line, style=style))
            self.call_from_thread(log.write, Text("Tip: paste plans into https://explain.dalibo.com", style="dim"))
        except DojoError as e:
            self.call_from_thread(log.write, Text(str(e), style="red"))
        self.busy = False

    def action_hint(self) -> None:
        if self.current is None:
            return
        if not self.current.hints:
            self.notify("No hints for this one. You've got this.")
            return
        core.reveal_hint(self.current)
        self.render_hints()
        self.query_one("#bottom", TabbedContent).active = "tab-hints"

    def action_solution(self) -> None:
        q = self.current
        if q is None:
            return
        if core.is_solved(core.load_progress(), q):
            self.push_screen(SolutionScreen(q))
            return

        def answer(ok: bool) -> None:
            if ok:
                core.mark_solution_viewed(q)
                self.push_screen(SolutionScreen(q))
        self.push_screen(ConfirmScreen(f"You haven't solved Q{q.code} yet.\nReveal the solution anyway?",
                                       yes="Reveal"), answer)

    def action_next(self) -> None:
        progress = core.load_progress()
        ids = [q.id for q in self.questions]
        start = ids.index(self.current.id) + 1 if self.current else 0
        for q in self.questions[start:] + self.questions[:start]:
            if not core.is_solved(progress, q):
                self.load_question(q)
                self.active_editor().focus()
                return
        self.notify("Every question is solved. 🎉", title="Done")

    def action_cancel(self) -> None:
        if self.busy:
            self.cancel_worker()

    @work(thread=True, group="cancel")
    def cancel_worker(self) -> None:
        try:
            core.cancel_all()
            self.call_from_thread(self.notify, "Cancel requested.")
        except DojoError as e:
            self.call_from_thread(self.notify, str(e), severity="error")

    def action_help(self) -> None:
        self.push_screen(HelpScreen())

    # --------------------------------------------------------------- database
    @work(thread=True, exclusive=True, group="meta")
    def check_database(self) -> None:
        meta = core.db_meta()
        self.call_from_thread(self.database_checked, meta)

    def database_checked(self, meta: Dict[str, str]) -> None:
        self.meta = meta
        self.refresh_question_list()
        self.set_status(f"answers/{self.current.code}.sql" if self.current else "")
        if meta:
            self.load_schema()
            q = self.current
            if q is not None and (q.engine == "duckdb" or q.setup_path or q.lake_paths):
                self.ensure_lab(q)
        else:
            self.push_screen(SetupScreen(), self.setup_done)

    def setup_done(self, ok: bool) -> None:
        if ok:
            core.CACHE_DIR.mkdir(exist_ok=True)
            self.check_database()

    @work(thread=True, exclusive=True, group="schema")
    def load_schema(self) -> None:
        try:
            cols = core.schema()
        except DojoError:
            return
        self.call_from_thread(self.show_schema, cols)

    def show_schema(self, cols) -> None:
        tree = self.query_one("#schema", Tree)
        tree.clear()
        nodes = {}
        for table, column, typ in cols:
            if table not in nodes:
                nodes[table] = tree.root.add(Text(table, style="bold"), data={"table": table}, expand=False)
            nodes[table].add_leaf(Text.assemble(column, "  ", (typ, "dim")),
                                  data={"table": table, "column": column, "type": typ})
        tree.root.expand()

    def get_system_commands(self, screen):
        yield from super().get_system_commands(screen)
        yield SystemCommand("Start database", "Start Postgres in Docker and generate data if needed",
                            lambda: self.push_screen(SetupScreen(), self.setup_done))
        yield SystemCommand("Regenerate dataset", "Rebuild the data at a different scale",
                            lambda: self.push_screen(SetupScreen(regenerate=True), self.setup_done))
        yield SystemCommand("Reset objects I created", "Drop your indexes, views and tables",
                            self.reset_objects)
        yield SystemCommand("Build the data lake (Level 8)", "Export the dataset into lake/ for DuckDB",
                            lambda: self.ensure_lab(self.current) if self.current else None)
        yield SystemCommand("Rebuild the data lake", "Re-export lake/raw from the current database (wipes lake/)",
                            self.confirm_rebuild_lake)
        if self.current is not None and (self.current.setup_path or self.current.lake_paths):
            yield SystemCommand("Reset this lab", f"Rebuild the lab objects for Q{self.current.code}",
                                lambda: self.ensure_lab(self.current, force=True))
        if self.current is not None:
            sessions = dict(core.parallel_step(st) for st in self.current.plan if st.startswith("parallel:"))
            for step in self.current.steps:
                how = f"in {sessions[step]} concurrent sessions" if step in sessions else "(lands data)"
                yield SystemCommand(f"Lab step: {step}", f"Run {step}.sql for Q{self.current.code} {how}",
                                    lambda step=step: self.lab_step(self.current, step))
        yield SystemCommand("Explain (plan only)", "EXPLAIN without running the query",
                            lambda: self.action_explain(analyze=False))
        yield SystemCommand("Next unsolved question", "Jump ahead", self.action_next)
        yield SystemCommand("Show solution", "Reference solution and explanation", self.action_solution)
        yield SystemCommand("Reload questions", "Pick up edits in questions/", self.reload_questions)

    def confirm_rebuild_lake(self) -> None:
        def answer(ok: bool) -> None:
            if ok:
                self.rebuild_lake()
        self.push_screen(ConfirmScreen("Rebuild the data lake?\n\nThis deletes everything in lake/, "
                                       "including your silver/ and gold/ files.", yes="Rebuild"), answer)

    def reload_questions(self) -> None:
        self.questions = core.load_questions()
        self.refresh_question_list()
        if self.current:
            self.load_question(core.get_question(self.current.id))

    def reset_objects(self) -> None:
        objs = core.user_objects()
        if not objs:
            self.notify("Nothing to reset: only the baseline indexes exist.")
            return
        listing = "\n".join(f"  {kind} {name}" for kind, name, _ in objs)

        def answer(ok: bool) -> None:
            if ok:
                core.reset_objects(objs)
                self.notify("Back to baseline.")
                self.load_schema()
        self.push_screen(ConfirmScreen(f"Drop these objects?\n\n{listing}", yes="Drop"), answer)

    async def action_quit(self) -> None:
        self.save_answer()
        self.save_scratch()
        self.exit()


def run() -> None:
    DojoApp().run()
