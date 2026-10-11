# SQL Dojo

**Graded SQL practice on millions of rows, on your own machine: from `GROUP BY` to query tuning,
migrations, pipelines and race conditions.**

SQL Dojo is 58 graded SQL problems in nine levels. You solve them in a terminal IDE against a local
Postgres loaded with a realistic, messy e-commerce dataset (5.8M events at the default size, 58M if
you want). It starts with joins and window functions, then moves on to slow queries with a time
target, safe migrations, idempotent loads, a DuckDB data lake and code that runs in four sessions
at once.

It's not a first SQL course: you should be comfortable with `SELECT`, `WHERE` and `JOIN`. There's
no account to create, and your work stays on your machine.

![The SQL Dojo terminal IDE](docs/screenshot.png)

- **Big, realistic data.** Three years of a fictional marketplace: customers, catalogue and price
  history, orders, a clickstream, reviews and subscriptions. It has growth, seasonality, long tails,
  time zones, and deliberate dirt: duplicates, NULLs, bots, lost events.
  [See the schema →](docs/SCHEMA.md)
- **Graded answers.** For query questions, your result set is compared with a reference answer,
  row by row. When it's wrong you see which rows are missing or extra.
- **Performance questions** come with a slow query and a time target. Index it, rewrite it or
  precompute it until it's fast enough. That's where large data really teaches you something.
- **Labs that check what you did.** From Level 6, many answers aren't a result set. The checker
  runs your migration as a restricted role and rolls it back, replays your load script twice per
  batch to prove retries are harmless, or runs your code in four sessions at once to catch lost
  updates and deadlocks.
- **Explanations.** Every reference solution explains the *why*: the trap, the alternative
  approaches, what the planner does.
- **Everything runs locally.** Docker and Python 3.10+. The data is generated inside Postgres in
  about a minute: no dataset to download, deterministic, any size you like.

## Quick start

You need Docker (running, with `docker compose`) and Python 3.10 or newer. You don't need Postgres
or psql on your machine.

```bash
git clone https://github.com/tjb/sql-dojo.git && cd sql-dojo
./dojo
```

The first run installs the terminal UI (and DuckDB, for Level 8) into `./.venv`, starts Postgres 17
in Docker and generates the dataset. Pick a scale: 1 is a good start. The whole first run then
takes a few minutes and needs about 3 GB of free disk (the Postgres image, the data and temporary
space while generating). Bigger scales need free space *inside Docker*: about 12 GB for scale 10. Docker
Desktop has its own disk limit, separate from your computer's free space (*Settings → Resources →
Advanced*); `./dojo` checks before generating.

- **macOS:** the built-in `python3` is 3.9, which is too old for the terminal UI. Install a newer
  one (`brew install python`, or python.org) and run the first launch with it, for example
  `python3.13 dojo`. After that, `./dojo` uses `./.venv`.
- **Linux:** your user must be able to run `docker` without `sudo`. Otherwise `./dojo` reports that
  Docker isn't running.
- **Windows:** untested. Native Windows won't work; WSL 2 with Docker Desktop's WSL integration
  should. Clone inside WSL (`~/sql-dojo`, not `/mnt/c/...`).

In the IDE:

| Key | |
|---|---|
| `Ctrl+R` / `F5` | Run your query and show the result |
| `Ctrl+T` / `F6` | Check it against the reference answer |
| `Ctrl+E` / `F7` | `EXPLAIN (ANALYZE, BUFFERS)` your query |
| `Ctrl+G` / `F8` | Next hint |
| `Ctrl+O` / `F9` | Reference solution and explanation (asks first if you haven't solved it) |
| `Ctrl+N` | Next unsolved question |
| `Esc` | Cancel a running query |
| `Ctrl+P` | Command palette: start/regenerate the database, reset indexes, explain without running, ... |
| `F1` | Help |
| `Ctrl+Q` | Quit |

**Rather use your own editor or SQL client?** Answers are plain files (`answers/007.sql`): edit
them anywhere and grade them with `./dojo check 7`. See [the plain CLI](#the-plain-cli) for the
commands and how to connect your own client.

**It picks up where you left off.** Each launch reopens the question you were on, with your
draft (answers autosave to `answers/NNN.sql`). If you'd finished it, you get the next unsolved
question instead. `./dojo today` does the same from the shell. Your progress (attempts, hints,
solve dates, best times) is in `answers/progress.json`. To keep your answers on GitHub, commit
`answers/` and push it to a repo of your own (a fork, or a private copy): it's your SQL portfolio.

For performance questions, open a second terminal with `./dojo psql` to create indexes or
materialized views, then check again.

## The curriculum

| Level | Questions |
|---|---|
| **1 · Foundations** | 1 Monthly revenue · 2 Customers who never ordered · 3 NULL traps · 4 Duplicate accounts · 5 Order status pivot · 6 Average order value by country |
| **2 · Window functions** | 7 Top 3 products per category · 8 Running total for December · 9 Moving average with gaps · 10 Time to second order · 11 MoM and YoY growth · 12 Gateway products · 13 Revenue deciles |
| **3 · Analytics patterns** | 14 Sessionization · 15 Ordered conversion funnel · 16 Cohort retention · 17 Longest daily streak · 18 Category tree rollup · 19 Biggest referral trees · 20 Bought together · 21 Subscription MRR · 22 Overlapping subscriptions · 23 Delivery time percentiles · 24 Subtotals with CUBE |
| **4 · Advanced SQL** | 25 Prices as of a date · 26 Latest orders with LATERAL · 27 Tracking loss (JSONB) · 28 Duplicate events · 29 What time do people buy? |
| **5 · Performance** ⏱ | 30 Latest activity per user · 31 Make it sargable · 32 Precompute monthly actives · 33 Events before purchase |
| **6 · Production Postgres** ⚗ | 34 TRUNCATE blast radius · 35 Migration without TRUNCATE · 36 DELETE vs TRUNCATE on disk · 37 Fail fast with lock_timeout · 38 Privilege audit · 39 Make updates HOT |
| **7 · Modeling & ELT** ⚗ | 40 Bulk load with COPY · 41 Data quality tests · 42 Build a star schema · 43 Sync a catalog with MERGE · 44 Slowly changing dimension · 45 Late-arriving data · 46 Partitioning and retention |
| **8 · Lake & columnar** 🦆 | 47 Query the landing zone · 48 CSV to partitioned Parquet · 49 Row store vs column store · 50 Partition pruning · 51 Sort for zone maps · 52 Schema drift · 53 Overwrite one partition |
| **9 · Events & concurrency** ⚗ | 54 An audit trail · 55 A rollup that keeps itself up to date · 56 An idempotent consumer · 57 A job queue with SKIP LOCKED · 58 Concurrent transfers |

⏱ performance questions with a time target · ⚗ labs: the checker inspects your database ·
🦆 runs in DuckDB

Levels 1–5 cover join fan-out, anti-joins, three-valued logic, `FILTER`, window frames, gap
filling, gaps-and-islands, recursive CTEs, closure tables, `LATERAL`, `GROUPING SETS`, as-of joins,
interval overlap, JSONB, time zones, B-tree vs BRIN, sargability, composite index order,
materialized views, and reading `EXPLAIN ANALYZE`.

**Levels 6–9 are mostly labs.** Instead of comparing a result set, the checker inspects what you
did to the database:

- **6 · Production Postgres.** Your migration runs as a restricted role inside a transaction that
  is rolled back after checking: for example, rewrite a migration that uses `TRUNCATE` for a role
  that isn't allowed to. Other labs let you change the database however you like, then check file
  nodes, sizes, role settings and HOT-update ratios. They cover `TRUNCATE` vs `DELETE` (privileges,
  locks, MVCC, what happens on disk), lock queues and `lock_timeout`, role inheritance, VACUUM and
  fillfactor.
- **7 · Modeling & ELT.** Your answer is a load script, and the checker plays the outside world.
  It resets the lab, lands batch 1, runs your load **twice** (retries must be harmless), lands
  batch 2, and so on, then compares your tables with the truth. You build a star schema, load a
  messy CSV with `COPY`, sync a catalog with `MERGE` and soft deletes, keep a type-2 slowly changing
  dimension, handle late-arriving data and manage retention with partitions.
- **8 · Lake & columnar.** `./dojo lake` exports the dataset as files: a gzipped CSV per day and a
  partner's JSON feed whose schema drifts. Your queries run in [DuckDB](https://duckdb.org),
  straight over the files. You build a Parquet silver layer and see why columnar formats win at
  analytics (the same MAU query: seconds in Postgres, milliseconds here). The grader counts **how
  many files your query opens**, so partition pruning is graded for real. The lake lives on your
  disk, not inside Docker: about 0.1 GB per unit of scale.
- **9 · Events & concurrency.** Four of the five labs run your code in **four sessions at once**.
  Code that is correct one call at a time breaks there, and the checks show how: lost updates,
  double-processed jobs, a wallet at −50.84, `deadlock detected`. You write an audit trail that
  even catches `TRUNCATE`, a rollup that keeps itself up to date, an idempotent consumer for an
  at-least-once broker, a `SKIP LOCKED` job queue, and transfers that neither overdraw nor
  deadlock.

While you work on a Level 7 or 9 lab, you can run the checker's steps yourself: *Lab step* in the
command palette, or `./dojo lab-step 45 batch_1`.

Adding your own questions takes a markdown file and a SQL file: see [CONTRIBUTING.md](CONTRIBUTING.md).

## The plain CLI

Everything the TUI does is also a command. The commands use only Python's standard library (3.8 is
enough). Level 8 is the exception: it needs Python 3.10 or newer and installs DuckDB into `./.venv`
the first time it needs it:

```
./dojo up [--scale 1]       start Postgres; generate data on first run
./dojo generate --scale 10  regenerate at another size (bigger = more interesting plans)
./dojo today                pick up where you left off (or the next unsolved question)
./dojo start 7              open question 7 and create answers/007.sql
./dojo show 7               print a question
./dojo run 7                run your answer, print the result
./dojo check 7              grade it
./dojo hint 7               reveal one more hint
./dojo explain 7            EXPLAIN (ANALYZE, BUFFERS)
./dojo solution 7           reference solution + explanation
./dojo list | status        the curriculum / your progress and the database
./dojo psql                 interactive psql
./dojo reset                drop the indexes, views and tables you created
./dojo lab-reset 36         rebuild a lab's objects and start it over
./dojo lab-step 45 batch_1  run one step of a lab's checker by hand (or: lab-step 57 worker)
./dojo lake [--rebuild]     Level 8: export the dataset into lake/ for DuckDB
./dojo down | destroy       stop the container / delete it and its data
```

Prefer your own client (DBeaver, DataGrip, TablePlus, VS Code)? Connect to
`postgresql://dojo:dojo@localhost:5433/dojo`. It uses port 5433 so it won't clash with a local
Postgres. If 5433 is taken, put `DOJO_PORT=5434` in a `.env` file next to `docker-compose.yml`, so
every command uses the same port. The dojo itself talks to Postgres through Docker, so only your
own client cares about the port.

To use a Postgres you run yourself instead of Docker, set
`DOJO_PSQL="psql postgresql://user:pass@host/db"` (Postgres 17 or newer, as a superuser, with the
contrib extensions) and run `./dojo generate`.

## How grading works

- Your file must contain **one** query. Comments are fine.
- The expected result comes from the reference query (or, for performance questions, from the
  original slow query) and is cached in `.dojo-cache/` per dataset.
- Numbers are compared after rounding to the precision the question asks for (12.30 = 12.3).
  `NULL` is not the same as `''`.
- Row order only matters when the question says the order matters. Column names don't matter;
  column order does.
- Performance questions run your query 3 times and take the best time. Some targets scale with the
  dataset size (`× scale`).
- Labs are graded by `check.sql`, which returns one row per check. Their objects live in their own
  schemas (`lab`, `partner`, `mart`, `stream`, ...) and a few roles (`app_migrator`, `analyst`,
  ...). Regenerating the data rebuilds them on demand.

## Optional: a daily question as a GitHub issue

Off by default, and it runs in your own copy of the repo on GitHub. In a fork, first enable
workflows (*Actions* tab) and Issues (*Settings → General → Features*).

The [`Daily SQL question`](.github/workflows/daily-question.yml) workflow can open one GitHub issue
a day with the next question you haven't solved or been sent yet (the problem, collapsible hints,
the commands to start) and @mention you, so GitHub emails it. To switch it on, uncomment the two
`schedule` lines in that file (the time is UTC) and push to your default branch. *Actions → Daily
SQL question → Run workflow* sends one immediately. Each run also closes the issues of questions
you've solved, based on the `answers/progress.json` you've pushed.

## Other places to practise

Most SQL practice runs on small tables in a browser and checks one result set. SQL Dojo is for the
step after that: data big enough that the query plan matters, and labs that check what your code
does to a database. I haven't found another tool that does both. These go well with it:

- **[DataLemur](https://datalemur.com)**, **[StrataScratch](https://www.stratascratch.com)**,
  **[LeetCode SQL 50](https://leetcode.com/studyplan/top-sql-50/)**: interview-style questions in
  the browser (small data).
- **[pgexercises.com](https://pgexercises.com)**: Postgres-specific exercises.
- **[Use The Index, Luke](https://use-the-index-luke.com)**: the best free book on indexing and
  query performance. Read it alongside Level 5.
- **[PostgreSQL: Concurrency Control](https://www.postgresql.org/docs/current/mvcc.html)**: MVCC,
  isolation levels and explicit locking, from the manual. Read it alongside Levels 6 and 9.
- **[BigQuery public datasets](https://cloud.google.com/bigquery/public-data)**: real big data
  (GitHub, Stack Overflow, NYC taxis), 1 TB of free queries a month.
- **[DuckDB](https://duckdb.org)** (used in Level 8): also try the Postgres-level questions in it
  (`ATTACH 'host=localhost port=5433 dbname=dojo user=dojo password=dojo' AS pg (TYPE postgres);
  USE pg;`). DuckDB downloads its postgres extension the first time.

## What could come next

More labs: `SERIALIZABLE` and write skew (two on-call engineers both going off call), sequence
gaps and the outbox relay that skips rows committed out of order, `CREATE INDEX CONCURRENTLY` and
invalid indexes, `NOT VALID` constraints, change data capture from the WAL with logical decoding
(needs `wal_level=logical`), replication lag, `pg_stat_statements` triage. Want one of these, or
have a better idea? Open an issue. Adding one yourself is a `question.md`, a `setup.sql`, a
`check.sql` and a solution: see [CONTRIBUTING.md](CONTRIBUTING.md).
