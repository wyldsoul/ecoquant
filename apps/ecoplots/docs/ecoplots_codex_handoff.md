# ECOplots Codex Handoff

This document summarizes the ECOplots work completed in the Codex desktop
chat so the VS Code Codex agent on the Linux server can continue from the same
context.

## Project Goal

Modernize the old Shiny ECOplots app so it can run on the `tx.eco` Linux
server as a Docker-deployed app. The app should use app-ready `.rds` files
built from daily result CSVs, avoid expensive user-triggered computation, and
support automated updates after the upstream stock run finishes.

Target Linux deployment path:

```sh
/home/bbotson/applications/ecoquant/apps/ecoplots
```

Expected app URL after deployment:

```text
https://app.ecoquantinsight.com/
```

## Data Flow

The upstream database/server creates daily CSV files and rsyncs them into the
repo-level `results/` directory.

Input file patterns:

```text
results/results_stock_xtest_YYYY-MM-DD.csv
results/results_etf_xtest_YYYY-MM-DD.csv
```

The Shiny app does not read CSVs directly. It reads app-ready `.rds` files from
`EcoPlots/`.

The builder is:

```sh
Rscript r/build_ecoplots_rds.R
```

The daily updater wrapper is:

```sh
Rscript r/update_ecoplots_rds.R
```

`r/update_ecoplots_rds.R` calls:

```sh
Rscript r/build_ecoplots_rds.R --mode=incremental
```

## Builder Behavior

Main script:

```text
r/build_ecoplots_rds.R
```

Important arguments:

```sh
--results-dir=...
--output-dir=...
--history-days=365
--volume-quantile=0.3333333
--suffix=_1y
--skip-loess=true|false
--mode=full|incremental
```

Default behavior:

- Reads the latest 365 calendar days of result CSVs.
- Writes app-ready files to `EcoPlots/*_1y.rds`.
- Writes `EcoPlots/manifest_1y.csv`.
- Precomputes loess data and crossover files outside Shiny.
- Builds EQI Focus outputs from the stock history.

Incremental behavior:

- Reads existing `stock_history_1y.rds` and `etf_history_1y.rds`.
- Finds result CSVs newer than the latest date in each history.
- Appends only new rows.
- Deduplicates by `date,symbol`.
- Trims the rolling one-year window.
- Rebuilds derived app-ready RDS files only when new stock or ETF files exist.

Important operational nuance:

- Incremental ingest avoids rereading all CSVs.
- Derived outputs are still rebuilt from the updated one-year history.
- This is expected because loess and crossover outputs are endpoint-sensitive.
- Loess is not naturally append-only; adding a new date can affect recent
  smoothed values and all latest crossover calculations.

## Current RDS Outputs

Main app outputs:

```text
stock_history_1y.rds
etf_history_1y.rds
xmeans_1y.rds
ss_melt_1y.rds
indmeans_1y.rds
etf_melt_1y.rds
loessdata_1y.rds
loessdata_etf_1y.rds
```

Stock interaction outputs:

```text
x5i_1y.rds
x9i_1y.rds
x14i_1y.rds
x21i_1y.rds
x30i_1y.rds
sumi_1y.rds
```

Stock crossover outputs:

```text
x9x5_1y.rds
x14x9_1y.rds
x21x14_1y.rds
x30x21_1y.rds
x30x14_1y.rds
```

ETF crossover outputs:

```text
etf9x5_1y.rds
etf14x9_1y.rds
etf21x14_1y.rds
etf30x21_1y.rds
etf30x14_1y.rds
```

EQI Focus outputs:

```text
eqi_top50_rank_1y.rds
eqi_top20_changes_1y.rds
eqi_top50_tenure_1y.rds
eqi_vol_top50_1y.rds
eqi_plot_lr_1y.rds
eqi_topN_events_vol_1y.rds
```

## EQI Focus Logic

The EQI Focus feature was recreated from the SAS/PDF workflow and moved into
the Shiny app instead of rendering static PDFs.

Generated tables:

- Latest EQI Top 50 rank.
- Top 20 promotions/demotions/entries/exits/flat names.
- Top 50 tenure and return since first Top 50 appearance within the lookback
  window.
- Volatility Top 50.
- Rank history for Top 50 symbols.
- Rolling LR chart data for Top 20 chart-pack symbols.

Feature calculations include:

- `delta_x21slope`
- `term_structure`
- 20-day price position
- `slope_edge`
- 1-day returns
- 20-day realized volatility
- average absolute return
- max absolute return
- 3% and 5% hit counts
- volatility swing score
- volume-weighted EQI score

The app hides low-level diagnostic fields from the main displayed tables because
the user feedback was that fields such as `SlopeEdge`, `delta_x21slope`,
`term_structure`, and `price_pos_20` were not useful in the user-facing view.

Important correction made:

- The PDF chart label says rolling LR is computed from `x1..x30` values.
- The initial implementation accidentally used `x1slope..x30slope`.
- This was corrected in `r/build_ecoplots_rds.R`.
- `eqi_plot_lr_1y.rds` now uses `x1..x30` values and stores them as `x_value`.

## EQI Focus App UI

Main app:

```text
EcoPlots/app.R
```

Changes made:

- `EQI Focus` is the first sidebar tab.
- Added a ticker group filter.
- Added ticker search for any ticker in `stock_history_1y.rds`.
- Added server-side selectize for large ticker lists.
- Added ticker summary boxes:
  - latest EQI rank
  - EQI score
  - latest price
  - approximate 90-day return
- Added ticker panel chart:
  - 90 trading days
  - rolling endpoint linear regression of `x1..x30`
  - optional price overlay
- Added ticker Top 50 rank-history table.

Ticker groups:

```text
All tickers
EQI Top 20
EQI Top 50
Top 20 Changes
Promotions
Entries
Demotions
Exits
Volatility Top 50
Sector: <sector name>
```

The app still keeps legacy tabs:

- Stocks Interaction
- Stocks crossovers
- ETF crossovers
- ETF
- X
- X Groups
- Stocks visualations

## Fixes Made To `EcoPlots/app.R`

Data loading:

- Added `read_app_rds()` so the app prefers `_1y.rds` files and falls back to
  legacy `.rds` names.
- Large stock and ETF loess data are converted to `data.table`.
- Keyed `loessdata` by common filter fields.
- Smaller tables are loaded as data frames to avoid accidental `data.table`
  join behavior.

Bug fixes:

- Fixed ETF tab `data.table` join/subset issue by converting intermediate
  tables to data frames.
- Fixed X tab color naming issue where color names did not match selected
  variables.
- Fixed X Groups color naming against `ss_melt$variable`.
- Fixed ETF date selector to use ETF dates.
- Fixed volume slider default.
- Corrected old ticker groups:
  - `fang = META, AMZN, NFLX, GOOGL`
  - `tech = AAPL, MSFT, INTC, BABA`
- Fixed EQI price overlay plot error by explicitly mapping both `x = date` and
  `y = price_scaled`.

## Fixes Made To `r/build_ecoplots_rds.R`

Major builder behavior:

- Full and incremental modes.
- App-ready RDS outputs.
- EQI output generation.
- Rolling one-year window.
- Manifest generation.

Important robustness fixes:

- Character fields are trimmed.
- Blank character fields become `NA`.
- Rows missing `symbol` are dropped.
- Missing `ticker` is filled from `symbol`.
- Missing `name` is filled from `symbol`.
- Missing `sector` becomes `"Unknown"`.
- Missing `industry` becomes `"Unknown"`.
- Volume columns are forced numeric to avoid integer64/corruption issues.
- Loess prediction is wrapped in `tryCatch()` so one bad ticker/timeframe series
  returns `NA` loess values instead of aborting the whole rebuild.

Reason for the loess patch:

- After adding stock files for 2026-05-07, 2026-05-08, and 2026-05-11, the full
  loess rebuild failed in `predict.loess()` with:

```text
NA/NaN/Inf in foreign function call
```

- The new files had no missing `symbol` or `ticker`, but did have missing
  `sector` and `industry` values for about 123 rows per new date.
- The defensive normalization and loess prediction guard fixed the rebuild.

## Current Rebuild State From Last Desktop Run

Last successful full build command:

```sh
Rscript r/build_ecoplots_rds.R
```

Last successful full build produced:

```text
stock_history_1y.rds       515,108 rows, through 2026-05-11
etf_history_1y.rds          25,939 rows, through 2026-05-06
loessdata_1y.rds         6,005,844 rows, through 2026-05-11
loessdata_etf_1y.rds       466,902 rows
eqi_top50_rank_1y.rds           50 rows, through 2026-05-11
eqi_top20_changes_1y.rds        26 rows, through 2026-05-11
eqi_plot_lr_1y.rds          36,360 rows, through 2026-05-11
eqi_topN_events_vol_1y.rds  10,100 rows, through 2026-05-11
```

After the full build, this command exited cleanly:

```sh
Rscript r/build_ecoplots_rds.R --mode=incremental
```

Output:

```text
No new stock files after 2026-05-11
No new etf files after 2026-05-06
No new stock or ETF files. Existing app RDS files are current through 2026-05-11.
```

Note:

- There were no ETF CSVs newer than 2026-05-06 at that point.
- The global manifest `latest_date` may show the stock latest date even though
  ETF data is older. Check individual RDS max dates when needed.

## Deployment Files Added

Docker/deploy files:

```text
Dockerfile
compose.yaml
.dockerignore
deploy/shiny-server.conf
docs/docker_deploy_tx.md
docs/ecoplots_rds_workflow.md
```

Docker intent:

- Use `rocker/shiny`.
- Install required R packages.
- Run Shiny Server on port `3838`.
- Mount `./EcoPlots` into `/srv/shiny-server/EcoPlots`.
- Map Shiny Server logs to the host.

Useful deploy commands:

```sh
cd /home/bbotson/applications/ecoquant/apps/ecoplots
docker compose build
docker compose up -d
docker compose logs -f ecoplots
```

Legacy Compose equivalent:

```sh
docker-compose build
docker-compose up -d
docker-compose logs -f ecoplots
```

Host log path:

```text
/home/bbotson/applications/ecoquant/apps/ecoplots/logs/shiny-server
```

Create once:

```sh
mkdir -p logs/shiny-server
chmod 777 logs/shiny-server
```

View logs:

```sh
tail -f logs/shiny-server/*.log
```

## Daily Update Workflow

Expected server workflow:

1. Upstream server finishes daily stock/database run.
2. Upstream server rsyncs new `results_*_xtest_YYYY-MM-DD.csv` files to
   `tx.eco`.
3. Cron or manual command runs:

```sh
cd /home/bbotson/applications/ecoquant/apps/ecoplots
Rscript r/update_ecoplots_rds.R >> logs/ecoplots_update.log 2>&1
docker compose restart ecoplots
```

Legacy Compose:

```sh
docker-compose restart ecoplots
```

Example cron:

```cron
15 19 * * 1-5 cd /home/bbotson/applications/ecoquant/apps/ecoplots && Rscript r/update_ecoplots_rds.R >> logs/ecoplots_update.log 2>&1 && docker-compose restart ecoplots
```

Possible future improvement:

- Have incremental mode write a status file or return a distinct code when no
  rebuild occurred.
- Then only restart the Shiny container when app RDS files actually changed.

## Backup Script

Added:

```text
scripts/backup_code_docs.sh
```

Purpose:

- Back up only code/config/docs.
- Exclude generated `.csv`, `.rds`, PDFs, images, logs, archives, databases,
  and `.git`.

Default backup path:

```sh
~/eqi_code_backups
```

Usage:

```sh
./scripts/backup_code_docs.sh
```

Or:

```sh
./scripts/backup_code_docs.sh "/path/to/backup/folder"
```

The script was patched to normalize copied macOS Terminal paths with escaped
spaces/tildes.

`archive/` is excluded.

## Code Review Notes

Review findings that were discussed but not fully fixed:

1. Hard-coded login credentials in `EcoPlots/app.R`.
   - Move to env vars, mounted config, Shiny Server auth, or reverse-proxy auth.

2. Nested observers in date selector logic.
   - Pattern: `observeEvent(..., { observe({ ... }) })`.
   - Replace with single `renderUI()` branches to avoid observer accumulation.

3. Large global RDS loads at app startup.
   - Simpler and currently working.
   - Could be optimized with lazy loading or tab-specific data loading later.

4. Plot reactives recompute filtered data repeatedly.
   - Assign `xdata()`/`xdata_etf()` to local variables inside render functions.

5. Repeated DT boilerplate.
   - Generalize a shared table-render helper across tabs.

6. UI/aesthetic enhancements.
   - Consider a modern dark analytics dashboard style for EQI Focus.
   - Keep legacy tabs available, but make EQI Focus the primary product surface.

## Pricing Discussion Context

Pricing estimates discussed for building similar dashboard apps:

- Simple working app: roughly `$2,500-$5,000`.
- Solid custom app: roughly `$7,500-$15,000`.
- Production analytics app: roughly `$18,000-$35,000+`.
- For a polished analytics dashboard where database already exists and the work
  is mainly UI, translating SAS logic, and automated routines:
  - basic version: `$6,000-$10,000`
  - polished dashboard: `$10,000-$18,000`
  - more complete analytics app: `$18,000-$30,000`

Recommended quote for a polished first version:

```text
$12,000-$15,000
```

Lower friendly/MVP range:

```text
$7,500-$10,000
```

Ongoing support:

```text
$250-$750/month
```

or:

```text
$100-$150/hour
```

## Suggested Next Steps On Linux Server

1. Confirm files copied to:

```sh
/home/bbotson/applications/ecoquant/apps/ecoplots
```

2. Confirm package availability:

```sh
Rscript -e 'source("EcoPlots/app.R", local=TRUE); cat("app source ok\n")'
```

3. Run a no-loess smoke build:

```sh
Rscript r/build_ecoplots_rds.R --skip-loess=true
```

4. Run full build:

```sh
Rscript r/build_ecoplots_rds.R
```

5. Confirm incremental no-new path:

```sh
Rscript r/build_ecoplots_rds.R --mode=incremental
```

6. Build and start Docker:

```sh
docker compose build
docker compose up -d
```

7. Watch app logs:

```sh
docker compose logs -f ecoplots
tail -f logs/shiny-server/*.log
```

8. After each data update:

```sh
Rscript r/update_ecoplots_rds.R
docker compose restart ecoplots
```

## Known Caution

The builder currently rewrites RDS files directly. If the Shiny container is
reading an RDS while the builder is writing it, there is a small risk of reading
a partial file. A future hardening step would be:

1. write to a temp file,
2. validate it,
3. atomically rename it over the final `.rds`.

This has not been implemented yet.
