#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(data.table)
})

args <- commandArgs(trailingOnly = TRUE)

`%||%` <- function(x, y) if (is.null(x)) y else x

arg_value <- function(name, default = NULL) {
  prefix <- paste0("--", name, "=")
  hit <- args[startsWith(args, prefix)]
  if (length(hit) == 0) {
    return(default)
  }
  sub(prefix, "", hit[[length(hit)]], fixed = TRUE)
}

find_up <- function(start, marker) {
  current <- normalizePath(start, mustWork = TRUE)
  repeat {
    candidate <- file.path(current, marker)
    if (dir.exists(candidate) || file.exists(candidate)) {
      return(current)
    }
    parent <- dirname(current)
    if (identical(parent, current)) {
      return(NULL)
    }
    current <- parent
  }
}

script_file <- sub("^--file=", "", commandArgs(FALSE)[grep("^--file=", commandArgs(FALSE))][1] %||% "build_ecoplots_rds.R")
script_dir <- normalizePath(dirname(script_file), mustWork = FALSE)
workflow_root <- find_up(script_dir, "EcoPlots") %||% normalizePath(getwd(), mustWork = TRUE)
data_root <- find_up(workflow_root, "results") %||% workflow_root

results_dir <- normalizePath(arg_value("results-dir", file.path(data_root, "results")), mustWork = TRUE)
output_dir <- normalizePath(arg_value("output-dir", file.path(workflow_root, "EcoPlots")), mustWork = TRUE)
history_days <- as.integer(arg_value("history-days", "365"))
volume_quantile <- as.numeric(arg_value("volume-quantile", "0.3333333"))
suffix <- arg_value("suffix", "_1y")
skip_loess <- tolower(arg_value("skip-loess", "false")) %in% c("true", "t", "1", "yes")
mode <- arg_value("mode", "full")
if (!mode %in% c("full", "incremental")) {
  stop("--mode must be either 'full' or 'incremental'")
}

x_cols <- c("x1", "x2", "x3", "x4", "x5", "x9", "x14", "x21", "x30")
slope_cols <- paste0(x_cols, "slope")
volume_cols <- c("d1_volume", "d2_volume", "d3_volume", "d4_volume", "d5_volume", "d9_volume", "d14_volume", "d21_volume", "d30_volume")
base_cols <- c(
  "symbol", "date", x_cols, slope_cols, "low", "low_rank", "x2_w_slope",
  volume_cols,
  "close_price", "ticker", "name", "sector", "industry", "exchange", "index"
)

xgroup <- list(
  fang = c("META", "AMZN", "NFLX", "GOOGL"),
  bank = c("BAC", "JPM", "WFC", "HSBC"),
  tech = c("AAPL", "MSFT", "INTC", "BABA"),
  ganja = c("GWPH", "furlockh"),
  semis = c("NVDA", "AMD", "INTC", "TSM"),
  semis2 = c("QCOM", "MU", "AVGO", "TXN"),
  bio = c("JNJ", "PFE", "AVGO", "MRK"),
  metals1 = c("AGI", "GOLD", "FCX", "IAG"),
  metals2 = c("PAAS", "FSM", "MUX", "GG"),
  metals3 = c("SCCO", "CDE", "KGC", "AG"),
  metals4 = c("BHP", "NEM", "TRQ", "PGLC"),
  metals6 = c("RGLD", "EXK", "MSB", "DRD"),
  metals7 = c("CHNR", "RIO", "GFI", "OPNT"),
  metals8 = c("PVG", "SA", "FNV", "CCJ"),
  metals9 = c("EGO", "HMY", "SBGL", "AU")
)

out_path <- function(stem) file.path(output_dir, paste0(stem, suffix, ".rds"))

save_app_rds <- function(x, stem) {
  path <- out_path(stem)
  saveRDS(x, path, compress = "gzip")
  data.table(file = basename(path), rows = if (is.data.frame(x)) nrow(x) else length(x))
}

required_app_output_stems <- c(
  "stock_history", "etf_history",
  "x5i", "x9i", "x14i", "x21i", "x30i", "sumi",
  "xmeans", "ss_melt", "indmeans", "etf_melt",
  "eqi_top50_rank", "eqi_top20_changes", "eqi_top50_tenure", "eqi_vol_top50",
  "eqi_plot_lr", "eqi_topN_events_vol",
  "eqi_file_inventory", "eqi_continuity_check", "eqi_continuity_exclusions",
  "eqi_stock_master_daily", "eqi_daily_ranked_universe",
  "eqi_curr_topN", "eqi_prev_topN", "eqi_curr_lifecycle_topN", "eqi_prev_lifecycle_topN",
  "eqi_topN_events_vol_today", "eqi_topN_exits_vol",
  "eqi_alert_entries", "eqi_entry_snapshot", "eqi_entry_snapshot_audit",
  "eqi_signal_lifecycle_daily", "eqi_active_signals_today", "eqi_status_changes_today",
  "eqi_broken_signals_today", "eqi_signal_status_summary_today",
  "eqi_quad_points", "eqi_eqmi_daily", "eqi_eqmi_sector_daily",
  "loessdata", "loessdata_etf",
  "x30x21", "x21x14", "x14x9", "x9x5", "x30x14",
  "etf30x21", "etf21x14", "etf14x9", "etf9x5", "etf30x14"
)

missing_required_outputs <- function() {
  stems <- required_app_output_stems
  if (skip_loess) {
    stems <- setdiff(stems, c(
      "loessdata", "loessdata_etf",
      "x30x21", "x21x14", "x14x9", "x9x5", "x30x14",
      "etf30x21", "etf21x14", "etf14x9", "etf9x5", "etf30x14"
    ))
  }
  stems[!file.exists(vapply(stems, out_path, character(1)))]
}

result_date <- function(path, prefix) {
  as.IDate(sub(prefix, "", sub(".csv", "", basename(path), fixed = TRUE), fixed = TRUE))
}

normalize_results <- function(dt) {
  missing_cols <- setdiff(base_cols, names(dt))
  if (length(missing_cols) > 0) {
    stop("Result data is missing required columns: ", paste(missing_cols, collapse = ", "))
  }
  if (!"source_file" %in% names(dt)) {
    dt[, source_file := NA_character_]
  }
  dt <- dt[, c(base_cols, "source_file"), with = FALSE]
  dt[, date := as.IDate(date)]
  char_cols <- intersect(c("symbol", "ticker", "name", "sector", "industry", "exchange", "source_file"), names(dt))
  dt[, (char_cols) := lapply(.SD, function(x) {
    x <- trimws(as.character(x))
    x[x == ""] <- NA_character_
    x
  }), .SDcols = char_cols]
  dt <- dt[!is.na(symbol)]
  dt[is.na(ticker), ticker := symbol]
  dt[is.na(name), name := symbol]
  dt[is.na(sector), sector := "Unknown"]
  dt[is.na(industry), industry := "Unknown"]
  dt[, (volume_cols) := lapply(.SD, as.numeric), .SDcols = volume_cols]
  setorder(dt, symbol, date)
  unique(dt, by = c("date", "symbol"), fromLast = TRUE)
}

read_result_csvs <- function(files) {
  dt <- rbindlist(
    lapply(files, function(path) {
      out <- fread(path, na.strings = c("", "NA", "NULL"), integer64 = "double")
      out[, source_file := basename(path)]
      out
    }),
    fill = TRUE,
    use.names = TRUE
  )
  normalize_results(dt)
}

result_files <- function(kind) {
  prefix <- paste0("results_", kind, "_xtest_")
  files <- Sys.glob(file.path(results_dir, paste0(prefix, "*.csv")))
  if (length(files) == 0) {
    stop("No ", kind, " result files found in ", results_dir)
  }
  dates <- result_date(files, prefix)
  keep <- !is.na(dates)
  data.table(file = files[keep], date = dates[keep])[order(date)]
}

history_stem <- function(kind) paste0(kind, "_history")

read_results_full <- function(kind) {
  available <- result_files(kind)
  latest <- max(available$date)
  start <- latest - history_days
  files <- available[date >= start, file]
  message("Reading ", length(files), " ", kind, " files from ", start, " to ", latest)
  dt <- read_result_csvs(files)
  attr(dt, "new_file_count") <- length(files)
  dt
}

read_results_incremental <- function(kind) {
  available <- result_files(kind)
  history_path <- out_path(history_stem(kind))
  if (!file.exists(history_path)) {
    message("No existing ", basename(history_path), "; running full ", kind, " load")
    return(read_results_full(kind))
  }

  existing <- normalize_results(as.data.table(readRDS(history_path)))
  latest_existing <- max(existing$date, na.rm = TRUE)
  new_files <- available[date > latest_existing, file]

  if (length(new_files) == 0) {
    latest <- max(existing$date, na.rm = TRUE)
    start <- latest - history_days
    existing <- existing[date >= start]
    message("No new ", kind, " files after ", latest_existing)
    attr(existing, "new_file_count") <- 0L
    return(existing)
  }

  message("Appending ", length(new_files), " new ", kind, " files after ", latest_existing)
  incoming <- read_result_csvs(new_files)
  dt <- rbindlist(list(existing, incoming), fill = TRUE, use.names = TRUE)
  dt <- normalize_results(dt)
  latest <- max(dt$date, na.rm = TRUE)
  start <- latest - history_days
  dt <- dt[date >= start]
  attr(dt, "new_file_count") <- length(new_files)
  dt
}

read_results <- function(kind) {
  if (mode == "incremental") {
    read_results_incremental(kind)
  } else {
    read_results_full(kind)
  }
}

fit_loess <- function(y, idx, span) {
  ok <- is.finite(y) & is.finite(idx)
  if (sum(ok) < 8L || length(unique(y[ok])) < 2L) {
    return(rep(NA_real_, length(y)))
  }
  out <- rep(NA_real_, length(y))
  fit <- tryCatch(
    stats::loess(y[ok] ~ idx[ok], span = span, na.action = stats::na.exclude),
    error = function(e) NULL
  )
  if (!is.null(fit)) {
    pred <- tryCatch(
      stats::predict(fit, data.frame(idx = idx[ok])),
      error = function(e) rep(NA_real_, sum(ok))
    )
    out[ok] <- pred
  }
  out
}

build_loessdata <- function(dt, symbol_col = "symbol", sector_col = "sector", include_industry = TRUE) {
  id_cols <- c("date", symbol_col, sector_col, "d5_volume", "close_price", slope_cols)
  if (include_industry) {
    id_cols <- c("date", symbol_col, sector_col, "industry", "d5_volume", "close_price", slope_cols)
  }
  long <- melt(
    dt,
    id.vars = id_cols,
    measure.vars = x_cols,
    variable.name = "timescale",
    value.name = "raw_value"
  )
  setnames(long, symbol_col, "symbol")
  setnames(long, sector_col, "sector")
  setorder(long, symbol, timescale, date)
  long[, idx := seq_len(.N), by = .(symbol, timescale)]
  long[, `:=`(
    ls10 = fit_loess(raw_value, idx, 0.1),
    ls20 = fit_loess(raw_value, idx, 0.2)
  ), by = .(symbol, timescale)]
  long <- melt(
    long,
    id.vars = setdiff(names(long), c("raw_value", "idx", "ls10", "ls20")),
    measure.vars = c("ls10", "ls20"),
    variable.name = "span",
    value.name = "value"
  )
  long[, timescale := factor(as.character(timescale), levels = x_cols)]
  long[, span := factor(as.character(span), levels = c("ls10", "ls20"))]
  setorder(long, symbol, timescale, span, date)
  long[]
}

build_interactions <- function(stock) {
  latest <- max(stock$date)
  si <- copy(stock[date == latest])
  si[, `:=`(
    x5i = x5slope * x5,
    x9i = x9slope * x9,
    x14i = x14slope * x14,
    x21i = x21slope * x21,
    x30i = x30slope * x30
  )]
  si[, sumi := x5i + x9i + x14i + x21i + x30i]

  top_negative <- function(dt, value_col, slope_filter, cols) {
    out <- dt[eval(slope_filter), ..cols]
    setorderv(out, value_col)
    head(out, 10)
  }

  list(
    x5i = top_negative(si, "x5i", quote(x5slope > 0 & x9slope > 0), c("symbol", "date", "sector", "industry", "close_price", "x5", "x5slope", "x5i")),
    x9i = top_negative(si, "x9i", quote(x9slope > 0 & x14slope > 0), c("symbol", "date", "sector", "industry", "close_price", "x9", "x9slope", "x9i")),
    x14i = top_negative(si, "x14i", quote(x14slope > 0 & x21slope > 0), c("symbol", "date", "sector", "industry", "close_price", "x14", "x14slope", "x14i")),
    x21i = top_negative(si, "x21i", quote(x21slope > 0 & x30slope > 0), c("symbol", "date", "sector", "industry", "close_price", "x21", "x21slope", "x21i")),
    x30i = top_negative(si, "x30i", quote(x30slope > 0), c("symbol", "date", "sector", "industry", "close_price", "x30", "x30slope", "x30i")),
    sumi = top_negative(si, "sumi", quote(x5slope > 0 & x9slope > 0 & x14slope > 0 & x21slope > 0 & x30slope > 0), c("symbol", "date", "sector", "industry", "close_price", "x5", "x14", "x21", "x30", "x5slope", "x14slope", "x21slope", "x30slope", "x5i", "x14i", "x21i", "x30i", "sumi"))
  )
}

build_crossovers <- function(loess_dt, is_etf = FALSE, threshold = 0.0051) {
  latest <- max(loess_dt$date)
  cols <- c("date", "symbol", "sector", "industry", "d5_volume", "close_price", "timescale", "value", slope_cols)
  if (!"industry" %in% names(loess_dt)) {
    loess_dt[, industry := NA_character_]
  }
  rr <- dcast(
    loess_dt[date == latest & span == "ls20" & timescale %in% c("x5", "x9", "x14", "x21", "x30"), ..cols],
    date + symbol + sector + industry + d5_volume + close_price + x5slope + x9slope + x14slope + x21slope + x30slope ~ timescale,
    value.var = "value"
  )

  one <- function(left, right) {
    diff_name <- paste(left, "-", right)
    out <- copy(rr)
    out[, (diff_name) := get(left) - get(right)]
    out <- out[is.finite(get(diff_name)) & abs(get(diff_name)) < threshold]
    out[, direction := fifelse(get(diff_name) > 0, "+", fifelse(get(diff_name) < 0, "-", "0"))]
    if (is_etf) {
      out <- out[, .(date, sector = symbol, d5_volume, direction, left_value = get(left), right_value = get(right), diff = get(diff_name))]
      setnames(out, c("left_value", "right_value", "diff"), c(left, right, diff_name))
    } else {
      out <- out[, .(date, symbol, sector, industry, d5_volume, close_price, direction, left_value = get(left), right_value = get(right), diff = get(diff_name))]
      setnames(out, c("left_value", "right_value", "diff"), c(left, right, diff_name))
    }
    setorder(out, sector)
    out
  }

  list(
    x30x21 = one("x30", "x21"),
    x21x14 = one("x21", "x14"),
    x14x9 = one("x14", "x9"),
    x9x5 = one("x9", "x5"),
    x30x14 = one("x30", "x14")
  )
}

build_sector_means <- function(stock) {
  stock[!is.na(sector) & sector != "" & sector != "n/a",
        lapply(.SD, mean, na.rm = TRUE),
        by = .(date, sector),
        .SDcols = x_cols]
}

build_industry_means <- function(stock) {
  means <- stock[!is.na(sector) & !is.na(industry) & sector != "" & industry != "" & sector != "n/a" & industry != "n/a",
                 lapply(.SD, mean, na.rm = TRUE),
                 by = .(date, industry, sector),
                 .SDcols = x_cols]
  out <- melt(means, id.vars = c("date", "industry", "sector"), variable.name = "variable", value.name = "value")
  out[, variable := factor(as.character(variable), levels = x_cols)]
  out[]
}

build_xgroup_melt <- function(stock) {
  keep <- unique(unlist(xgroup, use.names = FALSE))
  out <- melt(
    stock[symbol %in% keep, c("date", "symbol", x_cols), with = FALSE],
    id.vars = c("date", "symbol"),
    measure.vars = x_cols,
    variable.name = "variable",
    value.name = "value"
  )
  out[, `:=`(
    symbol = factor(symbol),
    variable = factor(as.character(variable), levels = x_cols)
  )]
  out[]
}

build_etf_melt <- function(etf) {
  group_map <- NULL
  old_path <- file.path(output_dir, "etf_melt.rds")
  if (file.exists(old_path)) {
    old <- as.data.table(readRDS(old_path))
    if (all(c("sector", "Group") %in% names(old))) {
      group_map <- unique(old[, .(sector, Group)])
    }
  }
  if (is.null(group_map)) {
    group_map <- unique(etf[, .(sector = symbol, Group = "Ungrouped")])
  }

  etf_copy <- copy(etf)
  etf_copy[, sector := symbol]
  out <- melt(
    etf_copy[, c("date", "sector", x_cols, "close_price"), with = FALSE],
    id.vars = c("date", "sector"),
    measure.vars = c(x_cols, "close_price"),
    variable.name = "variable",
    value.name = "value"
  )
  out <- merge(out, group_map, by = "sector", all.x = TRUE)
  out[is.na(Group), Group := "Ungrouped"]
  out[, variable := factor(as.character(variable), levels = c(x_cols, "close_price"))]
  setorder(out, date, Group, sector, variable)
  out[]
}

zscore_safe <- function(x) {
  m <- mean(x, na.rm = TRUE)
  s <- stats::sd(x, na.rm = TRUE)
  if (is.na(s) || s == 0) {
    return(rep(NA_real_, length(x)))
  }
  (x - m) / s
}

zscore_zero <- function(x) {
  m <- mean(x, na.rm = TRUE)
  s <- stats::sd(x, na.rm = TRUE)
  if (is.na(s) || s == 0) {
    return(rep(0, length(x)))
  }
  (x - m) / s
}

roll_sd_complete <- function(x) {
  if (anyNA(x)) {
    return(NA_real_)
  }
  stats::sd(x)
}

lr_endpoint <- function(y) {
  if (length(y) < 2L || anyNA(y)) {
    return(NA_real_)
  }
  x <- seq_along(y)
  fit <- stats::lm(y ~ x)
  as.numeric(stats::predict(fit, newdata = data.frame(x = length(y))))
}

rolling_lr_endpoint <- function(y, window) {
  out <- rep(NA_real_, length(y))
  if (length(y) < 2L) {
    return(out)
  }
  for (i in seq_along(y)) {
    start <- max(1L, i - window + 1L)
    out[i] <- lr_endpoint(y[start:i])
  }
  out
}

build_eqi_focus_outputs <- function(
  stock,
  top_n = 50L,
  table1_n = 20L,
  chart_n = 20L,
  lifecycle_top_n = 20L,
  d30_floor = 1000000,
  tenure_days = 92L,
  continuity_lookback_dates = 60L,
  continuity_min_obs = 40L,
  strict_continuity = TRUE,
  eqmi_lookback_days = 60L
) {
  needed <- c("symbol", "date", "ticker", "name", "sector", "industry", "close_price", "d30_volume", x_cols, slope_cols, "source_file")
  missing_needed <- setdiff(needed, names(stock))
  if (length(missing_needed) > 0) {
    for (col in missing_needed) stock[, (col) := NA]
  }
  dt <- copy(stock[, ..needed])
  dt <- dt[
    !is.na(symbol) & symbol != "" &
      !is.na(sector) & sector != "" &
      !tolower(sector) %in% c("etf", "etfs", "unknown", "n/a", "na", "null", "none", ".")
  ]
  all_dates <- sort(unique(dt$date))
  latest_date <- max(all_dates)
  yday_date <- max(all_dates[all_dates < latest_date])

  setorder(dt, symbol, date)

  dt[, `:=`(
    delta_x21slope = x21slope - shift(x21slope),
    term_structure_pdf = (x9slope - x30slope) + (x14slope - x30slope) + (x21slope - x30slope),
    term_structure_lifecycle = ((x14slope + x21slope + x30slope) / 3) - ((x3slope + x4slope + x5slope) / 3),
    rollmin20 = frollapply(close_price, 20, min, fill = NA_real_, align = "right"),
    rollmax20 = frollapply(close_price, 20, max, fill = NA_real_, align = "right"),
    prev_close = shift(close_price)
  ), by = symbol]

  dt[, price_pos_20 := fifelse(
    is.finite(rollmin20) & is.finite(rollmax20) & rollmax20 > rollmin20,
    (close_price - rollmin20) / (rollmax20 - rollmin20),
    NA_real_
  )]
  dt[, `:=`(
    slope_edge_pdf = is.finite(delta_x21slope) & is.finite(term_structure_pdf) & is.finite(price_pos_20) &
      delta_x21slope > 0 & term_structure_pdf > 0 & price_pos_20 <= 0.70,
    slope_edge_lifecycle = is.finite(delta_x21slope) & is.finite(term_structure_lifecycle) & is.finite(price_pos_20) &
      delta_x21slope > 0 & term_structure_lifecycle > 0 & price_pos_20 <= 0.70
  )]
  dt[, `:=`(
    trigger_reason_edge_pdf = fifelse(slope_edge_pdf, "delta_x21>0 & term_structure_pdf>0 & price_pos_20<=0.70", ""),
    trigger_reason_edge_lifecycle = fifelse(slope_edge_lifecycle, "delta_x21>0 & term_structure_lifecycle>0 & price_pos_20<=0.70", "")
  )]

  dt[, ret_1d := fifelse(is.finite(prev_close) & prev_close > 0 & close_price > 0, close_price / prev_close - 1, NA_real_)]
  dt[, abs_ret_1d := abs(ret_1d)]
  dt[, `:=`(
    hv_20 = frollapply(ret_1d, 20, roll_sd_complete, fill = NA_real_, align = "right"),
    avg_abs_ret_20 = frollapply(abs_ret_1d, 20, function(x) if (anyNA(x)) NA_real_ else mean(x), fill = NA_real_, align = "right"),
    max_abs_ret_20 = frollapply(abs_ret_1d, 20, function(x) if (anyNA(x)) NA_real_ else max(x), fill = NA_real_, align = "right"),
    hit_3pct_20 = frollapply(abs_ret_1d, 20, function(x) if (anyNA(x)) NA_real_ else sum(x >= 0.03), fill = NA_real_, align = "right"),
    hit_5pct_20 = frollapply(abs_ret_1d, 20, function(x) if (anyNA(x)) NA_real_ else sum(x >= 0.05), fill = NA_real_, align = "right")
  ), by = symbol]
  dt[, hv_20_ann := hv_20 * sqrt(252)]
  dt[, `:=`(
    z_avg_abs_ret_20 = zscore_safe(avg_abs_ret_20),
    z_hv_20 = zscore_safe(hv_20),
    z_max_abs_ret_20 = zscore_safe(max_abs_ret_20),
    z_hit_3pct_20 = zscore_safe(hit_3pct_20),
    z_hit_5pct_20 = zscore_safe(hit_5pct_20)
  ), by = date]
  dt[, swing_score_1d := 0.60 * z_avg_abs_ret_20 + 0.40 * z_hit_3pct_20]

  recent_dates <- tail(all_dates, min(length(all_dates), continuity_lookback_dates))
  continuity_check <- dt[date %in% recent_dates, .(
    n_obs_recent = uniqueN(date),
    max_symbol_dt = max(date, na.rm = TRUE),
    miss_close_price = sum(!is.finite(close_price)),
    miss_d30_volume = sum(!is.finite(d30_volume)),
    miss_x3slope = sum(!is.finite(x3slope)),
    miss_x4slope = sum(!is.finite(x4slope)),
    miss_x5slope = sum(!is.finite(x5slope)),
    miss_x14slope = sum(!is.finite(x14slope)),
    miss_x21slope = sum(!is.finite(x21slope)),
    miss_x30slope = sum(!is.finite(x30slope))
  ), by = symbol]
  required_obs <- if (strict_continuity) length(recent_dates) else min(continuity_min_obs, length(recent_dates))
  eligible_symbols <- continuity_check[
    max_symbol_dt == latest_date &
      n_obs_recent >= required_obs &
      miss_close_price == 0 &
      miss_d30_volume == 0 &
      miss_x3slope == 0 &
      miss_x4slope == 0 &
      miss_x5slope == 0 &
      miss_x14slope == 0 &
      miss_x21slope == 0 &
      miss_x30slope == 0,
    symbol
  ]
  continuity_exclusions <- continuity_check[max_symbol_dt == latest_date & !symbol %in% eligible_symbols][order(n_obs_recent, symbol)]
  master_features <- dt[symbol %in% eligible_symbols]

  eq_base <- master_features[
    d30_volume >= d30_floor &
      is.finite(close_price) & is.finite(x14slope) & is.finite(x21slope) & is.finite(x30slope) &
      is.finite(x3slope) & is.finite(x4slope) & is.finite(x5slope)
  ]
  eq_base[, `:=`(
    avg_long = (x14slope + x21slope + x30slope) / 3,
    short_alpha = 0.5 * x4slope + 0.3 * x3slope + 0.2 * x5slope,
    logvol = log10(pmax(d30_volume, 1))
  )]
  eq_base[, `:=`(
    z_avg_long = zscore_zero(avg_long),
    z_short_alpha = zscore_zero(short_alpha),
    z_logvol = zscore_zero(logvol)
  ), by = date]
  eq_base[, EQ_score_vol := 0.65 * z_avg_long + 0.25 * z_short_alpha + 0.10 * z_logvol]
  setorder(eq_base, date, -EQ_score_vol, -d30_volume, symbol)
  eq_base[, rank_EQ := seq_len(.N), by = date]
  eq_base[, universe_n := .N, by = date]
  setnames(eq_base, c("avg_long", "short_alpha", "logvol"), c("avg_long_raw", "short_alpha_raw", "logvol_raw"))

  stock_master_daily <- eq_base[, .(
    date, symbol, name, sector, industry, close_price, d30_volume,
    x1slope, x2slope, x3slope, x4slope, x5slope, x9slope, x14slope, x21slope, x30slope,
    rollmin20, rollmax20, price_pos_20, delta_x21slope,
    term_structure_pdf, term_structure_lifecycle,
    slope_edge_pdf, slope_edge_lifecycle,
    trigger_reason_edge_pdf, trigger_reason_edge_lifecycle,
    avg_long_raw, short_alpha_raw, logvol_raw,
    z_avg_long, z_short_alpha, z_logvol,
    EQ_score_vol, rank_EQ, universe_n, source_file
  )]
  setnames(stock_master_daily, c("rollmin20", "rollmax20"), c("close_min_20", "close_max_20"))

  daily_ranked_universe <- stock_master_daily[, .(
    date, symbol, name, sector, industry, close_price, d30_volume,
    x3slope, x4slope, x5slope, x14slope, x21slope, x30slope,
    avg_long_raw, short_alpha_raw, logvol_raw,
    z_avg_long, z_short_alpha, z_logvol,
    EQ_score_vol, rank_EQ, universe_n,
    delta_x21slope,
    term_structure = term_structure_lifecycle,
    price_pos_20,
    slope_edge = slope_edge_lifecycle,
    trigger_reason_edge = trigger_reason_edge_lifecycle,
    source_file
  )]

  top50_today_rank <- stock_master_daily[date == latest_date & rank_EQ <= top_n][
    order(rank_EQ),
    .SD,
    .SDcols = c(
      "date", "symbol", "name", "sector", "industry", "close_price", "d30_volume", "EQ_score_vol", "rank_EQ",
      "delta_x21slope", "term_structure_pdf", "price_pos_20", "slope_edge_pdf"
    )
  ]
  setnames(top50_today_rank, c("term_structure_pdf", "slope_edge_pdf"), c("term_structure", "slope_edge"))
  top50_yday_rank <- stock_master_daily[date == yday_date & rank_EQ <= top_n][
    order(rank_EQ),
    .SD,
    .SDcols = c(
      "date", "symbol", "name", "sector", "industry", "close_price", "d30_volume", "EQ_score_vol", "rank_EQ",
      "delta_x21slope", "term_structure_pdf", "price_pos_20", "slope_edge_pdf"
    )
  ]
  setnames(top50_yday_rank, c("term_structure_pdf", "slope_edge_pdf"), c("term_structure", "slope_edge"))

  curr_topN <- daily_ranked_universe[date == latest_date & rank_EQ <= top_n][order(rank_EQ, symbol)]
  prev_topN <- daily_ranked_universe[date == yday_date & rank_EQ <= top_n][order(rank_EQ, symbol)]
  curr_lifecycle_topN <- daily_ranked_universe[date == latest_date & rank_EQ <= lifecycle_top_n][order(rank_EQ, symbol)]
  prev_lifecycle_topN <- daily_ranked_universe[date == yday_date & rank_EQ <= lifecycle_top_n][order(rank_EQ, symbol)]

  eq_topN_events_vol_today <- merge(
    curr_topN,
    prev_topN[, .(symbol, prior_rank_EQ = rank_EQ, prior_EQ_score_vol = EQ_score_vol)],
    by = "symbol",
    all.x = TRUE
  )
  eq_topN_events_vol_today[, `:=`(
    rank_delta_1d = prior_rank_EQ - rank_EQ,
    EQ_delta_1d = EQ_score_vol - prior_EQ_score_vol,
    event_type = fcase(
      is.na(prior_rank_EQ), "Entry",
      prior_rank_EQ > rank_EQ, "Promotion",
      prior_rank_EQ < rank_EQ, "Demotion",
      default = "Flat"
    )
  )]
  setorder(eq_topN_events_vol_today, rank_EQ, symbol)
  eq_topN_exits_vol <- prev_topN[!symbol %in% curr_topN$symbol, .(
    prior_date = date,
    current_date = latest_date,
    symbol, name, sector, industry,
    prior_rank_EQ = rank_EQ,
    event_type = "Exit"
  )][order(prior_rank_EQ, symbol)]

  eq_topN_events_vol <- stock_master_daily[rank_EQ <= top_n, .(
    date, symbol, name, sector, industry, close_price, d30_volume,
    EQ_score_vol, rank_EQ, delta_x21slope,
    term_structure = term_structure_lifecycle,
    price_pos_20,
    slope_edge = slope_edge_lifecycle,
    trigger_reason_edge = trigger_reason_edge_lifecycle
  )]

  today20 <- copy(top50_today_rank[rank_EQ <= table1_n])
  yday20 <- copy(top50_yday_rank[rank_EQ <= table1_n])
  setnames(today20, c("rank_EQ", "EQ_score_vol", "close_price", "d30_volume", "delta_x21slope", "term_structure", "price_pos_20", "slope_edge"),
           c("rank_today", "EQ_today", "close_today", "d30_today", "dx21_today", "ts_today", "pp_today", "edge_today"))
  setnames(yday20, c("rank_EQ", "EQ_score_vol", "close_price", "d30_volume", "sector", "industry", "delta_x21slope", "term_structure", "price_pos_20", "slope_edge"),
           c("rank_yday", "EQ_yday", "close_yday", "d30_yday", "sector_y", "industry_y", "dx21_yday", "ts_yday", "pp_yday", "edge_yday"))
  changes <- merge(today20, yday20, by = "symbol", all = TRUE, suffixes = c("", "_drop"))
  changes[, `:=`(
    sector = fifelse(is.na(sector) | sector == "", sector_y, sector),
    industry = fifelse(is.na(industry) | industry == "", industry_y, industry),
    d30_volume = fcoalesce(d30_today, d30_yday),
    close_price = fcoalesce(close_today, close_yday),
    EQ_score_vol = fcoalesce(EQ_today, EQ_yday),
    delta_x21slope = fcoalesce(dx21_today, dx21_yday),
    term_structure = fcoalesce(ts_today, ts_yday),
    price_pos_20 = fcoalesce(pp_today, pp_yday),
    slope_edge = fcoalesce(edge_today, edge_yday),
    rank_EQ = rank_today,
    rank_EQ_yday = rank_yday
  )]
  changes[, delta_rank := rank_yday - rank_today]
  changes[, change_type := fcase(
    !is.na(rank_today) & !is.na(rank_yday) & delta_rank > 0, "Promotion",
    !is.na(rank_today) & !is.na(rank_yday) & delta_rank < 0, "Demotion",
    !is.na(rank_today) & !is.na(rank_yday) & delta_rank == 0, "Flat",
    !is.na(rank_today) & is.na(rank_yday), "Entry",
    is.na(rank_today) & !is.na(rank_yday), "Exit",
    default = NA_character_
  )]
  changes[, `:=`(
    sort_order = fcase(change_type == "Promotion", 1L, change_type == "Entry", 2L, change_type == "Demotion", 3L, change_type == "Exit", 4L, change_type == "Flat", 5L, default = 99L),
    promo_key = fifelse(change_type == "Promotion", -delta_rank, NA_real_),
    demo_key = fifelse(change_type == "Demotion", delta_rank, NA_real_),
    sort_rank = fcoalesce(rank_today, rank_yday)
  )]
  setorder(changes, sort_order, promo_key, demo_key, sort_rank, symbol)
  hist_top20 <- stock_master_daily[
    date >= latest_date - tenure_days & date <= latest_date & rank_EQ <= table1_n,
    .(first_top20_date = min(date)),
    by = symbol
  ]
  changes <- merge(changes, hist_top20, by = "symbol", all.x = TRUE)
  changes[is.na(first_top20_date), first_top20_date := latest_date]
  changes[, days_since_first_top20 := as.integer(latest_date - first_top20_date) + 1L]
  change_cols <- c("change_type", "symbol", "sector", "industry", "rank_EQ", "rank_EQ_yday", "delta_rank", "EQ_score_vol", "d30_volume", "close_price", "delta_x21slope", "price_pos_20", "first_top20_date", "days_since_first_top20")
  promo_demo_sorted <- changes[, ..change_cols]

  tenure_cut <- latest_date - tenure_days
  hist_3m <- stock_master_daily[date >= tenure_cut & date <= latest_date & rank_EQ <= top_n, .(first_topN_date = min(date)), by = symbol]
  first_close <- stock_master_daily[, .(symbol, first_topN_date = date, first_topN_close = close_price)]
  hist_3m <- merge(hist_3m, first_close, by = c("symbol", "first_topN_date"), all.x = TRUE)
  top_today_enriched <- merge(top50_today_rank, hist_3m, by = "symbol", all.x = TRUE)
  top_today_enriched[is.na(first_topN_date), first_topN_date := latest_date]
  top_today_enriched[is.na(first_topN_close), first_topN_close := close_price]
  top_today_enriched[, `:=`(
    days_since_first_topN = as.integer(latest_date - first_topN_date) + 1L,
    pct_return_since_first = fifelse(is.finite(first_topN_close) & first_topN_close > 0, (close_price - first_topN_close) / first_topN_close, NA_real_)
  )]
  setorder(top_today_enriched, rank_EQ)

  chart_symbols <- top50_today_rank[rank_EQ <= chart_n, .(symbol, rank_EQ)]
  chart_base <- merge(dt, chart_symbols, by = "symbol", all = FALSE)
  plot_long <- melt(
    chart_base[, c("symbol", "rank_EQ", "date", "close_price", x_cols), with = FALSE],
    id.vars = c("symbol", "rank_EQ", "date", "close_price"),
    measure.vars = x_cols,
    variable.name = "tf",
    value.name = "x_value"
  )
  plot_long[, tf := as.character(tf)]
  lr_lengths <- c(x1 = 30, x2 = 35, x3 = 40, x4 = 45, x5 = 50, x9 = 45, x14 = 50, x21 = 60, x30 = 70)
  setorder(plot_long, symbol, tf, date)
  plot_long[, lr_value := rolling_lr_endpoint(x_value, lr_lengths[tf[1]]), by = .(symbol, tf)]
  plot_long[, price := close_price]
  plot_long[, price_plot := fifelse(tf == "x1", price, NA_real_)]

  vol_top50_today <- dt[
    date == latest_date &
      is.finite(swing_score_1d) & is.finite(avg_abs_ret_20) & is.finite(hit_3pct_20) &
      is.finite(hv_20) & is.finite(max_abs_ret_20) & d30_volume >= d30_floor &
      !is.na(sector) & sector != ""
  ][order(-swing_score_1d, -avg_abs_ret_20, -hit_3pct_20, -hv_20)]
  vol_top50_today <- head(vol_top50_today, top_n)
  vol_top50_today[, rank_vol := seq_len(.N)]

  alert_entries <- daily_ranked_universe[rank_EQ <= lifecycle_top_n, .(entry_date = min(date)), by = symbol]
  alert_entries[, `:=`(
    alert_type = "BUY",
    notes = "Auto-seeded from current Top 20"
  )]
  setorder(alert_entries, entry_date, symbol)
  entry_snapshot <- merge(
    alert_entries,
    daily_ranked_universe[, .(
      symbol, entry_date = date, entry_name = name, entry_sector = sector, entry_industry = industry,
      entry_price = close_price, entry_rank_EQ = rank_EQ, entry_EQ_score_vol = EQ_score_vol
    )],
    by = c("symbol", "entry_date"),
    all.x = TRUE
  )
  entry_snapshot_audit <- copy(entry_snapshot)
  entry_snapshot_audit[, missing_entry_row_flag := is.na(entry_price) | is.na(entry_rank_EQ) | is.na(entry_EQ_score_vol)]

  lifecycle_base <- merge(alert_entries, daily_ranked_universe, by = "symbol", allow.cartesian = TRUE)
  lifecycle_base <- lifecycle_base[date >= entry_date]
  lifecycle_base <- merge(
    lifecycle_base,
    entry_snapshot[, .(symbol, entry_date, entry_price, entry_rank_EQ, entry_EQ_score_vol)],
    by = c("symbol", "entry_date"),
    all.x = TRUE
  )
  setorder(lifecycle_base, symbol, entry_date, date)
  lifecycle_base[, `:=`(
    prior_date = shift(date),
    prior_rank_EQ = shift(rank_EQ),
    prior_EQ_score_vol = shift(EQ_score_vol),
    prior_close_price = shift(close_price),
    trade_day_idx = seq_len(.N) - 1L
  ), by = .(symbol, entry_date)]
  lifecycle_base[, `:=`(
    trading_days_since_entry = trade_day_idx,
    calendar_days_since_entry = as.integer(date - entry_date),
    rank_delta_1d = prior_rank_EQ - rank_EQ,
    EQ_delta_1d = EQ_score_vol - prior_EQ_score_vol,
    price_return_1d = fifelse(is.finite(prior_close_price) & prior_close_price > 0, close_price / prior_close_price - 1, NA_real_),
    rank_delta_from_entry = entry_rank_EQ - rank_EQ,
    EQ_delta_from_entry = EQ_score_vol - entry_EQ_score_vol,
    price_return_since_entry = fifelse(is.finite(entry_price) & entry_price > 0, close_price / entry_price - 1, NA_real_)
  )]
  lifecycle_base[, eq_down_streak := {
    streak <- integer(.N)
    current <- 0L
    for (i in seq_len(.N)) {
      if (is.finite(EQ_delta_1d[i]) && EQ_delta_1d[i] < 0) current <- current + 1L else current <- 0L
      streak[i] <- current
    }
    streak
  }, by = .(symbol, entry_date)]
  lifecycle_base[, `:=`(
    EQ_down_2d_flag = eq_down_streak >= 2L,
    EQ_down_3d_flag = eq_down_streak >= 3L,
    rank_zone = fcase(rank_EQ <= 20, "Top 20", rank_EQ <= 50, "Top 50", rank_EQ <= 100, "Top 100", default = "Below Top 100"),
    rank_percentile = fifelse(universe_n > 1, 1 - ((rank_EQ - 1) / (universe_n - 1)), NA_real_),
    rank_drop_15_1d_flag = is.finite(rank_delta_1d) & rank_delta_1d <= -15,
    rank_drop_25_from_entry_flag = is.finite(rank_delta_from_entry) & rank_delta_from_entry <= -25,
    rank_drop_75_from_entry_flag = is.finite(rank_delta_from_entry) & rank_delta_from_entry <= -75
  )]
  lifecycle_base[, status_label := fcase(
    rank_EQ > 100 | rank_drop_75_from_entry_flag | (rank_EQ > 50 & price_return_since_entry < 0 & EQ_down_3d_flag), "Broken",
    rank_drop_15_1d_flag | rank_drop_25_from_entry_flag | EQ_down_3d_flag | rank_EQ > 50, "Re-Evaluate",
    rank_EQ <= 20 & fcoalesce(EQ_delta_1d, 0) >= 0 & !EQ_down_3d_flag, "Active-Strong",
    rank_EQ <= 50, "Active-Weakening",
    default = "Unclassified"
  )]
  lifecycle_base[, prior_status_label := shift(status_label), by = .(symbol, entry_date)]
  lifecycle_base[, status_changed_flag := !is.na(prior_status_label) & status_label != prior_status_label]
  lifecycle_base[, trigger_reason := fcase(
    status_label == "Broken" & rank_EQ > 100, "Rank fell below allowed zone",
    status_label == "Broken" & rank_drop_75_from_entry_flag, "Rank deterioration from entry exceeded Broken threshold",
    status_label == "Broken", "Outside weak zone + below entry + 3-day EQ decline",
    status_label == "Re-Evaluate" & rank_drop_15_1d_flag, "1-day rank deterioration exceeded threshold",
    status_label == "Re-Evaluate" & rank_drop_25_from_entry_flag, "Rank deterioration from entry exceeded threshold",
    status_label == "Re-Evaluate" & EQ_down_3d_flag, "EQ_score_vol declined 3 straight days",
    status_label == "Re-Evaluate", "Rank fell outside weak zone",
    status_label == "Active-Strong", "Top zone rank with stable/rising EQ_score",
    status_label == "Active-Weakening", "Still inside weak zone but no longer strong",
    default = "No rule matched"
  )]
  signal_lifecycle_daily <- lifecycle_base
  active_signals_today <- signal_lifecycle_daily[date == latest_date & status_label %in% c("Active-Strong", "Active-Weakening", "Re-Evaluate")]
  status_changes_today <- signal_lifecycle_daily[date == latest_date & status_changed_flag == TRUE]
  broken_signals_today <- signal_lifecycle_daily[date == latest_date & status_label == "Broken"]
  signal_status_summary_today <- signal_lifecycle_daily[date == latest_date, .(n_signals = .N), by = .(date, status_label)][order(-n_signals, status_label)]

  prev_eq_lookup <- daily_ranked_universe[date == yday_date, .(symbol, prior_EQ_score_vol = EQ_score_vol)]
  quad_points <- merge(curr_lifecycle_topN, alert_entries[, .(symbol, entry_date)], by = "symbol")
  quad_points <- merge(quad_points, prev_eq_lookup, by = "symbol", all.x = TRUE)
  quad_points <- merge(
    quad_points,
    signal_lifecycle_daily[date == latest_date, .(symbol, entry_date, status_label, rank_delta_from_entry, price_return_since_entry, trading_days_since_entry)],
    by = c("symbol", "entry_date"),
    all.x = TRUE
  )
  quad_points[, `:=`(
    EQ_delta_1d = EQ_score_vol - prior_EQ_score_vol,
    x_score = EQ_score_vol,
    y_delta = EQ_score_vol - prior_EQ_score_vol,
    plot_label = paste0(symbol, "(", rank_EQ, ")"),
    status_group = fifelse(status_label %in% c("Active-Strong", "Active-Weakening", "Re-Evaluate", "Broken"), status_label, "Other")
  )]

  eqmi_src <- dt[date >= latest_date - eqmi_lookback_days & date <= latest_date]
  eqmi_src <- eqmi_src[
    is.finite(close_price) & is.finite(d30_volume) & d30_volume >= d30_floor &
      is.finite(x14slope) & is.finite(x21slope) & is.finite(x30slope)
  ]
  eqmi_src[, avg_long := (x14slope + x21slope + x30slope) / 3]
  setorder(eqmi_src, symbol, date)
  eqmi_src[, delta_avg_long := avg_long - shift(avg_long), by = symbol]
  eqmi_src[is.na(delta_avg_long), delta_avg_long := 0]
  eqmi_src[, `:=`(flag_long = avg_long > 0, flag_accel = delta_avg_long > 0)]
  eqmi_daily <- eqmi_src[, .(
    n = uniqueN(symbol),
    p_long = mean(flag_long, na.rm = TRUE),
    p_accel = mean(flag_accel, na.rm = TRUE)
  ), by = date][order(date)]
  eqmi_daily[, EQMI := 100 * (0.60 * p_long + 0.40 * p_accel)]
  eqmi_daily[, EQMI_EMA3 := {
    out <- numeric(.N)
    for (i in seq_len(.N)) out[i] <- if (i == 1L) EQMI[i] else 0.5 * EQMI[i] + 0.5 * out[i - 1L]
    out
  }]
  eqmi_sector_daily <- eqmi_src[
    !is.na(sector) & !tolower(sector) %in% c("n/a", "na", "unknown", ""),
    .(n = uniqueN(symbol), p_long = mean(flag_long, na.rm = TRUE), p_accel = mean(flag_accel, na.rm = TRUE)),
    by = .(sector, date)
  ][order(sector, date)]
  eqmi_sector_daily[, EQMI := 100 * (0.60 * p_long + 0.40 * p_accel)]
  eqmi_sector_daily[, EQMI_EMA3 := {
    out <- numeric(.N)
    for (i in seq_len(.N)) out[i] <- if (i == 1L) EQMI[i] else 0.5 * EQMI[i] + 0.5 * out[i - 1L]
    out
  }, by = sector]

  list(
    eqi_top50_rank = top50_today_rank,
    eqi_top20_changes = promo_demo_sorted,
    eqi_top50_tenure = top_today_enriched,
    eqi_vol_top50 = vol_top50_today,
    eqi_plot_lr = plot_long,
    eqi_topN_events_vol = eq_topN_events_vol,
    eqi_file_inventory = result_files("stock"),
    eqi_continuity_check = continuity_check,
    eqi_continuity_exclusions = continuity_exclusions,
    eqi_stock_master_daily = stock_master_daily,
    eqi_daily_ranked_universe = daily_ranked_universe,
    eqi_curr_topN = curr_topN,
    eqi_prev_topN = prev_topN,
    eqi_curr_lifecycle_topN = curr_lifecycle_topN,
    eqi_prev_lifecycle_topN = prev_lifecycle_topN,
    eqi_topN_events_vol_today = eq_topN_events_vol_today,
    eqi_topN_exits_vol = eq_topN_exits_vol,
    eqi_alert_entries = alert_entries,
    eqi_entry_snapshot = entry_snapshot,
    eqi_entry_snapshot_audit = entry_snapshot_audit,
    eqi_signal_lifecycle_daily = signal_lifecycle_daily,
    eqi_active_signals_today = active_signals_today,
    eqi_status_changes_today = status_changes_today,
    eqi_broken_signals_today = broken_signals_today,
    eqi_signal_status_summary_today = signal_status_summary_today,
    eqi_quad_points = quad_points,
    eqi_eqmi_daily = eqmi_daily,
    eqi_eqmi_sector_daily = eqmi_sector_daily
  )
}

manifest <- list()
start_time <- Sys.time()

stock <- read_results("stock")
etf <- read_results("etf")
latest_date <- max(stock$date, etf$date)
new_stock_files <- attr(stock, "new_file_count") %||% NA_integer_
new_etf_files <- attr(etf, "new_file_count") %||% NA_integer_

missing_outputs <- missing_required_outputs()
if (mode == "incremental" && identical(new_stock_files, 0L) && identical(new_etf_files, 0L) && length(missing_outputs) == 0) {
  message("No new stock or ETF files. Existing app RDS files are current through ", latest_date, ".")
  quit(save = "no", status = 0)
}
if (mode == "incremental" && identical(new_stock_files, 0L) && identical(new_etf_files, 0L) && length(missing_outputs) > 0) {
  message("No new stock or ETF files, but required app outputs are missing: ", paste(missing_outputs, collapse = ", "))
  message("Rebuilding derived app outputs from existing rolling histories.")
}

manifest <- append(manifest, list(save_app_rds(stock, "stock_history")))
manifest <- append(manifest, list(save_app_rds(etf, "etf_history")))

message("Building interactions")
interactions <- build_interactions(stock)
manifest <- append(manifest, lapply(names(interactions), function(nm) save_app_rds(interactions[[nm]], nm)))

message("Building means and group melts")
xmeans <- build_sector_means(stock)
ss_melt <- build_xgroup_melt(stock)
indmeans <- build_industry_means(stock)
etf_melt <- build_etf_melt(etf)
message("Building EQI focus outputs")
eqi_outputs <- build_eqi_focus_outputs(stock)
manifest <- append(manifest, list(
  save_app_rds(xmeans, "xmeans"),
  save_app_rds(ss_melt, "ss_melt"),
  save_app_rds(indmeans, "indmeans"),
  save_app_rds(etf_melt, "etf_melt")
))
manifest <- append(manifest, lapply(names(eqi_outputs), function(nm) save_app_rds(eqi_outputs[[nm]], nm)))

if (!skip_loess) {
  latest_stock <- stock[date == max(date)]
  cutoff <- as.numeric(stats::quantile(latest_stock$d5_volume, probs = volume_quantile, na.rm = TRUE))
  high_volume_symbols <- latest_stock[is.finite(d5_volume) & d5_volume >= cutoff, unique(symbol)]
  message("Building stock loess for ", length(high_volume_symbols), " symbols")
  loessdata <- build_loessdata(stock[symbol %in% high_volume_symbols])
  manifest <- append(manifest, list(save_app_rds(loessdata, "loessdata")))

  message("Building stock crossovers")
  stock_crossovers <- build_crossovers(loessdata, is_etf = FALSE)
  manifest <- append(manifest, list(
    save_app_rds(stock_crossovers$x30x21, "x30x21"),
    save_app_rds(stock_crossovers$x21x14, "x21x14"),
    save_app_rds(stock_crossovers$x14x9, "x14x9"),
    save_app_rds(stock_crossovers$x9x5, "x9x5"),
    save_app_rds(stock_crossovers$x30x14, "x30x14")
  ))

  message("Building ETF loess and crossovers")
  etf_for_loess <- copy(etf)
  etf_for_loess[, sector := symbol]
  loessdata_etf <- build_loessdata(etf_for_loess, symbol_col = "symbol", sector_col = "sector", include_industry = FALSE)
  manifest <- append(manifest, list(save_app_rds(loessdata_etf[, .(date, sector, timescale, d5_volume, span, value)], "loessdata_etf")))
  etf_crossovers <- build_crossovers(loessdata_etf, is_etf = TRUE)
  manifest <- append(manifest, list(
    save_app_rds(etf_crossovers$x30x21, "etf30x21"),
    save_app_rds(etf_crossovers$x21x14, "etf21x14"),
    save_app_rds(etf_crossovers$x14x9, "etf14x9"),
    save_app_rds(etf_crossovers$x9x5, "etf9x5"),
    save_app_rds(etf_crossovers$x30x14, "etf30x14")
  ))
}

manifest_dt <- rbindlist(manifest, fill = TRUE)
manifest_dt[, `:=`(
  latest_date = as.character(latest_date),
  history_days = history_days,
  generated_at = as.character(Sys.time()),
  runtime_seconds = round(as.numeric(difftime(Sys.time(), start_time, units = "secs")), 1)
)]
manifest_path <- file.path(output_dir, paste0("manifest", suffix, ".csv"))
fwrite(manifest_dt, manifest_path)
print(manifest_dt)
message("Wrote manifest: ", manifest_path)
