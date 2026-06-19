# ECOplots RDS Workflow

This workflow keeps the Shiny app fast by treating the app data as a daily
cache, not as the source of truth.

## Inputs

The builder lives in `apps/ecoplots` and reads daily CSV outputs from the
shared repo-level `../../results/` directory:

- `results_stock_xtest_YYYY-MM-DD.csv`
- `results_etf_xtest_YYYY-MM-DD.csv`

The current expected schema is the `xtest` export with `symbol`, `date`, `x1`
through `x30`, slope columns, volume columns, `close_price`, `sector`,
`industry`, and related metadata.

## Builder

Run from the EcoPlots workflow directory:

```sh
cd /home/bbotson/applications/ecoquant/apps/ecoplots
Rscript r/build_ecoplots_rds.R
```

By default, the script:

- keeps the latest 365 calendar days of result files
- filters stock loess processing to symbols above the bottom third of latest
  `d5_volume`
- computes `ls10` and `ls20` loess values outside Shiny
- writes app-ready files to `EcoPlots/*_1y.rds`
- writes `EcoPlots/manifest_1y.csv`

Useful options:

```sh
Rscript r/build_ecoplots_rds.R --history-days=365
Rscript r/build_ecoplots_rds.R --volume-quantile=0.3333333
Rscript r/build_ecoplots_rds.R --skip-loess=true
Rscript r/build_ecoplots_rds.R --suffix=_test --history-days=30
```

`--skip-loess=true` is useful for quick validation of CSV ingestion, means,
group melts, and interaction tables.

## Incremental Updates

For daily operation, use:

```sh
cd /home/bbotson/applications/ecoquant/apps/ecoplots
Rscript r/update_ecoplots_rds.R
```

This is a wrapper around:

```sh
Rscript r/build_ecoplots_rds.R --mode=incremental
```

Incremental mode:

- reads the existing `stock_history_1y.rds` and `etf_history_1y.rds`
- finds result CSV files newer than the latest date already in those histories
- appends only the new CSV rows
- deduplicates by `date,symbol`
- trims the rolling history window
- regenerates the app-ready RDS files only when new stock or ETF files exist

If no new files are present, it exits without rebuilding loess.
If new app output families have been added in code and the corresponding RDS
files are missing, incremental mode rebuilds derived outputs from the existing
rolling histories even when no new CSV files are present.

Example cron entry:

```cron
15 19 * * 1-5 cd /home/bbotson/applications/ecoquant/apps/ecoplots && Rscript r/update_ecoplots_rds.R >> logs/ecoplots_update.log 2>&1
```

## Outputs

The app now prefers `_1y.rds` files when present and falls back to the legacy
file names otherwise.

Main outputs:

- `loessdata_1y.rds`
- `loessdata_etf_1y.rds`
- `xmeans_1y.rds`
- `indmeans_1y.rds`
- `ss_melt_1y.rds`
- `etf_melt_1y.rds`
- `x5i_1y.rds`, `x9i_1y.rds`, `x14i_1y.rds`, `x21i_1y.rds`, `x30i_1y.rds`,
  `sumi_1y.rds`
- stock crossover files: `x9x5_1y.rds`, `x14x9_1y.rds`, `x21x14_1y.rds`,
  `x30x21_1y.rds`, `x30x14_1y.rds`
- ETF crossover files: `etf9x5_1y.rds`, `etf14x9_1y.rds`,
  `etf21x14_1y.rds`, `etf30x21_1y.rds`, `etf30x14_1y.rds`

EQI Focus outputs:

- `eqi_top50_rank_1y.rds`: latest complete-history stock ranking by EQI score
- `eqi_top20_changes_1y.rds`: latest Top 20 entries, exits, and rank changes
- `eqi_top50_tenure_1y.rds`: Top 50 tenure and return since first Top 50 entry
- `eqi_vol_top50_1y.rds`: latest Top 50 ranked with realized-volatility context
- `eqi_plot_lr_1y.rds`: in-app plot data for Top 20 rolling regression lines
  computed from `x1` through `x30` values
- `eqi_topN_events_vol_1y.rds`: rank-history and volatility event table

SAS master/lifecycle/EQMI outputs:

- `eqi_stock_master_daily_1y.rds`: continuity-filtered daily master with
  PDF and lifecycle term-structure fields
- `eqi_daily_ranked_universe_1y.rds`: lifecycle-compatible ranked universe
- `eqi_curr_topN_1y.rds`, `eqi_prev_topN_1y.rds`,
  `eqi_curr_lifecycle_topN_1y.rds`, `eqi_prev_lifecycle_topN_1y.rds`
- `eqi_topN_events_vol_today_1y.rds`, `eqi_topN_exits_vol_1y.rds`
- `eqi_alert_entries_1y.rds`, `eqi_entry_snapshot_1y.rds`,
  `eqi_entry_snapshot_audit_1y.rds`
- `eqi_signal_lifecycle_daily_1y.rds`, `eqi_active_signals_today_1y.rds`,
  `eqi_status_changes_today_1y.rds`, `eqi_broken_signals_today_1y.rds`,
  `eqi_signal_status_summary_today_1y.rds`
- `eqi_quad_points_1y.rds`
- `eqi_eqmi_daily_1y.rds`, `eqi_eqmi_sector_daily_1y.rds`
- `eqi_continuity_check_1y.rds`, `eqi_continuity_exclusions_1y.rds`

## Shiny App Behavior

`EcoPlots/app.R` loads `_1y.rds` files automatically when they exist. The
large stock loess data is converted to a `data.table` and keyed by common
filter fields. Date sliders default to the latest 180 calendar days, while
still allowing the full one-year range.

The EQI Focus section is the first sidebar tab. It provides a ticker panel
where a user can filter the ticker search by useful groups, including All
tickers, EQI Top 20, EQI Top 50, movers, entries, exits, Volatility Top 50, and
sector groups. After selecting a ticker, the panel shows latest rank status,
score, price, approximate 90-day return, a 90-trading-day rolling LR chart, and
that ticker's Top 50 rank history if it has one. The summary tables hide
lower-level diagnostic fields such as `slope_edge`, `delta_x21slope`,
`term_structure`, and `price_pos_20`.

The app should only filter and plot app-ready data. Loess generation and EQI
table construction belong in `r/build_ecoplots_rds.R`, not in user-triggered
Shiny paths.

The `EQI Master` tab exposes the SAS-derived ranked universe, TopN event
tables, alert lifecycle snapshots, continuity exclusions, and EQMI daily/sector
tables from prebuilt RDS files.

## Operational Notes

The legacy files without `_1y` are still present as fallbacks. Once the new
workflow is verified on the Shiny server, the deployment process can either:

1. copy only the `_1y.rds` files plus `app.R`, or
2. replace the legacy names with the newly built files.

Option 1 is safer during transition because the app can fall back to legacy
files if a new file is missing.
