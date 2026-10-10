# SQL Dojo

**Learn SQL in depth by solving real analytics problems against millions of rows, on your own machine.**

SQL Dojo gives you a realistic, messy e-commerce warehouse in a local Postgres (5.8M events at the
default size, 58M if you want), a curriculum of graded questions from `GROUP BY` to query tuning,
and a terminal IDE to work through them. Open it, and it picks up where you left off.

![The SQL Dojo terminal IDE](docs/screenshot.png)

- **Big, realistic data.** Three years of a fictional marketplace: customers, catalogue and price
  history, orders, a clickstream, reviews and subscriptions. It has growth, seasonality, long tails,
  time zones, and deliberate dirt: duplicates, NULLs, bots, lost events.
  [See the schema →](docs/SCHEMA.md)
- **Graded answers.** Your result set is compared with a reference answer, row by row. When it's
  wrong you see which rows are missing or extra.
- **Performance questions** come with a slow query and a time target. Index it, rewrite it or
  precompute it until it's fast enough. That's where large data really teaches you something.
- **Explanations.** Every reference solution explains the *why*: the trap, the alternative
  approaches, what the planner does.
- **Everything runs locally.** Docker plus Python 3.8+. The data is generated inside Postgres in
  about a minute: no downloads, deterministic, any size you like.

## Quick start

```bash
git clone <this repo> sql-dojo && cd sql-dojo
./dojo
```

The first run installs the terminal UI (and DuckDB, for Level 8) into `./.venv`, starts Postgres 17 in Docker and generates
the dataset (pick a scale; 1 is a good start). Bigger scales need free space *inside Docker*: about
12 GB for scale 10. Docker Desktop has its own disk limit, separate from your computer's free space
(*Settings → Resources → Advanced*); `./dojo` checks before generating. Then:

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

**It picks up where you left off.** Each launch reopens the question you were on, with your
draft (answers autosave to `answers/NNN.sql`). If you'd finished it, you get the next unsolved
question instead. `./dojo today` does the same from the shell. Your progress (attempts, hints,
solve dates, best times) is in `answers/progress.json`. Commit `answers/`: it's your SQL portfolio.

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

Along the way: join fan-out, anti-joins, three-valued logic, `FILTER`, window frames, gap filling,
gaps-and-islands, recursive CTEs, closure tables, `LATERAL`, `GROUPING SETS`, as-of joins, interval
overlap, JSONB, time zones, B-tree vs BRIN, sargability, composite index order, materialized views,
and reading `EXPLAIN ANALYZE`.

**Level 6 is labs** (⚗) about running Postgres in production rather than querying it. Instead of
comparing a result set, the checker inspects what you did to the database:
- **Script labs** run your migration as a restricted role inside a transaction, inspect the result
  and roll back. Example: rewrite a migration that uses `TRUNCATE` for a role that isn't allowed to.
- **State labs** let you change the database however you like (the editor runs any statements),
  then verify things like file nodes, sizes, role settings and HOT-update ratios.

They cover `TRUNCATE` vs `DELETE` (privileges, locks, MVCC, what happens on disk), foreign-key
cascades, lock queues and `lock_timeout`, role inheritance, VACUUM, fillfactor and HOT updates.

**Level 7 is data engineering in SQL.** It adds *pipeline labs*: your answer is a load script, and
the checker plays the outside world. It resets the lab, lands batch 1, runs your load **twice**
(retries must be harmless), lands batch 2, runs it twice again, and so on, then compares your
tables with the truth. You build a star schema, bulk-load a messy CSV with `COPY`, sync a
supplier catalogue with `MERGE` (soft deletes included), keep a type-2 slowly changing
dimension, maintain an incremental rollup while late data arrives, and manage retention with
partitions. While developing, run the steps yourself: *Lab step* in the command palette, or
`./dojo lab-step 45 batch_1`.

**Level 8 leaves Postgres for the data lake.** `./dojo lake` (or opening a Level 8 question)
exports the dataset as files into `lake/raw/`: one gzipped CSV per day, a partner's JSON feed,
dimension tables. Your queries then run in [DuckDB](https://duckdb.org), in-process and straight
over the files. You build a Parquet silver layer, then see why columnar formats win at analytics
(the same MAU query: seconds in Postgres, milliseconds here) and why file layout matters. The
grader also counts **how many files your query opens**, so partition pruning is graded for real.
You also handle schema drift, sort data for zone maps, and rewrite one partition without
touching the others, which is the gap Iceberg and Delta Lake exist to close. The lake lives on
your disk (not inside Docker): about 0.1 GB per unit of scale for raw, plus whatever you build.

Adding your own questions takes a markdown file and a SQL file: see [CONTRIBUTING.md](CONTRIBUTING.md).

## Optional: a daily question by email

Off by default. If you'd like a nudge, the [`Daily SQL question`](.github/workflows/daily-question.yml)
workflow can open one GitHub issue a day with the next question you haven't solved or been sent
yet (the problem, collapsible hints, the commands to start) and @mention you, so GitHub emails it.
To switch it on, uncomment the two `schedule` lines in that file (the time is UTC) and push to your
default branch. *Actions → Daily SQL question → Run workflow* sends one immediately. Each run
also closes the issues of questions you've solved, based on the `answers/progress.json` you've pushed.

## The plain CLI

Everything the TUI does is also a command, using only Python's standard library:

```
./dojo up [--scale 1]       start Postgres; generate data on first run
./dojo generate --scale 10  regenerate at another size (bigger = more interesting plans)
./dojo today                pick up where you left off (or the next unsolved question)
./dojo run 7                run your answer, print the result
./dojo check 7              grade it
./dojo hint 7               reveal one more hint
./dojo explain 7            EXPLAIN (ANALYZE, BUFFERS)
./dojo solution 7           reference solution + explanation
./dojo list | status        the curriculum / your progress and the database
./dojo psql                 interactive psql
./dojo reset                drop the indexes, views and tables you created
./dojo lab-reset 36         rebuild a lab's objects and start it over
./dojo lab-step 45 batch_1  pipeline labs: land the next batch of data by hand
./dojo lake [--rebuild]     Level 8: export the dataset into lake/ for DuckDB
./dojo down | destroy       stop the container / delete it and its data
```

Prefer your own client (DBeaver, DataGrip, TablePlus, VS Code)? Connect to
`postgresql://dojo:dojo@localhost:5433/dojo` (port 5433, so it won't clash with a local Postgres;
change it with `DOJO_PORT`). To use a Postgres you run yourself instead of Docker, set
`DOJO_PSQL="psql postgresql://user:pass@host/db"` (Postgres 16 or newer, as a superuser) and run
`./dojo generate`.

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

## Other places to practise

Nothing else I know of combines big local data with graded questions and a daily email, but these
are excellent complements:

- **[DataLemur](https://datalemur.com)**, **[StrataScratch](https://www.stratascratch.com)**,
  **[LeetCode SQL 50](https://leetcode.com/studyplan/top-sql-50/)**: interview-style questions in
  the browser (small data).
- **[pgexercises.com](https://pgexercises.com)**: Postgres-specific exercises.
- **[Use The Index, Luke](https://use-the-index-luke.com)**: the best free book on indexing and
  query performance. Read it alongside Level 5.
- **[BigQuery public datasets](https://cloud.google.com/bigquery/public-data)**: real big data
  (GitHub, Stack Overflow, NYC taxis), 1 TB of free queries a month.
- **[DuckDB](https://duckdb.org)** (used in Level 8): also try the Postgres-level questions in it
  (`ATTACH 'host=localhost port=5433 dbname=dojo user=dojo password=dojo' AS pg (TYPE postgres);`).

## Ideas for more

More Production Postgres labs: isolation levels and anomalies (lost updates, write skew),
deadlocks, `CREATE INDEX CONCURRENTLY` and invalid indexes, `NOT VALID` constraints, table
partitioning and partition pruning, sequences and gaps, replication lag, `pg_stat_statements`
triage. Adding one is a `question.md`, a `setup.sql`, a `check.sql` and a solution: see
[CONTRIBUTING.md](CONTRIBUTING.md).
