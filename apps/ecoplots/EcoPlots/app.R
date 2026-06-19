###Load package, data queries---------------

library(shiny)
library(shinyjs)
library(shinyauthr)
library(shinydashboard)
library(ggplot2)
library(dplyr)
library(scales)
library(grid)
library(data.table)
library(reshape2)
library(shinyWidgets)
library(DT)

options(shiny.autoreload = FALSE)

`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || is.na(x)) y else x

app_file_raw <- sys.frames()[[1]]$ofile %||% NA_character_
app_file <- tryCatch(normalizePath(app_file_raw, mustWork = TRUE), error = function(e) NA_character_)
app_dir <- if (is.na(app_file)) normalizePath(getwd(), mustWork = TRUE) else dirname(app_file)

read_app_rds <- function(name) {
  one_year_path <- file.path(app_dir, paste0(name, "_1y.rds"))
  legacy_path <- file.path(app_dir, paste0(name, ".rds"))
  if (file.exists(one_year_path)) {
    return(readRDS(one_year_path))
  }
  if (file.exists(legacy_path)) {
    return(readRDS(legacy_path))
  }
  stop("Missing app data for ", name, ". Expected one of: ", paste(basename(c(one_year_path, legacy_path)), collapse = ", "))
}

read_optional_app_rds <- function(name) {
  one_year_path <- file.path(app_dir, paste0(name, "_1y.rds"))
  legacy_path <- file.path(app_dir, paste0(name, ".rds"))
  if (file.exists(one_year_path)) {
    return(readRDS(one_year_path))
  }
  if (file.exists(legacy_path)) {
    return(readRDS(legacy_path))
  }
  data.frame()
}

date_default <- function(dates, days = 180) {
  dates <- as.Date(dates)
  minval <- min(dates, na.rm = TRUE)
  maxval <- max(dates, na.rm = TRUE)
  c(max(minval, maxval - days), maxval)
}

loess_smooth_series <- function(x, y, span = 0.35, degree = 1, family = "symmetric") {
  out <- rep(NA_real_, length(y))
  x_date <- as.Date(x)
  x_num <- as.numeric(x_date)
  ok <- is.finite(y) & is.finite(x_num)
  if (sum(ok) < 8L || length(unique(y[ok])) < 2L) {
    return(out)
  }
  fit_df <- data.frame(x_num = x_num[ok], y = y[ok])
  fit <- tryCatch(
    stats::loess(
      y ~ x_num,
      data = fit_df,
      span = span,
      degree = degree,
      family = family,
      na.action = stats::na.exclude,
      control = stats::loess.control(surface = "direct")
    ),
    error = function(e) NULL
  )
  if (!is.null(fit)) {
    pred <- tryCatch(
      stats::predict(fit, newdata = data.frame(x_num = x_num[ok])),
      error = function(e) rep(NA_real_, sum(ok))
    )
    out[ok] <- pred
  }
  out
}

coerce_plot_date_range <- function(xmin, xmax) {
  if (is.null(xmin) || is.null(xmax) || !is.finite(xmin) || !is.finite(xmax)) {
    return(NULL)
  }
  as.Date(c(xmin, xmax), origin = "1970-01-01")
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

eqi_tf_colors <- c(
  x1  = "#FF0000",
  x2  = "#FFA500",
  x3  = "#D4C600",
  x4  = "#00B050",
  x5  = "#00AEEF",
  x9  = "#0000FF",
  x14 = "#800080",
  x21 = "#808080",
  x30 = "#000000"
)
eqi_focus_palettes <- list(
  "Classic" = c(
    x1 = "#c62828",
    x2 = "#ef6c00",
    x3 = "#f9a825",
    x4 = "#2e7d32",
    x5 = "#00897b",
    x9 = "#1e88e5",
    x14 = "#5e35b1",
    x21 = "#6d4c41",
    x30 = "#212121"
  ),
  "Bright" = c(
    x1 = "#ff5a5f",
    x2 = "#ff9f1c",
    x3 = "#ffd166",
    x4 = "#06d6a0",
    x5 = "#00d1ff",
    x9 = "#3a86ff",
    x14 = "#b517ff",
    x21 = "#ff66c4",
    x30 = "#f8fafc"
  ),
  "Bright Dark" = c(
    x1 = "#ff6b6b",
    x2 = "#ffb347",
    x3 = "#ffe66d",
    x4 = "#7ae582",
    x5 = "#5eead4",
    x9 = "#66c7ff",
    x14 = "#a78bfa",
    x21 = "#f9a8d4",
    x30 = "#ffffff"
  ),
  "Cool" = c(
    x1 = "#006d77",
    x2 = "#118ab2",
    x3 = "#3a86ff",
    x4 = "#4361ee",
    x5 = "#4cc9f0",
    x9 = "#4895ef",
    x14 = "#560bad",
    x21 = "#7209b7",
    x30 = "#14213d"
  ),
  "Warm" = c(
    x1 = "#9d0208",
    x2 = "#d00000",
    x3 = "#e85d04",
    x4 = "#f48c06",
    x5 = "#faa307",
    x9 = "#ffba08",
    x14 = "#e76f51",
    x21 = "#b56576",
    x30 = "#6d597a"
  ),
  "Colorblind Safe" = c(
    x1 = "#D55E00",
    x2 = "#E69F00",
    x3 = "#F0E442",
    x4 = "#009E73",
    x5 = "#56B4E9",
    x9 = "#0072B2",
    x14 = "#CC79A7",
    x21 = "#999999",
    x30 = "#000000"
  )
)

eqi_lr_lengths <- c(x1 = 30, x2 = 35, x3 = 40, x4 = 45, x5 = 50, x9 = 45, x14 = 50, x21 = 60, x30 = 70)
eqi_x_cols <- names(eqi_lr_lengths)
eqi_slope_cols <- paste0(eqi_x_cols, "slope")
eqi_lr_display_multiplier <- 100

l <- as.data.table(read_app_rds("loessdata"))
letf <- as.data.table(read_app_rds("loessdata_etf"))
if (!inherits(l$date, "Date")) l[, date := as.Date(date)]
if (!inherits(letf$date, "Date")) letf[, date := as.Date(date)]
setkey(l, sector, industry, symbol, date, timescale, span)
setkey(letf, sector, date, timescale, span)
l$x5_volume <- l$d5_volume/5
industries <- l %>% distinct(sector, industry) %>% arrange(sector, industry)
indmeans <- as.data.frame(read_app_rds("indmeans"))
industries_x <- indmeans %>% distinct(sector, industry) %>% arrange(sector, industry)
allindustries_x <- unique(as.character(as.factor(indmeans$industry)))
ss_melt <- as.data.frame(read_app_rds("ss_melt"))
etf_melt <- as.data.frame(read_app_rds("etf_melt"))
t <- as.data.frame(read_app_rds("xmeans"))
m <- reshape2::melt(t, id =c("date", "sector") )
scalesx <- unique(as.character(m$variable))
scales <- unique(as.character(l$timescale))
sectors <- unique(as.character(as.factor(l$sector)))
sectors_x <- unique(as.character(as.factor(m$sector)))
allindustries <- unique(as.character(as.factor(l$industry)))
spans <- unique(as.character(l$span))
spansetf <- unique(as.character(letf$span))
symbols <- unique(l$symbol)
xgroup <- list(  fang =   c('META', 'AMZN','NFLX' ,'GOOGL'),
                 bank=  c('BAC', 'JPM', 'WFC', 'HSBC'),
                 tech =  c('AAPL', 'MSFT', 'INTC', 'BABA'),
                 ganja =  c(  'GWPH', 'furlockh'),
                 semis = c(  'NVDA', 'AMD','INTC','TSM'),
                 semis2 =   c(  'QCOM', 'MU','AVGO','TXN'),
                 bio =  c(  'JNJ', 'PFE','AVGO','MRK'),
                 metals1 =   c(  'AGI', 'GOLD','FCX','IAG'),
                 metals2 =  c('PAAS','FSM','MUX','GG'),
                 metals3 =  c('SCCO','CDE','KGC','AG'),
                 metals4 =  c('BHP','NEM','TRQ','PGLC'),
                 metals6 = c('RGLD','EXK','MSB','DRD'),
                 metals7 = c('CHNR','RIO','GFI','OPNT'),
                 metals8 = c('PVG','SA','FNV','CCJ'),
                 metals9 = c('EGO','HMY','SBGL','AU')
)
x3021 <- read_app_rds("x30x21") %>%  mutate_if(is.numeric, round, 4)
x2114 <- read_app_rds("x21x14") %>% mutate_if(is.numeric, round, 4)
x149 <- read_app_rds("x14x9") %>% mutate_if(is.numeric, round, 4)
x95 <- read_app_rds("x9x5") %>% mutate_if(is.numeric, round, 4)
x3014 <- read_app_rds("x30x14") %>% mutate_if(is.numeric, round, 4)
etf3021 <- read_app_rds("etf30x21") %>%  mutate_if(is.numeric, round, 4)
etf2114 <- read_app_rds("etf21x14") %>% mutate_if(is.numeric, round, 4)
etf149 <- read_app_rds("etf14x9") %>% mutate_if(is.numeric, round, 4)
etf95 <- read_app_rds("etf9x5") %>% mutate_if(is.numeric, round, 4)
etf3014 <- read_app_rds("etf30x14") %>% mutate_if(is.numeric, round, 4)
#import stock interactions
x5i <- read_app_rds("x5i")
x9i <- read_app_rds("x9i")
x14i <- read_app_rds("x14i")
x21i <- read_app_rds("x21i")
x30i <- read_app_rds("x30i")
sumi <- read_app_rds("sumi")
eqi_top50_rank <- as.data.frame(read_app_rds("eqi_top50_rank"))
eqi_top20_changes <- as.data.frame(read_app_rds("eqi_top20_changes"))
eqi_top50_tenure <- as.data.frame(read_app_rds("eqi_top50_tenure"))
eqi_vol_top50 <- as.data.frame(read_app_rds("eqi_vol_top50"))
eqi_plot_lr <- as.data.frame(read_app_rds("eqi_plot_lr"))
eqi_topN_events_vol <- as.data.frame(read_app_rds("eqi_topN_events_vol"))
eqi_daily_ranked_universe <- as.data.frame(read_optional_app_rds("eqi_daily_ranked_universe"))
eqi_topN_events_vol_today <- as.data.frame(read_optional_app_rds("eqi_topN_events_vol_today"))
eqi_topN_exits_vol <- as.data.frame(read_optional_app_rds("eqi_topN_exits_vol"))
eqi_signal_lifecycle_daily <- as.data.frame(read_optional_app_rds("eqi_signal_lifecycle_daily"))
eqi_active_signals_today <- as.data.frame(read_optional_app_rds("eqi_active_signals_today"))
eqi_status_changes_today <- as.data.frame(read_optional_app_rds("eqi_status_changes_today"))
eqi_broken_signals_today <- as.data.frame(read_optional_app_rds("eqi_broken_signals_today"))
eqi_signal_status_summary_today <- as.data.frame(read_optional_app_rds("eqi_signal_status_summary_today"))
eqi_continuity_exclusions <- as.data.frame(read_optional_app_rds("eqi_continuity_exclusions"))
eqi_eqmi_daily <- as.data.frame(read_optional_app_rds("eqi_eqmi_daily"))
eqi_eqmi_sector_daily <- as.data.frame(read_optional_app_rds("eqi_eqmi_sector_daily"))
stock_history <- as.data.table(read_app_rds("stock_history"))
eqi_plot_lr$date <- as.Date(eqi_plot_lr$date)
stock_history[, date := as.Date(date)]
latest_app_date <- max(stock_history$date, na.rm = TRUE)
for (date_table_name in c(
  "eqi_daily_ranked_universe", "eqi_topN_events_vol_today", "eqi_topN_exits_vol",
  "eqi_signal_lifecycle_daily", "eqi_active_signals_today", "eqi_status_changes_today",
  "eqi_broken_signals_today", "eqi_signal_status_summary_today", "eqi_continuity_exclusions",
  "eqi_eqmi_daily", "eqi_eqmi_sector_daily"
)) {
  date_table <- get(date_table_name)
  if (nrow(date_table) > 0 && "date" %in% names(date_table)) {
    date_table$date <- as.Date(date_table$date)
    assign(date_table_name, date_table)
  }
}
setkey(stock_history, symbol, date)
eqi_symbols <- eqi_top50_rank %>% arrange(rank_EQ) %>% filter(rank_EQ <= 20) %>% pull(symbol)
all_eqi_symbols <- sort(unique(stock_history$symbol))
latest_symbol_sector <- stock_history[order(date), .SD[.N], by = symbol][
  !is.na(sector) & sector != "",
  .(symbol, sector)
]
sector_symbols <- split(latest_symbol_sector$symbol, latest_symbol_sector$sector)
sector_groups <- setNames(
  lapply(names(sector_symbols), function(sector) sector_symbols[[sector]]),
  paste("Sector:", names(sector_symbols))
)
eqi_ticker_groups <- c(
  list(
    "All tickers" = all_eqi_symbols,
    "EQI Top 20" = eqi_symbols,
    "EQI Top 50" = eqi_top50_rank %>% arrange(rank_EQ) %>% pull(symbol),
    "Top 20 Changes" = sort(unique(eqi_top20_changes$symbol)),
    "Promotions" = sort(unique(eqi_top20_changes$symbol[eqi_top20_changes$change_type == "Promotion"])),
    "Entries" = sort(unique(eqi_top20_changes$symbol[eqi_top20_changes$change_type == "Entry"])),
    "Demotions" = sort(unique(eqi_top20_changes$symbol[eqi_top20_changes$change_type == "Demotion"])),
    "Exits" = sort(unique(eqi_top20_changes$symbol[eqi_top20_changes$change_type == "Exit"])),
    "Volatility Top 50" = eqi_vol_top50 %>% arrange(rank_vol) %>% pull(symbol)
  ),
  sector_groups
)
eqi_ticker_groups <- lapply(eqi_ticker_groups, function(x) sort(unique(x[!is.na(x) & x != ""])))
#t <- readRDS("C:/Users/bbotson/Dropbox/EQI/Bryan_working/shiny/plots/xmeans.rds")
user_base <- data.frame(
  user = c("jbeerens", "bbotson", "ben"),
  password = c("maja22", "frodo", "alice76"), 
  permissions = c("standard", "admin", "standard"),
  name = c("James", "Bryan", "Ben"),
  stringsAsFactors = FALSE,
  row.names = NULL
)

auth_cookie_expiry_days <- suppressWarnings(as.integer(Sys.getenv("EQI_AUTH_COOKIE_DAYS", "30")))
if (is.na(auth_cookie_expiry_days) || auth_cookie_expiry_days < 1) {
  auth_cookie_expiry_days <- 30
}
auth_session_dir <- Sys.getenv("EQI_AUTH_SESSION_DIR", "/srv/shiny-server/auth_sessions")
auth_session_file <- file.path(auth_session_dir, "remembered_sessions.rds")

empty_auth_sessions <- function() {
  data.frame(
    user = character(),
    sessionid = character(),
    login_time = as.POSIXct(character()),
    stringsAsFactors = FALSE
  )
}

read_auth_sessions <- function() {
  if (!file.exists(auth_session_file)) {
    return(empty_auth_sessions())
  }
  sessions <- tryCatch(readRDS(auth_session_file), error = function(e) empty_auth_sessions())
  sessions$user <- as.character(sessions$user)
  sessions$sessionid <- as.character(sessions$sessionid)
  sessions$login_time <- as.POSIXct(sessions$login_time, tz = "UTC")
  sessions
}

write_auth_sessions <- function(sessions) {
  dir.create(auth_session_dir, recursive = TRUE, showWarnings = FALSE)
  saveRDS(sessions, auth_session_file)
}

get_remembered_sessions <- function(expiry = auth_cookie_expiry_days) {
  sessions <- read_auth_sessions()
  if (nrow(sessions) == 0) {
    return(sessions)
  }
  cutoff <- Sys.time() - as.difftime(expiry, units = "days")
  sessions <- sessions[!is.na(sessions$login_time) & sessions$login_time > cutoff, , drop = FALSE]
  valid_users <- user_base[, c("user", "permissions", "name"), drop = FALSE]
  merge(sessions, valid_users, by = "user", all.x = FALSE, all.y = FALSE)
}

save_remembered_session <- function(user, sessionid) {
  sessions <- read_auth_sessions()
  sessions <- sessions[!(sessions$user == user & sessions$sessionid == sessionid), , drop = FALSE]
  sessions <- rbind(
    sessions,
    data.frame(
      user = as.character(user),
      sessionid = as.character(sessionid),
      login_time = Sys.time(),
      stringsAsFactors = FALSE
    )
  )
  cutoff <- Sys.time() - as.difftime(auth_cookie_expiry_days, units = "days")
  sessions <- sessions[!is.na(sessions$login_time) & sessions$login_time > cutoff, , drop = FALSE]
  write_auth_sessions(sessions)
}

#-------------sidebar----------------
sidebar <- dashboardSidebar( 
  tags$head(
    tags$style(
      HTML("#sidebarmenu{padding-top:50px; margin-bottom: 120px; }")
    )),
  width = 225,
  sidebarMenu(HTML("<br><br><br>"),id="sidebarmenu"
              ,menuItem("EQI Focus",  tabName = "eqifocus", icon = icon("line-chart"))
              ,menuItem("EQI Master",  tabName = "eqimaster", icon = icon("database"))
              ,menuItem("Stocks Interaction",  tabName = "stocksint",icon = icon("table"))
              ,menuItem("Stocks crossovers",  tabName = "stockscross",icon = icon("table"))
              ,menuItem("ETF crossovers",  tabName = "etfcross",icon = icon("table"))
              ,menuItem("ETF",  tabName = "etf", icon = icon("line-chart"))
              ,menuItem("X",  tabName = "plotsx",icon = icon("line-chart"))
              ,menuItem("X Groups",  tabName = "xgroups",icon = icon("line-chart"))
              ,menuItem("Stocks visualations",  tabName = "stocks",icon = icon("line-chart"))
           
  ) 
) 
body <- dashboardBody(
  tags$head(
    tags$style(HTML("
      #shiny-disconnect-banner {
        display: none;
        position: fixed;
        right: 18px;
        bottom: 18px;
        z-index: 99999;
        max-width: 360px;
        padding: 14px 16px;
        border-radius: 4px;
        background: #24292f;
        color: #fff;
        box-shadow: 0 8px 24px rgba(0,0,0,.22);
        font-size: 14px;
      }
      #shiny-disconnect-banner button {
        margin-left: 10px;
        color: #24292f;
        background: #fff;
        border: 0;
        border-radius: 3px;
        padding: 5px 9px;
      }
      .skin-blue .main-header .navbar,
      .skin-blue .main-header .logo {
        background: linear-gradient(90deg, #08213a 0%, #0a3557 55%, #0f5f83 100%);
        box-shadow: 0 2px 14px rgba(0, 204, 255, .16);
      }
      .skin-blue .main-header .logo:hover {
        background: #0b3659;
      }
      .skin-blue .main-sidebar {
        background: #061320;
        border-right: 1px solid #123b5a;
      }
      .skin-blue .sidebar a {
        color: #d8edf8;
      }
      .skin-blue .sidebar-menu > li > a {
        border-left: 4px solid transparent;
      }
      .skin-blue .sidebar-menu > li.active > a,
      .skin-blue .sidebar-menu > li:hover > a {
        border-left-color: #19e6c2;
        background: linear-gradient(90deg, #12324d 0%, #0d2133 100%);
        color: #ffffff;
      }
      .content-wrapper, .right-side {
        background:
          radial-gradient(circle at top left, rgba(25, 230, 194, .10), transparent 32rem),
          linear-gradient(135deg, #07111d 0%, #061827 55%, #08111b 100%);
      }
      .content {
        padding-top: 24px;
      }
      .main-panel,
      .tab-content,
      .nav-tabs-custom,
      .box {
        background: transparent;
      }
      .nav-tabs {
        border-bottom: 1px solid #2a5f83;
      }
      .nav-tabs > li > a {
        color: #7fdfff;
        background: #07192a;
        border: 1px solid #173f60;
        margin-right: 6px;
      }
      .nav-tabs > li.active > a,
      .nav-tabs > li.active > a:focus,
      .nav-tabs > li.active > a:hover {
        color: #07111d;
        background: #f5fbff;
        border-color: #f5fbff;
        font-weight: 700;
      }
      .tab-pane {
        padding-top: 10px;
      }
      .eqi-dashboard {
        color: #edf8ff;
        font-family: 'Inter', 'Source Sans Pro', Arial, sans-serif;
      }
      .eqi-topbar {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        padding: 10px 12px;
        margin-bottom: 10px;
        border: 1px solid #266b91;
        background: linear-gradient(135deg, #0a2034 0%, #0d304a 100%);
        border-radius: 4px;
        box-shadow: 0 12px 28px rgba(0,0,0,.26);
      }
      .eqi-brand {
        display: flex;
        align-items: center;
        gap: 10px;
      }
      .eqi-logo-mark {
        width: 34px;
        height: 34px;
        border: 1px solid #00c2a8;
        border-radius: 4px;
        display: flex;
        align-items: center;
        justify-content: center;
        color: #05111b;
        font-weight: 800;
        background: linear-gradient(135deg, #19e6c2 0%, #6bf3ff 100%);
      }
      .eqi-title {
        font-size: 18px;
        font-weight: 700;
        color: #f6fbff;
        line-height: 1.1;
      }
      .eqi-subtitle {
        color: #6bf3ff;
        font-size: 12px;
        margin-top: 2px;
      }
      .eqi-asof {
        color: #c4ddec;
        font-size: 12px;
        white-space: nowrap;
      }
      .eqi-grid {
        display: grid;
        grid-template-columns: 250px minmax(0, 1fr) 300px;
        gap: 10px;
      }
      .eqi-filter-panel,
      .eqi-panel,
      .eqi-card,
      .eqi-table-panel {
        border: 1px solid #23577a;
        background: linear-gradient(180deg, #0d2236 0%, #091827 100%);
        border-radius: 4px;
        box-shadow: 0 10px 24px rgba(0,0,0,.30), inset 0 1px 0 rgba(255,255,255,.04);
      }
      .eqi-filter-panel {
        padding: 12px;
      }
      .eqi-panel-title {
        color: #f5fcff;
        font-size: 12px;
        font-weight: 700;
        letter-spacing: .02em;
        text-transform: uppercase;
        margin-bottom: 8px;
        border-bottom: 1px solid #2a5f83;
        padding-bottom: 7px;
      }
      .eqi-filter-panel label {
        color: #c2dbea;
        font-size: 12px;
      }
      .eqi-filter-panel .form-control,
      .eqi-filter-panel .selectize-input {
        background: #f5fbff !important;
        border: 1px solid #69c9f2 !important;
        color: #091827 !important;
        border-radius: 3px;
      }
      .eqi-filter-panel .selectize-dropdown {
        background: #f5fbff;
        color: #091827;
        border-color: #69c9f2;
      }
      .eqi-filter-panel .checkbox {
        color: #d7e5ee;
      }
      .eqi-kpi-strip {
        display: grid;
        grid-template-columns: repeat(5, minmax(145px, 1fr));
        gap: 10px;
        margin-bottom: 10px;
      }
      .eqi-card {
        min-height: 78px;
        padding: 12px;
        position: relative;
        overflow: hidden;
        display: flex;
        align-items: center;
        gap: 12px;
      }
      .eqi-card:before {
        content: '';
        position: absolute;
        left: 0;
        top: 0;
        bottom: 0;
        width: 3px;
        background: linear-gradient(180deg, #19e6c2 0%, #00a9ff 100%);
      }
      .eqi-card.warn:before { background: #ffd166; }
      .eqi-card.danger:before { background: #ff4d6d; }
      .eqi-card.neutral:before { background: #8bc7ff; }
      .eqi-card-icon {
        width: 38px;
        height: 38px;
        flex: 0 0 38px;
        border: 1px solid #8bc7ff;
        border-radius: 50%;
        display: flex;
        align-items: center;
        justify-content: center;
        color: #ffffff;
        background: rgba(107, 243, 255, .10);
        font-size: 18px;
      }
      .eqi-card-body {
        min-width: 0;
      }
      .eqi-card-label {
        color: #a9cbe0;
        font-size: 11px;
        text-transform: uppercase;
        letter-spacing: .03em;
      }
      .eqi-card-value {
        color: #ffffff;
        font-size: 22px;
        font-weight: 800;
        margin-top: 4px;
        line-height: 1.1;
      }
      .eqi-card-sub {
        color: #c4ddec;
        font-size: 12px;
        margin-top: 4px;
      }
      .eqi-chart-panel,
      .eqi-side-panel {
        padding: 10px;
      }
      .eqi-right-stack {
        display: grid;
        gap: 10px;
      }
      .eqi-detail-grid {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 8px 12px;
      }
      .eqi-detail-label {
        color: #a7c6d8;
        font-size: 11px;
        text-transform: uppercase;
      }
      .eqi-detail-value {
        color: #ffffff;
        font-weight: 700;
        font-size: 13px;
      }
      .eqi-heatmap-image img {
        width: 100%;
        height: auto;
        border: 1px solid #23577a;
        border-radius: 3px;
        background: #f5fbff;
      }
      .eqi-heatmap-empty {
        min-height: 120px;
        display: flex;
        align-items: center;
        justify-content: center;
        color: #a9cbe0;
        border: 1px dashed #23577a;
        border-radius: 3px;
        padding: 12px;
        text-align: center;
      }
      .eqi-heatmap-actions {
        display: flex;
        gap: 8px;
        margin: 8px 0;
      }
      .eqi-heatmap-actions .btn,
      .eqi-heatmap-actions a.btn {
        flex: 1;
        color: #061320 !important;
        background: #6bf3ff;
        border: 0;
        font-weight: 700;
        padding: 6px 8px;
      }
      .eqi-heatmap-actions a.btn {
        display: inline-block;
        text-align: center;
        text-decoration: none;
      }
      .eqi-heatmap-modal .modal-dialog {
        width: min(96vw, 1500px);
      }
      .eqi-heatmap-modal .modal-content {
        background: #07111d;
        color: #edf8ff;
        border: 1px solid #23577a;
      }
      .eqi-heatmap-modal .modal-header,
      .eqi-heatmap-modal .modal-footer {
        border-color: #23577a;
      }
      .eqi-heatmap-modal-body {
        max-height: 82vh;
        overflow: auto;
        background: #f5fbff;
        padding: 10px;
      }
      .eqi-heatmap-modal-body img {
        width: 100%;
        min-width: 900px;
        height: auto;
        display: block;
      }
      .eqi-mini-list {
        display: grid;
        gap: 6px;
      }
      .eqi-mini-row {
        display: flex;
        justify-content: space-between;
        gap: 8px;
        border-bottom: 1px solid #23577a;
        padding-bottom: 5px;
        font-size: 12px;
      }
      .eqi-positive { color: #39ffbf; font-weight: 700; }
      .eqi-negative { color: #ff7a90; font-weight: 700; }
      .eqi-bottom-grid {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 10px;
        margin-top: 10px;
      }
      .eqi-table-panel {
        padding: 10px;
      }
      .eqi-dashboard .nav-tabs {
        border-bottom-color: #2a5f83;
      }
      .eqi-dashboard .nav-tabs > li > a {
        color: #9deaff;
        background: #07192a;
        border-color: #23577a;
        border-radius: 3px 3px 0 0;
      }
      .eqi-dashboard .nav-tabs > li.active > a,
      .eqi-dashboard .nav-tabs > li.active > a:focus,
      .eqi-dashboard .nav-tabs > li.active > a:hover {
        color: #061320;
        background: #f5fbff;
        border-color: #f5fbff;
        font-weight: 700;
      }
      table.dataTable,
      .eqi-dashboard table.dataTable {
        color: #f0f8ff !important;
        background: #0b1d2e !important;
        border-collapse: collapse !important;
      }
      table.dataTable thead th,
      table.dataTable thead td {
        color: #ffffff !important;
        background: #123a5a !important;
        border-bottom: 1px solid #58c7f3 !important;
        font-weight: 800 !important;
      }
      table.dataTable tbody tr,
      table.dataTable.display tbody tr,
      table.dataTable.stripe tbody tr {
        background: #0c1f31 !important;
      }
      table.dataTable tbody tr:nth-child(even),
      table.dataTable.display tbody tr:nth-child(even),
      table.dataTable.stripe tbody tr:nth-child(even) {
        background: #102a40 !important;
      }
      table.dataTable.hover tbody tr:hover,
      table.dataTable.display tbody tr:hover {
        background: #174563 !important;
      }
      table.dataTable tbody td {
        color: #e8f5ff !important;
        border-top: 1px solid #173f60 !important;
      }
      .dataTables_wrapper,
      .eqi-dashboard .dataTables_wrapper,
      .eqi-dashboard .dataTables_info,
      .eqi-dashboard .dataTables_filter label,
      .eqi-dashboard .dataTables_length label {
        color: #c4ddec !important;
      }
      .dataTables_wrapper .dataTables_paginate .paginate_button {
        color: #bdefff !important;
        border: 1px solid #23577a !important;
        background: #07192a !important;
      }
      .dataTables_wrapper .dataTables_paginate .paginate_button.current,
      .dataTables_wrapper .dataTables_paginate .paginate_button.current:hover {
        color: #061320 !important;
        border-color: #6bf3ff !important;
        background: #6bf3ff !important;
      }
      .dataTables_wrapper input,
      .dataTables_wrapper select,
      .eqi-dashboard .dataTables_wrapper input,
      .eqi-dashboard .dataTables_wrapper select {
        background: #f5fbff !important;
        color: #091827 !important;
        border: 1px solid #69c9f2 !important;
      }
      @media (max-width: 1200px) {
        .eqi-grid {
          grid-template-columns: 220px minmax(0, 1fr);
        }
        .eqi-right-stack {
          grid-column: 1 / -1;
          grid-template-columns: 1fr 1fr;
        }
      }
      @media (max-width: 900px) {
        .eqi-grid,
        .eqi-kpi-strip,
        .eqi-bottom-grid,
        .eqi-right-stack {
          grid-template-columns: 1fr;
        }
        .eqi-topbar {
          align-items: flex-start;
          flex-direction: column;
        }
      }
    ")),
    tags$script(HTML("
      (function() {
        function sendHeartbeat() {
          if (window.Shiny && Shiny.setInputValue) {
            Shiny.setInputValue('client_heartbeat', new Date().toISOString(), {priority: 'event'});
            Shiny.setInputValue('client_visibility', document.visibilityState, {priority: 'event'});
          }
        }
        document.addEventListener('visibilitychange', sendHeartbeat);
        window.addEventListener('focus', sendHeartbeat);
        setInterval(sendHeartbeat, 25000);
        $(document).on('shiny:disconnected', function() {
          $('#shiny-disconnect-banner').show();
        });
        $(document).on('shiny:connected', function() {
          $('#shiny-disconnect-banner').hide();
          sendHeartbeat();
        });
        $(document).on('click', '#shiny-reload-button', function() {
          window.location.reload();
        });
      })();
    "))
  ),
  div(
    id = "shiny-disconnect-banner",
    span("Connection paused. Reconnect may resume automatically."),
    tags$button(id = "shiny-reload-button", type = "button", "Reload")
  ),
  
  ##login module------------------------
  # must turn shinyjs on
  shinyjs::useShinyjs(),
  # # add logout button UI 
  div(class = "pull-right", shinyauthr::logoutUI(id = "logout")),
  # add login panel UI function
  shinyauthr::loginUI(
    id = "login",
    cookie_expiry = auth_cookie_expiry_days,
    additional_ui = tags$p(
      paste0("Secure remember-this-device sessions last ", auth_cookie_expiry_days, " days. Use Log out to clear this browser session."),
      class = "text-center text-muted"
    )
  ),
  hidden(
  div(
      id = "form1",
  tabItems(
    
    # stocks tab ------------------------        
    tabItem(tabName = "stocks",
            fluidPage(  
              fluidRow(
                fluidPage(
                  fluidRow(
                    column(
                      12,
                      column(3, 
                               uiOutput("sectorOutput"),
                               uiOutput("industryOutput")
                           
                      ),
                      column(3,
                             uiOutput("symbolOutput"),
                             uiOutput("axislimits")
                             # ,uiOutput("operatorOutput")
                             # ,radioButtons('scale_choice',  'Scale type:', choices = c("free" = "free_y", "fixed" =  "fixed"), selected = "fixed", inline=TRUE)
                      )
                      ,column(2,
                      uiOutput("scaleOutput"),
                      uiOutput("volumeSelector")
             
                      )
                      ,column(4,
                              fluidRow(
                              uiOutput("date.selector") ,   
                              uiOutput("spanOutput")),
                     
                              uiOutput("dates")
                      )
                    )
                  ),
                  fluidRow(
                    column(
                      12,
                      mainPanel(
                        tabsetPanel(
                          type = "tabs",
                          tabPanel("Plot",   plotOutput("stocksplot")),
                          tabPanel("Data Table / Download", icon = icon("table") , HTML("<br>"),   downloadButton('downloadData', 'Download selected data') , HTML("<br><br>"),   DTOutput("results"))
                        ),
                        width = 12
                      )
                    )
                  )
                )
              )
            )
    ) # close tabItem stocks
    
    #stocks interaction tap ----------------------------------------
    ,tabItem(tabName = "stocksint",
             fluidPage(  
               fluidRow(
                 column(
                   12,
                   mainPanel(
                     tabsetPanel(
                       type = "tabs",
                       tabPanel("x5i", icon = icon("table") ,  DTOutput("x5i")),
                       tabPanel("x9i", icon = icon("table") ,  DTOutput("x9i")),
                       tabPanel("x14i", icon = icon("table") ,  DTOutput("x14i")),
                       tabPanel("x21i", icon = icon("table") ,  DTOutput("x21i")),
                       tabPanel("x30i", icon = icon("table") ,  DTOutput("x30i")),
                       tabPanel("sumi", icon = icon("table") ,  DTOutput("sumi"))
                       
                       
                     ),width = 12
                   )
                 )
               )
               
               
             )
    )# close stocks crossover tables
    
    ,tabItem(tabName = "stockscross",
            fluidPage(  
                  fluidRow(
                    column(
                      12,
                      mainPanel(
                        tabsetPanel(
                          type = "tabs",
                          tabPanel("X9 - X5", icon = icon("table") ,  DTOutput("x9x5")),
                          tabPanel("X14 - X9", icon = icon("table") ,  DTOutput("x14x9")),
                          tabPanel("X21 - X14", icon = icon("table") ,  DTOutput("x21x14")),
                          tabPanel("X30 - X21", icon = icon("table") ,  DTOutput("x30x21")),
                          tabPanel("X30 - X14", icon = icon("table") ,  DTOutput("x30x14"))
                         
                        
                      ),width = 12
                    )
                  )
                )
             
           
    )
    )# close stocks crossover tables
    
    ,tabItem(tabName = "etfcross",
             fluidPage(  
               fluidRow(
                 column(
                   12,
                   mainPanel(
                     tabsetPanel(
                       type = "tabs",
                       tabPanel("X9 - X5", icon = icon("table") ,  DTOutput("etf9x5")),
                       tabPanel("X14 - X9", icon = icon("table") ,  DTOutput("etf14x9")),
                       tabPanel("X21 - X14", icon = icon("table") ,  DTOutput("etf21x14")),
                       tabPanel("X30 - X21", icon = icon("table") ,  DTOutput("etf30x21")),
                       tabPanel("X30 - X14", icon = icon("table") ,  DTOutput("etf30x14"))
                       
                     ),width = 12
                   )
                 )
               )
               
               
             )
    )# close stocks crossover tables
    
    
    # xgroups tab ------------------------ 
    , tabItem(
      tabName =  "xgroups"
      ,fluidPage(
        fluidRow(
          fluidPage(
            fluidRow(
              column(12,
                     column(2, 
                            uiOutput("xgroupOutput")
                     ),
                     column(3,
                            uiOutput("date.selector_met"),
                            uiOutput("dates_met")),
                     column(2,
                            radioButtons('scale_choice_met',  'Scale type:', choices = c("free" = "free_y", "fixed" =  "fixed"), selected = "fixed" )
                     )
              )
            ),
            fluidRow(column(
              12,
              mainPanel(
                tabsetPanel(
                  type = "tabs",
                  
                  tabPanel("Plot_xgroups",   plotOutput("xgroup_plots")),
                  # tabPanel("Plot",  uiOutput("dyn_tabPanel")),
                  tabPanel("Xplot data",  HTML("<br>") , HTML("<br><br>"),   DTOutput("results_met"))
                ),
                width = 12
                
              )
            )
            )
          )
        )
      )
    ) # CLOSE OF TABITEM xgroups
    # etfs tab ------------------------ 
    , tabItem(
      tabName = "etf"
      ,fluidPage(
        fluidRow(
          fluidPage(
            fluidRow(
              column(12,
                     column(3, 
                            uiOutput("etfgroupOutput"))
                     
                     ,column(3,
                             uiOutput("date.selector_etf"),
                             uiOutput("dates_etf"))
                     ,column(6, 
                             column(3, 
                             uiOutput("axislimitsetf")),
                             column(3, 
                             radioButtons('scale_choice_etf',  'Scale type:', choices = c("free" = "free_y", "fixed" =  "fixed"), selected = "fixed" ) )
                     )
              )
            ),
            fluidRow(column(
              12,
              mainPanel(
                tabsetPanel(
                  type = "tabs",
                  
                  tabPanel("Plot_etf",   plotOutput("etf_plots"
                                                    # ,width = "1200px", height=  "700px"
                  )),
                  # tabPanel("Plot",  uiOutput("dyn_tabPanel")),
                  tabPanel("Etf data",  HTML("<br>") , HTML("<br><br>"),   DTOutput("results_etf"))
                ),
                width = 12
                
              )
            )
            )
          )
        )
        
      )
    )
    
    # EQI focus tab ------------------------
    , tabItem(
      tabName = "eqifocus",
      div(
        class = "eqi-dashboard",
        div(
          class = "eqi-topbar",
          div(
            class = "eqi-brand",
            div(class = "eqi-logo-mark", "EQ"),
            div(
              div(class = "eqi-title", "EcoQuant Insight Premium"),
              div(class = "eqi-subtitle", "Signal intelligence dashboard")
            )
          ),
          div(class = "eqi-asof", paste("Data as of", format(latest_app_date, "%b %d, %Y")))
        ),
        div(
          class = "eqi-grid",
          div(
            class = "eqi-filter-panel",
            div(class = "eqi-panel-title", "Dashboard Filters"),
            selectInput(
              "eqiTickerGroupInput",
              "Board / Ticker Group",
              choices = names(eqi_ticker_groups),
              selected = "EQI Top 20"
            ),
            selectizeInput(
              "eqiTickerInput",
              "Stock",
              choices = NULL,
              selected = NULL,
              options = list(placeholder = "Type a ticker", create = FALSE)
            ),
            selectInput(
              "eqiWindowInput",
              "Time Window",
              choices = c("30 trading days" = 30, "60 trading days" = 60, "90 trading days" = 90, "120 trading days" = 120, "180 trading days" = 180, "252 trading days" = 252),
              selected = 90
            ),
            selectInput(
              "eqiLoessPreset",
              "Trend Smoothing",
              choices = c(
                "Raw LR endpoints" = "none",
                "LOESS 0.20" = "0.20",
                "LOESS 0.30" = "0.30",
                "LOESS 0.35" = "0.35",
                "LOESS 0.50" = "0.50",
                "LOESS 0.65" = "0.65",
                "Custom LOESS" = "custom"
              ),
              selected = "0.35"
            ),
            conditionalPanel(
              "input.eqiLoessPreset == 'custom'",
              sliderInput("eqiLoessSpan", "Custom LOESS span", min = 0.10, max = 0.80, value = 0.35, step = 0.05)
            ),
            checkboxInput("eqiLoessRobust", "Robust LOESS", value = TRUE),
            checkboxInput("eqiPriceOverlay", "Price Overlay", value = TRUE),
            checkboxInput("eqiDarkTheme", "Dark mode", value = FALSE),
            selectInput(
              "eqiPalette",
              "Line Palette",
              choices = names(eqi_focus_palettes),
              selected = "Classic"
            ),
            selectInput(
              "eqiPlotHeight",
              "Plot Size",
              choices = c("Standard" = 520, "Large" = 650, "Extra Large" = 780, "Presentation" = 920),
              selected = 650
            ),
            actionButton("eqiFocusZoomReset", "Reset Zoom"),
            helpText("Drag on the chart to zoom. Double-click or use Reset Zoom to return to the full view."),
            div(class = "eqi-panel-title", "Signal Scope"),
            tags$div(class = "eqi-mini-list", uiOutput("eqi_filter_summary"))
          ),
          div(
            uiOutput("eqi_kpi_strip"),
            div(
              class = "eqi-panel eqi-chart-panel",
              div(class = "eqi-panel-title", textOutput("eqi_chart_title", inline = TRUE)),
              uiOutput("eqi_focus_plot_ui")
            )
          ),
          div(
            class = "eqi-right-stack",
            div(
              class = "eqi-panel eqi-side-panel",
              div(class = "eqi-panel-title", "Stock Details"),
              uiOutput("eqi_stock_detail_panel")
            ),
            div(
              class = "eqi-panel eqi-side-panel",
              div(class = "eqi-panel-title", "Signal Status"),
              uiOutput("eqi_signal_status_panel")
            ),
            div(
              class = "eqi-panel eqi-side-panel",
              div(class = "eqi-panel-title", "Latest Sector Heatmap"),
              uiOutput("eqi_heatmap_panel")
            )
          )
        ),
        div(
          class = "eqi-bottom-grid",
          div(
            class = "eqi-table-panel",
            div(class = "eqi-panel-title", "Promotions, Entries, Demotions, Exits"),
            DTOutput("eqi_top20_changes")
          ),
          div(
            class = "eqi-table-panel",
            div(class = "eqi-panel-title", "Top 50 Rank Board"),
            DTOutput("eqi_top50_rank")
          )
        ),
        div(
          class = "eqi-table-panel",
          style = "margin-top:10px;",
          tabsetPanel(
            type = "tabs",
            tabPanel("Ticker Snapshot", DTOutput("eqi_ticker_snapshot"), HTML("<br>"), DTOutput("eqi_ticker_history")),
            tabPanel("Top 50 Tenure", DTOutput("eqi_top50_tenure")),
            tabPanel("Volatility Top 50", DTOutput("eqi_vol_top50")),
            tabPanel("Rank History", DTOutput("eqi_rank_history"))
          )
        )
      )
    )

    # EQI master database tab ------------------------
    , tabItem(
      tabName = "eqimaster",
      fluidPage(
        fluidRow(
          column(
            12,
            mainPanel(
              tabsetPanel(
                type = "tabs",
                tabPanel("Daily Ranked Universe", icon = icon("table"), DTOutput("eqi_daily_ranked_universe")),
                tabPanel("TopN Events Today", icon = icon("table"), DTOutput("eqi_topN_events_vol_today")),
                tabPanel("TopN Exits", icon = icon("table"), DTOutput("eqi_topN_exits_vol")),
                tabPanel("Active Signals", icon = icon("table"), DTOutput("eqi_active_signals_today")),
                tabPanel("Status Changes", icon = icon("table"), DTOutput("eqi_status_changes_today")),
                tabPanel("Broken Signals", icon = icon("table"), DTOutput("eqi_broken_signals_today")),
                tabPanel("Status Summary", icon = icon("table"), DTOutput("eqi_signal_status_summary_today")),
                tabPanel("Continuity Exclusions", icon = icon("table"), DTOutput("eqi_continuity_exclusions")),
                tabPanel("EQMI Daily", icon = icon("bar-chart"), DTOutput("eqi_eqmi_daily")),
                tabPanel("EQMI Sector", icon = icon("bar-chart"), DTOutput("eqi_eqmi_sector_daily"))
              ),
              width = 12
            )
          )
        )
      )
    )
    
    # xplots tab ------------------------ 
    , tabItem(
      tabName =  "plotsx"
      ,fluidPage(
        fluidRow(
          fluidPage(
            fluidRow(
              column(12,
                     column(2,
                            uiOutput("sectorOutput_x")
                     ),
                     column(2,
                            uiOutput("industryOutput_x")
                     ),
                     column(2,
                            uiOutput("date.selector_x")
                            ),
                     column(2,
                            uiOutput("dates_x")
                            ),
                     column(2,
                            uiOutput("axislimits_x")
                     ),
                     
                        column(2,
                     uiOutput("scaleOutput_x")
                     )
              )
            ),
            fluidRow(column(
              12,
              mainPanel(
                tabsetPanel(
                  type = "tabs",
                  
                  tabPanel("Plot_x",   plotOutput("xplots")),
                  # tabPanel("Plot",  uiOutput("dyn_tabPanel")),
                  tabPanel("Xdata",  HTML("<br>") , HTML("<br><br>"),   DTOutput("resultsx"))
                ),
                width = 12
                
              )
            )
            )
          )
        )
      )
    )
    
     # CLOSE OF TABITEM xgroups
    
  )
  )
  )# end hidden
  # close tabItems
  
) # end dashboardbody


# Put them together into a dashboardPage
ui <-dashboardPage(
  dashboardHeader(title = 'EcoQuant Intel Plots'
  ),
  
  sidebar,
  body
)


#xplots tab


##----Server------------------------------
server <- function(input, output, session) {
  if (is.function(session$allowReconnect)) {
    session$allowReconnect(TRUE)
  }
  eqi_focus_zoom_x <- reactiveVal(NULL)
  eqi_focus_zoom_y <- reactiveVal(NULL)
  observeEvent(input$client_heartbeat, {
    session$userData$last_client_heartbeat <- input$client_heartbeat
    session$userData$last_client_visibility <- input$client_visibility
  }, ignoreInit = TRUE)
  # 
  observeEvent(input$eqiTickerGroupInput, {
    choices <- eqi_ticker_groups[[input$eqiTickerGroupInput]]
    if (is.null(choices) || length(choices) == 0) {
      choices <- all_eqi_symbols
    }
    current <- if (is.null(input$eqiTickerInput)) "" else toupper(input$eqiTickerInput)
    selected <- if (current %in% choices) current else choices[1]
    updateSelectizeInput(
      session,
      "eqiTickerInput",
      choices = choices,
      selected = selected,
      server = TRUE
    )
  }, ignoreNULL = FALSE)

  # call login module supplying data frame, user and password cols
  # and reactive trigger
  credentials <- shinyauthr::loginServer(
    id = "login",
    data = user_base,
    user_col = user,
    pwd_col = password,
    cookie_logins = TRUE,
    sessionid_col = sessionid,
    cookie_getter = get_remembered_sessions,
    cookie_setter = save_remembered_session,
    log_out = reactive(logout_init())
  )

  logout_init <- shinyauthr::logoutServer(
    id = "logout",
    active = reactive(credentials()$user_auth)
  )
  user_data <- reactive({credentials()$info})
  observe({
    shinyjs::hide("form1")
    req(credentials()$user_auth)
    shinyjs::show("form1")

  })
  

  #------xplot variables ------------------------------------
  
  output$date.selector_x<- renderUI({
    radioButtons('date.selector_x',  label="Select Dates:",  c("Slider", "Calendar"), selected="Slider",inline = TRUE)
  })
  
  observe({
    updateRadioButtons(session, 'date.selector_x',  label="Select Date Type:",  c("Slider", "Calendar"), selected=input$date.selector_x,inline = TRUE)
  })
  
  observeEvent(input$date.selector_x, {
    
    observe({
      
      if (input$date.selector_x == "Slider"){
        dates <- unique(m$date)
        output$dates_x<- renderUI({
          minval <- min(dates)
          maxval <- max(dates)
          sliderInput("dates_x",label = NULL,
                      min = minval, max = maxval,
                      value = date_default(dates), width="80%"
          )
        })
      }
      if (input$date.selector_x == "Calendar"){
        dates <- unique(m$date)
        output$dates_x<- renderUI({
          minval <- min(dates)
          maxval <- max(dates)
          dateRangeInput('dates_x', label = NULL,
                         start =minval, end = maxval,
                         min = minval, max = maxval,
                         separator = " - ", format = "yyyy-mm-dd",
                         language = 'en', weekstart = 0
          )
        })
      }
    })
    
    
  })
  
  
  output$axislimits_x <- renderUI({
    sliderInput("axislimits_x", label = "Y-axis range", min = -0.75,
                max = 0.75, value = c(-.5 ,.3),step=.2)
    
  })
  
  
  output$sectorOutput_x <- renderUI({
    pickerInput(inputId  = 'sectorInput_x',
                label = 'Select sector:',
                choices  = sectors_x,  selected =  NULL,
                multiple = TRUE
                ,  options = pickerOptions(
                  actionsBox = TRUE,
                  liveSearch = TRUE
                )
    )
  })
  
  output$industryOutput_x <- renderUI({
    pickerInput(inputId  = 'industryInput_x',
                label = 'Select Industry:',
                if(!is.null(input$sectorInput_x) )  {  choices =    c("",  industries_x  %>% filter(sector %in% input$sectorInput_x) %>% select(industry) %>% unname()%>% unlist() %>% factor() %>% levels())  } else
                {choices =    allindustries_x}
                ,selected = "",
                multiple =TRUE,
                options = pickerOptions(
                    actionsBox = TRUE,
                  liveSearch = TRUE
                )
    )
  })
  
  #Select all / Unselect all
  output$scaleOutput_x <- renderUI({
    pickerInput(inputId  = 'scaleInput_x',
                label = 'Select scale:',
                choices  = scalesx,   selected =c('x1', 'x2' ,'x3', 'x4','x5' , 'x9'  ,  'x14' ,'x21' ,'x30'),
                multiple = TRUE,
                options = list(`actions-box` = TRUE)
    )
  })
  
  #------xplot data tab filter data based on user input------
  # data_xplots <- reactive({
  #   m %>%   filter(   date >= input$dates_x[1],
  #                     date <= input$dates_x[2],
  #                     variable %in% input$scaleInput_x
  #   )
  # })
  
  
 
  
  
  
  data_xplots<- reactive({
    industry_selected <- !is.null(input$industryInput_x) && any(input$industryInput_x != "")
    if(!industry_selected)
   { datax <-   m %>%
      filter(
        date >= input$dates_x[1],
        date <= input$dates_x[2],
        variable %in% input$scaleInput_x
      )
    datax<-  datax %>% filter(sector %in% input$sectorInput_x

    )
    }
    
    if(industry_selected) {   
      
      datax <-   indmeans %>%
        filter(
          date >= input$dates_x[1],
          date <= input$dates_x[2],
          variable %in% input$scaleInput_x
        )
      datax<-  datax %>% filter(sector %in% input$sectorInput_x,
                                    industry %in% input$industryInput_x
      )
      
    
      
      }
    
    datax
    
  })
  
  

  
  output$resultsx <- DT::renderDT(
  # ifelse(input$inputIndustry_x =="" , data_xplots(), data_indplots()),
    data_xplots(),
   caption = "Results",filter = c("top"),
    extensions = c('Buttons', 'ColReorder','KeyTable'),
    options = list( pageLength = 50, autoWidth = TRUE, colReorder=TRUE,
                    dom = 'Bfrtip', keys = TRUE,
                    # columnDefs = list(list(width = '5px', targets = list(4:25)),
                    #                   list(width = '25px', targets = list(1,2,3,26))),
                    buttons = c('copy', 'csv', 'excel', 'pdf', 'print')
    )
  )
  
  #------EQI focus outputs ------------------------------------
  render_eqi_dt <- function(data, page_length = 25) {
    DT::datatable(
      data,
      filter = "top",
      extensions = c('Buttons', 'ColReorder','KeyTable'),
      options = list(
        pageLength = page_length,
        autoWidth = TRUE,
        colReorder = TRUE,
        dom = 'Bfrtip',
        keys = TRUE,
        scrollX = TRUE,
        buttons = c('copy', 'csv', 'excel', 'print')
      )
    )
  }

  fmt_num <- function(x, digits = 2) {
    ifelse(is.na(x), NA, round(x, digits))
  }

  fmt_pct <- function(x, digits = 1) {
    ifelse(is.na(x), NA, paste0(round(100 * x, digits), "%"))
  }

  eqi_metric_card <- function(label, value, subvalue = NULL, tone = "neutral", icon_name = "line-chart") {
    div(
      class = paste("eqi-card", tone),
      div(class = "eqi-card-icon", icon(icon_name)),
      div(
        class = "eqi-card-body",
        div(class = "eqi-card-label", label),
        div(class = "eqi-card-value", value),
        if (!is.null(subvalue)) div(class = "eqi-card-sub", subvalue)
      )
    )
  }

  eqi_detail_item <- function(label, value, value_class = "") {
    div(
      div(class = "eqi-detail-label", label),
      div(class = paste("eqi-detail-value", value_class), value)
    )
  }

  eqi_top20_changes_view <- eqi_top20_changes %>%
    transmute(
      Type = change_type,
      Symbol = symbol,
      Sector = sector,
      Industry = industry,
      Rank = rank_EQ,
      `Prior Rank` = rank_EQ_yday,
      `Rank Change` = delta_rank,
      `EQ Score` = fmt_num(EQ_score_vol, 4),
      `D30 Volume` = round(d30_volume),
      Price = fmt_num(close_price, 2)
    )

  eqi_top50_rank_view <- eqi_top50_rank %>%
    arrange(rank_EQ) %>%
    transmute(
      Rank = rank_EQ,
      Symbol = symbol,
      Sector = sector,
      Industry = industry,
      `EQ Score` = fmt_num(EQ_score_vol, 4),
      `D30 Volume` = round(d30_volume),
      Price = fmt_num(close_price, 2)
    )

  eqi_top50_tenure_view <- eqi_top50_tenure %>%
    arrange(rank_EQ) %>%
    transmute(
      Rank = rank_EQ,
      Symbol = symbol,
      Sector = sector,
      Industry = industry,
      `EQ Score` = fmt_num(EQ_score_vol, 4),
      `D30 Volume` = round(d30_volume),
      `First Top50 Date` = as.Date(first_topN_date),
      `First Top50 Price` = fmt_num(first_topN_close, 2),
      Price = fmt_num(close_price, 2),
      `Days in Top50` = days_since_first_topN,
      `Return Since First` = fmt_pct(pct_return_since_first, 2)
    )

  eqi_vol_top50_view <- eqi_vol_top50 %>%
    arrange(rank_vol) %>%
    transmute(
      Rank = rank_vol,
      Symbol = symbol,
      Sector = sector,
      Industry = industry,
      Price = fmt_num(close_price, 2),
      `D30 Volume` = round(d30_volume),
      `Avg Abs Ret 20D` = fmt_pct(avg_abs_ret_20, 2),
      `3% Days` = hit_3pct_20,
      `5% Days` = hit_5pct_20,
      `HV 20D` = fmt_pct(hv_20, 2),
      `Max Abs Ret 20D` = fmt_pct(max_abs_ret_20, 2),
      `Vol Score` = fmt_num(swing_score_1d, 4)
    )

  eqi_rank_history_view <- eqi_topN_events_vol %>%
    arrange(desc(date), rank_EQ) %>%
    transmute(
      Date = as.Date(date),
      Symbol = symbol,
      Rank = rank_EQ,
      Sector = sector,
      Industry = industry,
      `EQ Score` = fmt_num(EQ_score_vol, 4),
      `D30 Volume` = round(d30_volume),
      Price = fmt_num(close_price, 2)
    )

  selected_ticker_history <- reactive({
    req(input$eqiTickerInput)
    sym <- toupper(input$eqiTickerInput)
    stock_history[symbol == sym][order(date)]
  })

  selected_ticker_latest <- reactive({
    d <- selected_ticker_history()
    req(nrow(d) > 0)
    d[which.max(date)]
  })

  selected_ticker_rank <- reactive({
    req(input$eqiTickerInput)
    sym <- toupper(input$eqiTickerInput)
    eqi_top50_rank %>% filter(symbol == sym)
  })

  selected_ticker_tenure <- reactive({
    req(input$eqiTickerInput)
    sym <- toupper(input$eqiTickerInput)
    eqi_top50_tenure %>% filter(symbol == sym)
  })

  selected_time_window <- reactive({
    window <- suppressWarnings(as.integer(input$eqiWindowInput %||% 90))
    if (is.na(window) || window < 10) 90 else window
  })

  selected_ticker_return_90d <- reactive({
    d <- selected_ticker_history()
    req(nrow(d) > 0)
    keep_dates <- tail(sort(unique(as.Date(d$date))), selected_time_window())
    window <- d[as.Date(date) %in% keep_dates]
    if (nrow(window) < 2 || !is.finite(window$close_price[1]) || window$close_price[1] <= 0) {
      return(NA_real_)
    }
    tail(window$close_price, 1) / window$close_price[1] - 1
  })

  selected_ticker_lr <- reactive({
    d <- selected_ticker_history()
    req(nrow(d) > 1)
    d <- as.data.frame(d)
    d <- d %>% arrange(date)
    keep_dates <- tail(sort(unique(as.Date(d$date))), selected_time_window())
    d <- d %>% filter(date %in% keep_dates)
    slope_cols <- intersect(eqi_slope_cols, names(d))
    req(length(slope_cols) > 0)
    plot_long <- reshape2::melt(
      d[, c("symbol", "date", "close_price", slope_cols)],
      id.vars = c("symbol", "date", "close_price"),
      measure.vars = slope_cols,
      variable.name = "slope_col",
      value.name = "slope_value"
    )
    plot_long$tf <- sub("slope$", "", as.character(plot_long$slope_col))
    plot_long <- as.data.table(plot_long)
    setorder(plot_long, symbol, tf, date)
    plot_long[, lr_value := rolling_lr_endpoint(slope_value, eqi_lr_lengths[tf[1]]), by = .(symbol, tf)]
    plot_long[, lr_plot_value := lr_value * eqi_lr_display_multiplier]
    plot_long[, price := close_price]
    as.data.frame(plot_long)
  })

  selected_eqi_loess_span <- reactive({
    preset <- input$eqiLoessPreset %||% "0.35"
    if (identical(preset, "custom")) {
      span <- suppressWarnings(as.numeric(input$eqiLoessSpan %||% 0.35))
    } else if (identical(preset, "none")) {
      span <- NA_real_
    } else {
      span <- suppressWarnings(as.numeric(preset))
    }
    if (is.na(span)) {
      return(NA_real_)
    }
    max(0.10, min(0.80, span))
  })

  selected_ticker_lr_plot <- reactive({
    d <- selected_ticker_lr()
    req(nrow(d) > 0)
    dt <- as.data.table(d)
    dt[, plot_lr_value := lr_plot_value]
    span <- selected_eqi_loess_span()
    if (is.finite(span)) {
      loess_family <- if (isTRUE(input$eqiLoessRobust)) "symmetric" else "gaussian"
      dt[, plot_lr_value := loess_smooth_series(date, lr_plot_value, span = span, family = loess_family), by = tf]
      dt[!is.finite(plot_lr_value), plot_lr_value := lr_plot_value]
    }
    as.data.frame(dt)
  })

  selected_eqi_focus_palette <- reactive({
    palette_name <- input$eqiPalette %||% "Classic"
    palette <- eqi_focus_palettes[[palette_name]]
    if (is.null(palette)) {
      palette <- eqi_focus_palettes[["Classic"]]
    }
    palette
  })

  output$eqi_focus_plot_ui <- renderUI({
    plot_height <- suppressWarnings(as.integer(input$eqiPlotHeight %||% 650))
    if (is.na(plot_height) || plot_height < 400) {
      plot_height <- 650
    }
    plotOutput(
      "eqi_focus_plot",
      height = paste0(plot_height, "px"),
      brush = brushOpts(id = "eqi_focus_plot_brush", direction = "xy", resetOnNew = TRUE),
      dblclick = "eqi_focus_plot_dblclick"
    )
  })

  observeEvent(input$eqiTickerInput, {
    eqi_focus_zoom_x(NULL)
    eqi_focus_zoom_y(NULL)
  }, ignoreInit = TRUE)

  observeEvent(input$eqiWindowInput, {
    eqi_focus_zoom_x(NULL)
    eqi_focus_zoom_y(NULL)
  }, ignoreInit = TRUE)

  observeEvent(input$eqiDarkTheme, {
    target_palette <- if (isTRUE(input$eqiDarkTheme)) "Bright Dark" else "Classic"
    if (!identical(input$eqiPalette, target_palette)) {
      updateSelectInput(session, "eqiPalette", selected = target_palette)
    }
  }, ignoreInit = TRUE)

  observeEvent(input$eqi_focus_plot_brush, {
    brush <- input$eqi_focus_plot_brush
    req(!is.null(brush))
    date_range <- coerce_plot_date_range(brush$xmin, brush$xmax)
    if (!is.null(date_range)) {
      eqi_focus_zoom_x(date_range)
    }
    if (is.finite(brush$ymin) && is.finite(brush$ymax)) {
      eqi_focus_zoom_y(sort(c(brush$ymin, brush$ymax)))
    }
  })

  observeEvent(input$eqi_focus_plot_dblclick, {
    eqi_focus_zoom_x(NULL)
    eqi_focus_zoom_y(NULL)
  })

  observeEvent(input$eqiFocusZoomReset, {
    eqi_focus_zoom_x(NULL)
    eqi_focus_zoom_y(NULL)
  })

  selected_ticker_snapshot <- reactive({
    latest <- as.data.frame(selected_ticker_latest())
    rank_row <- selected_ticker_rank()
    tenure_row <- selected_ticker_tenure()
    ret90 <- selected_ticker_return_90d()

    data.frame(
      Metric = c(
        "Symbol", "Latest Date", "Sector", "Industry", "EQI Rank", "EQI Score",
        "Price", "D30 Volume", paste0(selected_time_window(), "D Return"), "First Top50 Date",
        "Days in Top50", "Return Since First Top50"
      ),
      Value = c(
        latest$symbol[1],
        as.character(as.Date(latest$date[1])),
        latest$sector[1],
        latest$industry[1],
        if (nrow(rank_row) > 0) as.character(rank_row$rank_EQ[1]) else "Not Top 50",
        if (nrow(rank_row) > 0) as.character(fmt_num(rank_row$EQ_score_vol[1], 4)) else NA,
        as.character(fmt_num(latest$close_price[1], 2)),
        as.character(round(latest$d30_volume[1])),
        as.character(fmt_pct(ret90, 2)),
        if (nrow(tenure_row) > 0) as.character(as.Date(tenure_row$first_topN_date[1])) else NA,
        if (nrow(tenure_row) > 0) as.character(tenure_row$days_since_first_topN[1]) else NA,
        if (nrow(tenure_row) > 0) as.character(fmt_pct(tenure_row$pct_return_since_first[1], 2)) else NA
      ),
      stringsAsFactors = FALSE
    )
  })

  latest_heatmap_file <- reactive({
    heatmap_dir <- file.path(app_dir, "www", "heatmap")
    if (!dir.exists(heatmap_dir)) {
      return(NA_character_)
    }
    files <- list.files(
      heatmap_dir,
      pattern = "^sectors_dual_branded_.*\\.png$",
      recursive = TRUE,
      full.names = TRUE
    )
    if (length(files) == 0) {
      return(NA_character_)
    }
    files[which.max(file.info(files)$mtime)]
  })

  heatmap_web_path <- function(heatmap_file) {
    if (is.na(heatmap_file) || !file.exists(heatmap_file)) {
      return(NA_character_)
    }
    www_dir <- normalizePath(file.path(app_dir, "www"), mustWork = TRUE)
    normalized_file <- normalizePath(heatmap_file, mustWork = TRUE)
    if (!startsWith(normalized_file, www_dir)) {
      return(NA_character_)
    }
    relative_path <- sub("^/+", "", substring(normalized_file, nchar(www_dir) + 1L))
    URLencode(gsub("\\\\", "/", relative_path), reserved = FALSE)
  }

  latest_eqmi_row <- reactive({
    if (nrow(eqi_eqmi_daily) == 0) {
      return(data.frame())
    }
    eqi_eqmi_daily %>%
      arrange(date) %>%
      tail(1)
  })

  latest_sector_eqmi_row <- reactive({
    latest <- as.data.frame(selected_ticker_latest())
    if (nrow(eqi_eqmi_sector_daily) == 0 || is.null(latest$sector[1]) || is.na(latest$sector[1])) {
      return(data.frame())
    }
    eqi_eqmi_sector_daily %>%
      filter(sector == latest$sector[1]) %>%
      arrange(date) %>%
      tail(1)
  })

  output$eqi_filter_summary <- renderUI({
    group_name <- input$eqiTickerGroupInput %||% "EQI Top 20"
    choices <- eqi_ticker_groups[[group_name]]
    if (is.null(choices)) choices <- character()
    tagList(
      div(class = "eqi-mini-row", span("Board Size"), strong(length(choices))),
      div(class = "eqi-mini-row", span("Time Window"), strong(paste(selected_time_window(), "days"))),
      div(class = "eqi-mini-row", span("Top 50 Names"), strong(nrow(eqi_top50_rank))),
      div(class = "eqi-mini-row", span("Change Rows"), strong(nrow(eqi_top20_changes))),
      div(class = "eqi-mini-row", span("Volatility Names"), strong(nrow(eqi_vol_top50)))
    )
  })

  output$eqi_chart_title <- renderText({
    req(input$eqiTickerInput)
    paste0(toupper(input$eqiTickerInput), " - ", selected_time_window(), " Day Smoothed Slope Performance")
  })

  output$eqi_kpi_strip <- renderUI({
    req(input$eqiTickerInput)
    latest <- as.data.frame(selected_ticker_latest())
    rank_row <- selected_ticker_rank()
    score_value <- if (nrow(rank_row) > 0) fmt_num(rank_row$EQ_score_vol[1], 3) else "N/A"
    rank_value <- if (nrow(rank_row) > 0) paste0("#", rank_row$rank_EQ[1]) else "Off Board"
    rank_sub <- if (nrow(rank_row) > 0) paste0("Top ", fmt_num(100 * rank_row$rank_EQ[1] / max(nrow(stock_history[date == max(date)]), 1), 2), "%") else "Not in Top 50"
    eqmi_row <- latest_eqmi_row()
    sector_eqmi_row <- latest_sector_eqmi_row()
    eqmi_value <- if (nrow(eqmi_row) > 0) fmt_num(eqmi_row$EQMI[1], 1) else "N/A"
    eqmi_sub <- if (nrow(sector_eqmi_row) > 0) paste0(latest$sector[1], " ", fmt_num(sector_eqmi_row$EQMI[1], 1)) else "Market momentum"
    div(
      class = "eqi-kpi-strip",
      eqi_metric_card("EQ Score (Vol)", score_value, "Volume-weighted signal", "neutral", "line-chart"),
      eqi_metric_card("EQ Rank", rank_value, rank_sub, if (nrow(rank_row) > 0) "" else "warn", "star-o"),
      eqi_metric_card("Sector", latest$sector[1], latest$industry[1], "neutral", "industry"),
      eqi_metric_card("D30 Volume", format(round(latest$d30_volume[1]), big.mark = ","), "Avg. shares", "neutral", "bar-chart"),
      eqi_metric_card("EQMI", eqmi_value, eqmi_sub, "neutral", "tachometer")
    )
  })

  output$eqi_stock_detail_panel <- renderUI({
    req(input$eqiTickerInput)
    latest <- as.data.frame(selected_ticker_latest())
    rank_row <- selected_ticker_rank()
    tenure_row <- selected_ticker_tenure()
    ret90 <- selected_ticker_return_90d()
    rank_value <- if (nrow(rank_row) > 0) paste0("#", rank_row$rank_EQ[1]) else "Not Top 50"
    score_value <- if (nrow(rank_row) > 0) fmt_num(rank_row$EQ_score_vol[1], 4) else "N/A"
    first_top50 <- if (nrow(tenure_row) > 0) as.character(as.Date(tenure_row$first_topN_date[1])) else "N/A"
    days_top50 <- if (nrow(tenure_row) > 0) tenure_row$days_since_first_topN[1] else "N/A"
    tagList(
      div(
        class = "eqi-detail-grid",
        eqi_detail_item("Symbol", latest$symbol[1]),
        eqi_detail_item("Company", latest$name[1] %||% latest$symbol[1]),
        eqi_detail_item("Sector", latest$sector[1]),
        eqi_detail_item("Industry", latest$industry[1]),
        eqi_detail_item("Rank", rank_value),
        eqi_detail_item("EQI Score", score_value),
        eqi_detail_item("D30 Volume", format(round(latest$d30_volume[1]), big.mark = ",")),
        eqi_detail_item(paste0(selected_time_window(), "D Return"), fmt_pct(ret90, 2), if (!is.na(ret90) && ret90 >= 0) "eqi-positive" else "eqi-negative"),
        eqi_detail_item("First Top50", first_top50),
        eqi_detail_item("Days Top50", days_top50)
      )
    )
  })

  output$eqi_signal_status_panel <- renderUI({
    summary_data <- eqi_signal_status_summary_today
    if (nrow(summary_data) == 0) {
      return(div(class = "eqi-card-sub", "Lifecycle outputs will appear after the next full RDS build."))
    }
    rows <- lapply(seq_len(nrow(summary_data)), function(i) {
      div(
        class = "eqi-mini-row",
        span(summary_data$status_label[i]),
        strong(summary_data$n_signals[i])
      )
    })
    active_count <- if (nrow(eqi_active_signals_today) > 0) nrow(eqi_active_signals_today) else 0
    broken_count <- if (nrow(eqi_broken_signals_today) > 0) nrow(eqi_broken_signals_today) else 0
    tagList(
      div(class = "eqi-mini-row", span("Active Signals"), strong(class = "eqi-positive", active_count)),
      div(class = "eqi-mini-row", span("Broken Signals"), strong(class = "eqi-negative", broken_count)),
      rows
    )
  })

  output$eqi_heatmap_panel <- renderUI({
    heatmap_file <- latest_heatmap_file()
    if (is.na(heatmap_file) || !file.exists(heatmap_file)) {
      return(div(class = "eqi-heatmap-empty", "Heatmap will appear after the next heatmap generation run."))
    }
    heatmap_url <- heatmap_web_path(heatmap_file)
    tagList(
      div(class = "eqi-card-sub", basename(heatmap_file)),
      div(
        class = "eqi-heatmap-actions",
        actionButton("eqiViewHeatmap", "View larger", icon = icon("expand")),
        tags$a(
          class = "btn",
          href = heatmap_url,
          target = "_blank",
          rel = "noopener noreferrer",
          icon("external-link"),
          "Open image"
        )
      ),
      div(class = "eqi-heatmap-image", imageOutput("eqi_sector_heatmap", height = "auto"))
    )
  })

  observeEvent(input$eqiViewHeatmap, {
    heatmap_file <- latest_heatmap_file()
    req(!is.na(heatmap_file), file.exists(heatmap_file))
    heatmap_url <- heatmap_web_path(heatmap_file)
    req(!is.na(heatmap_url))
    showModal(
      modalDialog(
        title = basename(heatmap_file),
        size = "l",
        easyClose = TRUE,
        class = "eqi-heatmap-modal",
        div(
          class = "eqi-heatmap-modal-body",
          tags$img(src = heatmap_url, alt = "Expanded sector heatmap")
        ),
        footer = tagList(
          tags$a(
            class = "btn btn-primary",
            href = heatmap_url,
            target = "_blank",
            rel = "noopener noreferrer",
            "Open image in new tab"
          ),
          modalButton("Close")
        )
      )
    )
  })

  output$eqi_sector_heatmap <- renderImage({
    heatmap_file <- latest_heatmap_file()
    req(!is.na(heatmap_file), file.exists(heatmap_file))
    list(src = heatmap_file, contentType = "image/png", alt = "Latest sector heatmap")
  }, deleteFile = FALSE)
  
  output$eqi_top20_changes <- DT::renderDT({
    render_eqi_dt(eqi_top20_changes_view, page_length = 25)
  })
  
  output$eqi_top50_tenure <- DT::renderDT({
    render_eqi_dt(eqi_top50_tenure_view, page_length = 50)
  })
  
  output$eqi_top50_rank <- DT::renderDT({
    render_eqi_dt(eqi_top50_rank_view, page_length = 50)
  })
  
  output$eqi_vol_top50 <- DT::renderDT({
    render_eqi_dt(eqi_vol_top50_view, page_length = 50)
  })
  
  output$eqi_rank_history <- DT::renderDT({
    render_eqi_dt(eqi_rank_history_view, page_length = 50)
  })

  output$eqi_daily_ranked_universe <- DT::renderDT({
    render_eqi_dt(eqi_daily_ranked_universe, page_length = 50)
  })

  output$eqi_topN_events_vol_today <- DT::renderDT({
    render_eqi_dt(eqi_topN_events_vol_today, page_length = 50)
  })

  output$eqi_topN_exits_vol <- DT::renderDT({
    render_eqi_dt(eqi_topN_exits_vol, page_length = 50)
  })

  output$eqi_active_signals_today <- DT::renderDT({
    render_eqi_dt(eqi_active_signals_today, page_length = 50)
  })

  output$eqi_status_changes_today <- DT::renderDT({
    render_eqi_dt(eqi_status_changes_today, page_length = 50)
  })

  output$eqi_broken_signals_today <- DT::renderDT({
    render_eqi_dt(eqi_broken_signals_today, page_length = 50)
  })

  output$eqi_signal_status_summary_today <- DT::renderDT({
    render_eqi_dt(eqi_signal_status_summary_today, page_length = 25)
  })

  output$eqi_continuity_exclusions <- DT::renderDT({
    render_eqi_dt(eqi_continuity_exclusions, page_length = 50)
  })

  output$eqi_eqmi_daily <- DT::renderDT({
    render_eqi_dt(eqi_eqmi_daily, page_length = 60)
  })

  output$eqi_eqmi_sector_daily <- DT::renderDT({
    render_eqi_dt(eqi_eqmi_sector_daily, page_length = 60)
  })

  output$eqi_ticker_snapshot <- DT::renderDT({
    DT::datatable(
      selected_ticker_snapshot(),
      rownames = FALSE,
      options = list(dom = 't', paging = FALSE, ordering = FALSE)
    )
  })

  output$eqi_ticker_history <- DT::renderDT({
    req(input$eqiTickerInput)
    sym <- toupper(input$eqiTickerInput)
    hist <- eqi_rank_history_view %>% filter(Symbol == sym)
    render_eqi_dt(hist, page_length = 25)
  })

  output$eqi_rank_box <- renderValueBox({
    rank_row <- selected_ticker_rank()
    valueBox(
      if (nrow(rank_row) > 0) paste0("#", rank_row$rank_EQ[1]) else "Not Top 50",
      "Latest EQI Rank",
      icon = icon("sort-numeric-asc"),
      color = if (nrow(rank_row) > 0) "green" else "yellow"
    )
  })

  output$eqi_score_box <- renderValueBox({
    rank_row <- selected_ticker_rank()
    valueBox(
      if (nrow(rank_row) > 0) fmt_num(rank_row$EQ_score_vol[1], 3) else "N/A",
      "EQI Score",
      icon = icon("line-chart"),
      color = "aqua"
    )
  })

  output$eqi_price_box <- renderValueBox({
    latest <- as.data.frame(selected_ticker_latest())
    valueBox(
      paste0("$", fmt_num(latest$close_price[1], 2)),
      "Latest Price",
      icon = icon("dollar-sign"),
      color = "blue"
    )
  })

  output$eqi_return_box <- renderValueBox({
    ret90 <- selected_ticker_return_90d()
    valueBox(
      fmt_pct(ret90, 2),
      paste0("Approx. ", selected_time_window(), "D Return"),
      icon = icon("percent"),
      color = if (!is.na(ret90) && ret90 >= 0) "green" else "red"
    )
  })
  
  output$eqi_focus_plot <- renderPlot({
    req(input$eqiTickerInput)
    d <- selected_ticker_lr_plot()
    req(nrow(d) > 0)
    rank_row <- selected_ticker_rank()
    rank_label <- if (nrow(rank_row) > 0) paste0("Latest rank: ", rank_row$rank_EQ[1]) else "Not currently Top 50"
    loess_span <- selected_eqi_loess_span()
    smoothing_label <- if (is.finite(loess_span)) {
      paste0(
        "LOESS span ", format(loess_span, nsmall = 2),
        if (isTRUE(input$eqiLoessRobust)) " robust" else ""
      )
    } else {
      "Raw LR endpoints"
    }
    
    finite_lr <- d$plot_lr_value[is.finite(d$plot_lr_value)]
    y_rng <- range(finite_lr, na.rm = TRUE)
    if (!all(is.finite(y_rng)) || y_rng[1] == y_rng[2]) {
      y_rng <- c(-10, 10)
    }
    y_pad <- diff(y_rng) * 0.08
    if (is.finite(y_pad) && y_pad > 0) {
      y_rng <- y_rng + c(-y_pad, y_pad)
    }
    focus_color_values <- selected_eqi_focus_palette()
    color_values <- c(focus_color_values, "Price (USD)" = "#64748b")
    linetype_values <- c(setNames(rep("solid", length(focus_color_values)), names(focus_color_values)), "Price (USD)" = "dotted")
    plot_base_size <- 13.2
    zoom_x <- eqi_focus_zoom_x()
    zoom_y <- eqi_focus_zoom_y()
    use_dark_theme <- isTRUE(input$eqiDarkTheme)
    if (is.null(zoom_y)) {
      zoom_y <- y_rng
    }
    zero_line_color <- if (use_dark_theme) "#64748b" else "#94a3b8"
    plot_bg_fill <- if (use_dark_theme) "#020617" else "#f3f6f9"
    panel_bg_fill <- if (use_dark_theme) "#0f172a" else "#fbfdff"
    grid_major_color <- if (use_dark_theme) "#1e293b" else "#d7e0e8"
    grid_minor_color <- if (use_dark_theme) "#172033" else "#edf2f7"
    axis_text_color <- if (use_dark_theme) "#dbe4ee" else "#334155"
    axis_title_color <- if (use_dark_theme) "#f8fafc" else "#0f172a"
    subtitle_color <- if (use_dark_theme) "#cbd5e1" else "#475569"
    legend_bg_fill <- if (use_dark_theme) alpha("#0f172a", 0.92) else alpha("#ffffff", 0.9)
    legend_bg_color <- if (use_dark_theme) "#334155" else "#d7e0e8"
    legend_key_fill <- if (use_dark_theme) "#0f172a" else "#fbfdff"
    legend_text_color <- if (use_dark_theme) "#f8fafc" else "#0f172a"
    
    p <- ggplot(d, aes(x = date)) +
      geom_hline(yintercept = 0, color = zero_line_color, linetype = "dashed") +
      geom_line(aes(y = plot_lr_value, color = tf, linetype = tf), linewidth = 0.95, na.rm = TRUE) +
      scale_color_manual(values = color_values, breaks = names(color_values)) +
      scale_linetype_manual(values = linetype_values, breaks = names(linetype_values)) +
      labs(
        title = NULL,
        subtitle = paste0(rank_label, " | ", selected_time_window(), " trading days | ", smoothing_label),
        x = NULL,
        y = paste0("Rolling slope LR endpoint ×", eqi_lr_display_multiplier),
        color = "Timeframe",
        linetype = "Timeframe"
      ) +
      coord_cartesian(xlim = zoom_x, ylim = zoom_y, expand = FALSE) +
      theme_minimal(base_size = plot_base_size) +
      theme(
        plot.background = element_rect(fill = plot_bg_fill, color = NA),
        panel.background = element_rect(fill = panel_bg_fill, color = NA),
        panel.grid.major = element_line(color = grid_major_color, linewidth = 0.35),
        panel.grid.minor = element_line(color = grid_minor_color, linewidth = 0.2),
        axis.text = element_text(color = axis_text_color, size = rel(1.1)),
        axis.title = element_text(color = axis_title_color, size = rel(1.1)),
        plot.subtitle = element_text(color = subtitle_color, size = rel(1.1)),
        legend.background = element_rect(fill = legend_bg_fill, color = legend_bg_color),
        legend.key = element_rect(fill = legend_key_fill, color = NA),
        legend.text = element_text(color = legend_text_color, size = rel(1.1)),
        legend.title = element_text(color = legend_text_color, size = rel(1.1)),
        legend.position = "bottom",
        axis.text.x = element_text(angle = 45, hjust = 1),
        strip.text = element_text(size = rel(1.1))
      )
    
    if (isTRUE(input$eqiPriceOverlay)) {
      price_data <- d %>% filter(tf == "x1", is.finite(price))
      if (nrow(price_data) > 1) {
        price_rng <- range(price_data$price, na.rm = TRUE)
        if (all(is.finite(price_rng)) && price_rng[1] != price_rng[2]) {
          price_data$price_scaled <- scales::rescale(price_data$price, to = y_rng, from = price_rng)
          price_to_axis <- function(x) {
            scales::rescale(x, to = y_rng, from = price_rng)
          }
          axis_to_price <- function(x) {
            scales::rescale(x, to = price_rng, from = y_rng)
          }
        p <- p +
          geom_line(
            data = price_data,
              aes(x = date, y = price_scaled, color = "Price (USD)", linetype = "Price (USD)"),
            linewidth = 0.8,
            inherit.aes = FALSE
            ) +
            scale_y_continuous(
              limits = y_rng,
              name = paste0("Rolling slope LR endpoint ×", eqi_lr_display_multiplier),
              sec.axis = sec_axis(~ axis_to_price(.), name = "Price (USD)")
            )
        } else {
          p <- p + scale_y_continuous(limits = y_rng)
        }
      } else {
        p <- p + scale_y_continuous(limits = y_rng)
      }
    } else {
      p <- p + scale_y_continuous(limits = y_rng)
    }
    
    p
  })
  
  #------xplot data tab output plot-----------
  output$xplots <-         renderPlot({
    x.col <-  c('red', 'orange', 'yellow', 'green', 'cyan', 'blue', 'purple', 'gray55', 'black')
    names(x.col) <- scalesx
    colScalevar_x <- scale_colour_manual(name = "Parameter",values = x.col )
    req(input$dates_x != 0 )
    req(input$scaleInput_x!= "")
    req(input$sectorInput_x!= "")
    time.diff <- difftime(max( data_xplots()$date), min( data_xplots()$date), units ="days")
    px1 <- ggplot(  data_xplots(), aes(x=date, y=value, color=variable))    + geom_point(size=.3, alpha=.3)  +     colScalevar_x + 
      scale_y_continuous(limits = c(input$axislimits_x[1], input$axislimits_x[2]), expand = c(0, .1)) +
      theme(strip.text.y = element_text(angle = 90 ,size=5),
            axis.text= element_text(size=15, color="black"),
            axis.title = element_blank(),
            axis.text.x = element_text(angle = 45, hjust = 1),
            legend.title=element_text(size=19,face="bold"),
            legend.key.width=unit(1,"line"),
            legend.key.height=unit(1,"line"),
            legend.text=element_text(size=15),
            legend.key.size = unit(5, "lines"),
            strip.text.x = element_text(size = 14),
            plot.margin = unit(c(0,1,0,1),"cm"),
            legend.background = element_rect(fill=alpha('white', 0.7)))
    px1 <- px1 +  scale_x_date(expand = c(.01, 0), labels=date_format("%b %d %Y")  ,breaks = ifelse( time.diff > 90 & length((unique(px1$data$variable)))  <  2   ,   "7 day",
                                                                                                     ifelse(  time.diff > 90 &   length((unique(px1$data$variable)))  >  1   , "30 day",
                                                                                                              ifelse(  time.diff < 90 &   length((unique(px1$data$variable)))  >  1   , "7 day", "3 day"))))
    px1  <-     px1  + stat_smooth(method = "loess", formula = y ~ x, size = 1, alpha=0,span = .2 ) 
    
    if(length(input$sectorInput_x) > 1) { 
      px1 <- px1 +  facet_wrap(~sector,  ncol=3)
      
    }
    
    if(length(input$industryInput_x) > 1) { 
      px1 <- px1 +  facet_wrap(~industry,  ncol=3)
      
    }
    
    px1
  }, height=700)
  
  
  
  
  #------stockplot variables ------------------------------------
  
  output$date.selector<- renderUI({
    radioButtons('date.selector',  label="Select Dates:",  c("Slider", "Calendar"), selected="Slider",inline = TRUE)
  })
  
  observe({
    updateRadioButtons(session, 'date.selector',  label="Select Date Type:",  c("Slider", "Calendar"), selected=input$date.selector,inline = TRUE)
  })
  
  observeEvent(input$date.selector, {
    
    observe({
      
      if (input$date.selector == "Slider"){
        dates <- unique(l$date)
        output$dates<- renderUI({
          minval <- min(dates)
          maxval <- max(dates)
          sliderInput("dates",label = NULL,
                      min = minval, max = maxval,
                      value = date_default(dates), width="80%"
          )
        })
      }
      if (input$date.selector == "Calendar"){
        dates <- unique(l$date)
        output$dates<- renderUI({
          minval <- min(dates)
          maxval <- max(dates)
          dateRangeInput('dates', label = NULL,
                         start =minval, end = maxval,
                         min = minval, max = maxval,
                         separator = " - ", format = "yyyy-mm-dd",
                         language = 'en', weekstart = 0
          )
        })
      }
    })
  })
  # Select all / Unselect all
  output$scaleOutput <- renderUI({
    pickerInput(inputId  = 'scaleInput', 
                label = 'Select scale:',      
                choices  = scales,   selected =c('x1', 'x2' ,'x3', 'x4','x5' , 'x9'  ,  'x14' ,'x21' ,'x30'),
                multiple = TRUE,
                options = list(`actions-box` = TRUE)
    )
  })
  
  output$axislimits<- renderUI({
    sliderInput("axislimits", label = "Y-axis range", min = -1.5, 
                max = 1.2, value = c(-1, 1),step=.2)

  })
  
  
  output$volumeSelector<- renderUI({
    max_volume <- max(l[l$date == max(l$date),]$x5_volume, na.rm=TRUE)
    if (!is.finite(max_volume)) {
      max_volume <- 0
    }
    sliderInput("volumeSelector", label = "Volume range", min = 0, 
                max = max_volume, value = c(0, max_volume), step=50000)
    
  })

  
  
    output$sectorOutput <- renderUI({
    pickerInput(inputId  = 'sectorInput', 
                label = 'Select sector:',      
                choices  = sectors,  selected =  NULL,
                multiple = FALSE
                ,  options = pickerOptions(
                    liveSearch = TRUE
                  )
    )
  })
    

  
  
  output$spanOutput <- renderUI({
    radioButtons('spanInput',  label="Choose span:",  spans, selected="ls20",inline = TRUE)
  })
  
  
  # output$operatorOutput<- renderUI({
  #   radioButtons('operatorInput',  label="x1 limits", c("> 0.9", "< -0.9"), selected=NULL,inline = TRUE)
  # })
  # 

  output$industryOutput <- renderUI({
    pickerInput(inputId  = 'industryInput', 
                label = 'Select Industry:',      
                if(!is.null(input$sectorInput) )  {  choices =     industries  %>% filter(sector %in% input$sectorInput ) %>% select(industry) %>% unname()%>% unlist() %>% factor() %>% levels()  } else 
                   {choices =    allindustries}
                
              ,  NULL,
                multiple = FALSE,
                options = pickerOptions(
                  #   actionsBox = TRUE,
                  liveSearch = TRUE
                )
    )
  })
  
  # observeEvent(input$indsecInput, {
  # updatePickerInput(session, inputId  = 'symbolInput',  label = NULL, selected = "",
  # 
  #                   if( is.null(input$sectorInput) )
  #                   {choices = NULL} else
  #                     if(input$indsecInput=='Sector') {  choices =     l  %>% filter(sector %in% input$sectorInput) %>% select(symbol) %>% distinct(symbol) %>% unname() %>% unlist()} else
  #                       if(input$indsecInput=='Industry') {    choices =    l  %>% filter(industry %in% input$industryInput) %>% select(symbol) %>% distinct(symbol) %>% unname() %>% unlist()}
  # 
  #            )
  # })

  # output$symbolOutput <- renderUI({
  #   pickerInput(inputId  = 'symbolInput',
  #               label = 'Select symbol:',
  #                if(!is.null(input$sectorInput) & !is.null(input$industryInput) & input$sectorInput != "" & input$industryInput != "" )
  #                     {  choices = l  %>% filter(sector %in% input$sectorInput, industry %in% input$industryInput,  x5_volume >=  input$volumeSelector) %>% select(symbol) %>% distinct(symbol) %>% unname() %>% unlist()} else
  #                       if((is.null(input$sectorInput) | input$sectorInput =="" ) & !is.null(input$industryInput) & input$industryInput != "")
  #                     {  choices = l  %>% filter(industry %in% input$industryInput,  x5_volume >=  input$volumeSelector) %>% select(symbol) %>% distinct(symbol) %>% unname() %>% unlist()} else
  #                       if((!is.null(input$sectorInput) & input$sectorInput !="" ) & is.null(input$industryInput))
  #                       {  choices = l  %>% filter(sector %in% input$sectorInput,  x5_volume >=  input$volumeSelector) %>% select(symbol) %>% distinct(symbol) %>% unname() %>% unlist()}  else
  #                         if((is.null(input$sectorInput) & is.null(input$industryInput)) | (input$sectorInput =="" & input$industryInput=="")){
  # 
  #                           {choices = l  %>% filter(date ==max(date) &  x5_volume >=  input$volumeSelector) %>% select(symbol) %>% distinct(symbol) %>% unname() %>% unlist()}
  #                         } else { choices = NULL}
  # 
  # 
  # 
  #              ,selected =  NULL,
  #               multiple = TRUE,
  #         options = pickerOptions(
  #           actionsBox = TRUE,
  #           liveSearch = TRUE
  #         )
  #               # ,options = list(`actions-box` = TRUE,liveSearch = TRUE)
  #   )
  # })
  output$symbolOutput <- renderUI({
    pickerInput(inputId  = 'symbolInput',
                label = 'Select symbol:',
                      if(input$sectorInput =="" ) {

                        {choices = l  %>% filter(date == max(date) &  x5_volume >=  input$volumeSelector & !is.na(x5_volume) & x5_volume != "") %>% select(symbol) %>% distinct(symbol) %>% unname() %>% unlist()}
                          } else {choices = l  %>% filter(sector %in% input$sectorInput, industry %in% input$industryInput,  x5_volume >=  input$volumeSelector) %>% select(symbol) %>% distinct(symbol) %>% unname() %>% unlist()}
  


                ,selected =  NULL,
                multiple = TRUE,
                options = pickerOptions(
                  actionsBox = TRUE,
                  liveSearch = TRUE
                )
                # ,options = list(`actions-box` = TRUE,liveSearch = TRUE)
    )
  })
  



 
  
  #------stockplot data tab filter data based on user input------
  
  
  xdata<- reactive({
    data <-   l %>%
      filter(
        date >= input$dates[1],
        date <= input$dates[2],
        timescale %in% input$scaleInput,
        span %in% input$spanInput
        )
    if(is.null(input$sectorInput) | input$sectorInput =="") { 
      data <-  data  %>% filter(
                                symbol %in% input$symbolInput
      )
      
      } else { 
      data <-  data  %>% filter(sector %in% input$sectorInput,
                                industry %in% input$industryInput,
                                symbol %in% input$symbolInput
                              )
      }
    
    data                    
    
  })
  output$results <- DT::renderDT(
    xdata(),caption = "Results",filter = c("top"),
    extensions = c('Buttons', 'ColReorder','KeyTable'),
    options = list( pageLength = 50, autoWidth = TRUE, colReorder=TRUE,
                    dom = 'Bfrtip', keys = TRUE,
                    # columnDefs = list(list(width = '5px', targets = list(4:25)),
                    #                   list(width = '25px', targets = list(1,2,3,26))),
                    buttons = c('copy', 'csv', 'excel', 'pdf', 'print')
    )
  )
  

  
#stocks interaction tables----------------------
  
  output$x5i <- DT::renderDT(
    x5i,caption = "Results",
    extensions = c('Buttons', 'ColReorder','KeyTable'),
    options = list( pageLength = 80, autoWidth = TRUE, colReorder=TRUE,
                    dom = 'Bfrtip', keys = TRUE,
                    # columnDefs = list(list(width = '5px', targets = list(4:25)),
                    #                   list(width = '25px', targets = list(1,2,3,26))),
                    buttons = c('copy', 'csv', 'excel', 'pdf', 'print')
    )
  )
  
  output$x9i <- DT::renderDT(
    x9i,caption = "Results",
    extensions = c('Buttons', 'ColReorder','KeyTable'),
    options = list( pageLength = 80, autoWidth = TRUE, colReorder=TRUE,
                    dom = 'Bfrtip', keys = TRUE,
                    # columnDefs = list(list(width = '5px', targets = list(4:25)),
                    #                   list(width = '25px', targets = list(1,2,3,26))),
                    buttons = c('copy', 'csv', 'excel', 'pdf', 'print')
    )
  )
  
  
  output$x14i <- DT::renderDT(
    x14i,caption = "Results",
    extensions = c('Buttons', 'ColReorder','KeyTable'),
    options = list( pageLength = 80, autoWidth = TRUE, colReorder=TRUE,
                    dom = 'Bfrtip', keys = TRUE,
                    # columnDefs = list(list(width = '5px', targets = list(4:25)),
                    #                   list(width = '25px', targets = list(1,2,3,26))),
                    buttons = c('copy', 'csv', 'excel', 'pdf', 'print')
    )
  )
  
  
  output$x21i <- DT::renderDT(
    x21i, caption = "Results",
    extensions = c('Buttons', 'ColReorder','KeyTable'),
    options = list( pageLength = 80, autoWidth = TRUE, colReorder=TRUE,
                    dom = 'Bfrtip', keys = TRUE,
                    # columnDefs = list(list(width = '5px', targets = list(4:25)),
                    #                   list(width = '25px', targets = list(1,2,3,26))),
                    buttons = c('copy', 'csv', 'excel', 'pdf', 'print')
    )
  )
  
  output$x30i <- DT::renderDT(
    x30i, caption = "Results",
    extensions = c('Buttons', 'ColReorder','KeyTable'),
    options = list( pageLength = 80, autoWidth = TRUE, colReorder=TRUE,
                    dom = 'Bfrtip', keys = TRUE,
                    # columnDefs = list(list(width = '5px', targets = list(4:25)),
                    #                   list(width = '25px', targets = list(1,2,3,26))),
                    buttons = c('copy', 'csv', 'excel', 'pdf', 'print')
    )
  )
  
  
  output$sumi <- DT::renderDT(
    sumi, caption = "Results",
    extensions = c('Buttons', 'ColReorder','KeyTable'),
    options = list( pageLength = 80, autoWidth = TRUE, colReorder=TRUE,
                    dom = 'Bfrtip', keys = TRUE,
                    # columnDefs = list(list(width = '5px', targets = list(4:25)),
                    #                   list(width = '25px', targets = list(1,2,3,26))),
                    buttons = c('copy', 'csv', 'excel', 'pdf', 'print')
    )
  )
  
  
  
  
  #stockscross data tables -------------------  
    
  output$x9x5 <- DT::renderDT(
    x95,caption = "Results",filter = c("top"),
    extensions = c('Buttons', 'ColReorder','KeyTable'),
    options = list( pageLength = 80, autoWidth = TRUE, colReorder=TRUE,
                    dom = 'Bfrtip', keys = TRUE,
                    # columnDefs = list(list(width = '5px', targets = list(4:25)),
                    #                   list(width = '25px', targets = list(1,2,3,26))),
                    buttons = c('copy', 'csv', 'excel', 'pdf', 'print')
    )
  )
  
  
  
  output$x14x9 <- DT::renderDT(
    x149,caption = "Results",filter = c("top"),
    extensions = c('Buttons', 'ColReorder','KeyTable'),
    options = list( pageLength = 80, autoWidth = TRUE, colReorder=TRUE,
                    dom = 'Bfrtip', keys = TRUE,
                    # columnDefs = list(list(width = '5px', targets = list(4:25)),
                    #                   list(width = '25px', targets = list(1,2,3,26))),
                    buttons = c('copy', 'csv', 'excel', 'pdf', 'print')
    )
  )
  
  
  
  
  output$x21x14<- DT::renderDT(
    x2114,caption = "Results",filter = c("top"),
    extensions = c('Buttons', 'ColReorder','KeyTable'),
    options = list( pageLength = 80, autoWidth = TRUE, colReorder=TRUE,
                    dom = 'Bfrtip', keys = TRUE,
                    # columnDefs = list(list(width = '5px', targets = list(4:25)),
                    #                   list(width = '25px', targets = list(1,2,3,26))),
                    buttons = c('copy', 'csv', 'excel', 'pdf', 'print')
    )
  )
  
  output$x30x21 <- DT::renderDT(
    x3021,caption = "Results",filter = c("top"),
    extensions = c('Buttons', 'ColReorder','KeyTable'),
    options = list( pageLength = 80, autoWidth = TRUE, colReorder=TRUE,
                    dom = 'Bfrtip', keys = TRUE,
                    # columnDefs = list(list(width = '5px', targets = list(4:25)),
                    #                   list(width = '25px', targets = list(1,2,3,26))),
                    buttons = c('copy', 'csv', 'excel', 'pdf', 'print')
    )
  )
  
  
  output$x30x14 <- DT::renderDT(
    x3014,caption = "Results",filter = c("top"),
    extensions = c('Buttons', 'ColReorder','KeyTable'),
    options = list( pageLength = 80, autoWidth = TRUE, colReorder=TRUE,
                    dom = 'Bfrtip', keys = TRUE,
                    # columnDefs = list(list(width = '5px', targets = list(4:25)),
                    #                   list(width = '25px', targets = list(1,2,3,26))),
                    buttons = c('copy', 'csv', 'excel', 'pdf', 'print')
    )
  )
  
  
  #etf output tables-------------------
  
  output$etf9x5 <- DT::renderDT(
    etf95,caption = "Results",filter = c("top"),
    extensions = c('Buttons', 'ColReorder','KeyTable'),
    options = list( pageLength = 80, autoWidth = TRUE, colReorder=TRUE,
                    dom = 'Bfrtip', keys = TRUE,
                    # columnDefs = list(list(width = '5px', targets = list(4:25)),
                    #                   list(width = '25px', targets = list(1,2,3,26))),
                    buttons = c('copy', 'csv', 'excel', 'pdf', 'print')
    )
  )
  
  
  
  output$etf14x9 <- DT::renderDT(
    etf149,caption = "Results",filter = c("top"),
    extensions = c('Buttons', 'ColReorder','KeyTable'),
    options = list( pageLength = 80, autoWidth = TRUE, colReorder=TRUE,
                    dom = 'Bfrtip', keys = TRUE,
                    # columnDefs = list(list(width = '5px', targets = list(4:25)),
                    #                   list(width = '25px', targets = list(1,2,3,26))),
                    buttons = c('copy', 'csv', 'excel', 'pdf', 'print')
    )
  )
  
  
  
  
  output$etf21x14<- DT::renderDT(
    etf2114,caption = "Results",filter = c("top"),
    extensions = c('Buttons', 'ColReorder','KeyTable'),
    options = list( pageLength = 80, autoWidth = TRUE, colReorder=TRUE,
                    dom = 'Bfrtip', keys = TRUE,
                    # columnDefs = list(list(width = '5px', targets = list(4:25)),
                    #                   list(width = '25px', targets = list(1,2,3,26))),
                    buttons = c('copy', 'csv', 'excel', 'pdf', 'print')
    )
  )
  
  output$etf30x21 <- DT::renderDT(
    etf3021,caption = "Results",filter = c("top"),
    extensions = c('Buttons', 'ColReorder','KeyTable'),
    options = list( pageLength = 80, autoWidth = TRUE, colReorder=TRUE,
                    dom = 'Bfrtip', keys = TRUE,
                    # columnDefs = list(list(width = '5px', targets = list(4:25)),
                    #                   list(width = '25px', targets = list(1,2,3,26))),
                    buttons = c('copy', 'csv', 'excel', 'pdf', 'print')
    )
  )
  
  
  output$etf30x14 <- DT::renderDT(
    etf3014,caption = "Results",filter = c("top"),
    extensions = c('Buttons', 'ColReorder','KeyTable'),
    options = list( pageLength = 80, autoWidth = TRUE, colReorder=TRUE,
                    dom = 'Bfrtip', keys = TRUE,
                    # columnDefs = list(list(width = '5px', targets = list(4:25)),
                    #                   list(width = '25px', targets = list(1,2,3,26))),
                    buttons = c('copy', 'csv', 'excel', 'pdf', 'print')
    )
  )
  
  
  
  #------stockplot data tab output plot-----------
  

  output$stocksplot <-         renderPlot({
    
    x.col <-  c('red', 'orange', 'yellow', 'green', 'cyan', 'blue', 'purple', 'gray55', 'black', "hotpink")
    x.shape <-  c('solid', 'solid', 'solid', 'solid', 'solid', 'solid' ,'solid', 'solid', 'solid', "solid")
    x.size <-  c(rep(1.25, 9), .9)
    names(x.col) <- levels(l$timescale)
    names(x.shape) <- levels(l$timescale)
    names(x.size) <- levels(l$timescale)
    colScalevar <- scale_colour_manual(name = "timescale",values = x.col )
    # conditional functions to ensure plots render properly and inform user of incorrect selections.
    req(input$dates != 0 )
    req(input$scaleInput != "")
    req(input$symbolInput != "" )
    time.diff <- difftime(max(xdata()$date), min(xdata()$date), units ="days") 
    px1 <- ggplot(xdata(), aes(x=date, y=value, color=timescale))   + colScalevar + 
      scale_y_continuous(limits = c(input$axislimits[1], input$axislimits[2]), expand = c(0, .1)) +
      theme(strip.text.y = element_text(angle = 90 ,size=5),
            axis.text= element_text(size=15, color="black"),
            axis.title = element_blank(),
            axis.text.x = element_text(angle = 45, hjust = 1),
            legend.title=element_text(size=19,face="bold"),
            legend.key.width=unit(1,"line"),
            legend.key.height=unit(1,"line"),
            legend.text=element_text(size=15),
            legend.key.size = unit(5, "lines"),
            strip.text.x = element_text(size = 14),
            plot.margin = unit(c(0,1,0,1),"cm"),
            legend.background = element_rect(fill=alpha('white', 0.7))) 
    px1 <- px1 +  scale_x_date(expand = c(.01, 0), labels=date_format("%b %d %Y")  ,breaks = ifelse( time.diff > 90 & length((unique(px1$data$symbol)))  <  2   ,   "7 day",
                                                                                                     ifelse(  time.diff > 90 &   length((unique(px1$data$symbol)))  == 2  , "14 day",
                                                                                                              ifelse(  time.diff < 90 &   length((unique(px1$data$symbol)))  >  1   , "7 day", 
                                                                                                              ifelse(  time.diff >90 &   length((unique(px1$data$symbol)))  >  2   , "21 day", "3 day"))))) + geom_line() +
      facet_wrap(~symbol, ncol=4)
    
    # px1  <-     px1  + stat_smooth(method = "loess", formula = y ~ x, size = 1, alpha=0,span = .2 ) +   facet_wrap(~sector, scales = input$scale_choice)
    px1
  }, height=700)
  
  
  
  
  
  
  #------metal plot variables ------------------------------------
  
  output$date.selector_met<- renderUI({
    radioButtons('date.selector_met',  label="Select Dates:",  c("Slider", "Calendar"), selected="Slider",inline = TRUE)
  })
  
  observe({
    updateRadioButtons(session, 'date.selector_met',  label="Select Date Type:",  c("Slider", "Calendar"), selected=input$date.selector_met,inline = TRUE)
  })
  
  observeEvent(input$date.selector_met, {
    
    observe({
      
      if (input$date.selector_met == "Slider"){
        dates <- unique(etf_melt$date)
        output$dates_met<- renderUI({
          minval <- min(dates)
          maxval <- max(dates)
          sliderInput("dates_met",label = NULL,
                      min = minval, max = maxval,
                      value = date_default(dates), width="80%"
          )
        })
      }
      if (input$date.selector_met == "Calendar"){
        dates <- unique(etf_melt$date)
        output$dates_met<- renderUI({
          minval <- min(dates)
          maxval <- max(dates)
          dateRangeInput('dates_met', label = NULL,
                         start =minval, end = maxval,
                         min = minval, max = maxval,
                         separator = " - ", format = "yyyy-mm-dd",
                         language = 'en', weekstart = 0
          )
        })
      }
    })
    
    
  })
  # Select all / Unselect all
  
  
  output$xgroupOutput <- renderUI({
    pickerInput(inputId  = 'xgroupInput',
                label = 'Select group:',
                choices  = names(xgroup),
                selected = "fang",
                multiple = FALSE
                # ,options = list(`actions-box` = TRUE)
    )
  })
  
  
  
  
  #------metal plot data tab filter data based on user input------
  xdata_met<- reactive({
    
    ss_melt %>%   filter(   date >= input$dates_met[1],
                            date <= input$dates_met[2]
                            , symbol %in% c(unlist(unname(xgroup[names(xgroup) == input$xgroupInput])))
    ) 
  })
  
  
  
  output$results_met <- DT::renderDT(
    xdata_met(),caption = "Results",filter = c("top"),
    extensions = c('Buttons', 'ColReorder','KeyTable'),
    options = list( pageLength = 50, autoWidth = TRUE, colReorder=TRUE,
                    dom = 'Bfrtip', keys = TRUE,
                    # columnDefs = list(list(width = '5px', targets = list(4:25)),
                    #                   list(width = '25px', targets = list(1,2,3,26))),
                    buttons = c('copy', 'csv', 'excel', 'pdf', 'print')
    )
  )
  
  
  
  
  #------metal plot data tab output plot-----------
  
  
  output$xgroup_plots <-         renderPlot({
    
    # conditional functions to ensure plots render properly and inform user of incorrect selections.
    req(input$dates_met != 0 & !is.na(input$dates_met) )
    req( input$xgroupInput != "" & !is.na(input$xgroupInput))
    req( input$scale_choice_met != "")
    x.col <-  c('red', 'orange', 'yellow', 'green', 'cyan', 'blue', 'purple', 'gray55', 'black')
    names(x.col) <- unique(as.character(ss_melt$variable))
    colScalevar <- scale_colour_manual(name = "Parameter",values = x.col )
    symbols <- unique(ss_melt$symbol)
    time.diff <- difftime(max(xdata_met()$date), min(xdata_met()$date), units ="days")
    px1 <- ggplot(xdata_met(), aes(x=date, y=value, color=variable))    + geom_point(size=.3, alpha=.3)  +  facet_wrap(symbol~., scales= input$scale_choice_met) +
      # scale_y_continuous(limits = c(-0.75, 0.75), expand = c(0, .1)) +
      theme(strip.text.y = element_text(angle = 90 ,size=5),
            axis.text= element_text(size=15, color="black"),
            axis.title = element_blank(),
            axis.text.x = element_text(angle = 45, hjust = 1),
            legend.title=element_text(size=19,face="bold"),
            legend.key.width=unit(1,"line"),
            legend.key.height=unit(1,"line"),
            legend.text=element_text(size=15),
            legend.key.size = unit(5, "lines"),
            strip.text.x = element_text(size = 14),
            plot.margin = unit(c(0,1,0,1),"cm"),
            legend.background = element_rect(fill=alpha('white', 0.7)))
    px1 <- px1 +  scale_x_date(expand = c(.01, 0), labels=date_format("%b %d %Y")  ,breaks = ifelse( time.diff > 90 & length((unique(px1$data$variable)))  <  2   ,   "7 day",
                                                                                                     ifelse(  time.diff > 90 &   length((unique(px1$data$variable)))  >  1   , "30 day",
                                                                                                              ifelse(  time.diff < 90 &   length((unique(px1$data$variable)))  >  1   , "7 day", "3 day")))) + colScalevar
    px1  <-     px1  + stat_smooth(method = "loess", formula = y ~ x, size = 1, alpha=0,span = .2 )
    px1
  }, height=700)
  
  
  
  
  
  
  
  
  #------etf plot variables ------------------------------------
  
  output$date.selector_etf<- renderUI({
    radioButtons('date.selector_etf',  label="Select Dates:",  c("Slider", "Calendar"), selected="Slider",inline = TRUE)
  })
  
  observe({
    updateRadioButtons(session, 'date.selector_etf',  label="Select Date Type:",  c("Slider", "Calendar"), selected=input$date.selector_etf,inline = TRUE)
  })
  
  
  output$axislimitsetf <- renderUI({
    sliderInput("axislimitsetf", label = "Y-axis range", min = -1.5, 
                max = 1.2, value = c(-1.2, 1),step=.2)
    
  })
  
  
  observeEvent(input$date.selector_etf, {
    
    observe({
      
      if (input$date.selector_etf == "Slider"){
        dates <- unique(ss_melt$date)
        output$dates_etf<- renderUI({
          minval <- min(dates)
          maxval <- max(dates)
          sliderInput("dates_etf",label = NULL,
                      min = minval, max = maxval,
                      value = date_default(dates), width="80%"
          )
        })
      }
      if (input$date.selector_etf == "Calendar"){
        dates <- unique(ss_melt$date)
        output$dates_etf<- renderUI({
          minval <- min(dates)
          maxval <- max(dates)
          dateRangeInput('dates_etf', label = NULL,
                         start =minval, end = maxval,
                         min = minval, max = maxval,
                         separator = " - ", format = "yyyy-mm-dd",
                         language = 'en', weekstart = 0
          )
        })
      }
    })
    
    
  })
  # Select all / Unselect all
  
  output$etfgroupOutput <- renderUI({
    pickerInput(inputId  = 'etfgroupInput',
                label    = "Select group",
                choices  = unique(etf_melt$Group),
                selected = "Metals",
                multiple = FALSE,
                options = list(`actions-box` = FALSE)
    )
  })
  
  
  
  
  # observeEvent(input$all.scales_etf, {
  #   if (is.null(input$scaleInput_etf)) {
  #     updateCheckboxGroupInput(
  #       session = session, inputId  = 'scaleInput_etf',label=NULL,
  #       choices  = scales,
  #       selected =scales,
  #       inline   = FALSE)
  #   } else {
  #     updateCheckboxGroupInput(
  #       session = session, inputId  = 'scaleInput_etf', selected = ""
  #     )
  #   }
  # })
  
  
  #------etf plot data tab filter data based on user input------
  xdata_etf<- reactive({
    df <- etf_melt %>%   filter(   date >= input$dates_etf[1],
                                   date <= input$dates_etf[2],
                                   Group %in% input$etfgroupInput ,
                                   variable != "close_price"
    )
    
    cp<- etf_melt %>%   filter(   date >= input$dates_etf[1],
                                  date <= input$dates_etf[2],
                                  Group %in% input$etfgroupInput ,
                                  variable == "close_price"
    )
    
    cp <-  cp %>% group_by(sector)%>%
      mutate(pricechange = ((value-value[1])/value[1])  * 2,
             date.len = length(unique(date))) 
    cp$pricechange[cp$pricechange==Inf] <- NA
    
    df <- as.data.frame(df)
    cp <- as.data.frame(cp)
    x1 <- df[df$variable=="x1",]
    x1$x1 <- x1$value
    x1 <- x1[c("date",     "sector",     "x1")]
    cp <- left_join(cp, x1, by = c("date", "sector"))
    # cp <-  cp %>% group_by(sector)%>%
    #   arrange(sector, date.ord )%>%
    #   mutate(priceline = predict(loess(x1 ~ date.ord,span=.25, data=.),
    #                              data.frame(date.ord = seq(min(date.ord), max(date.ord), 1))))   
    cp$variable <- "pricechange"
    cp$value <- cp$pricechange
    cp2 <- cp[c("date" , "sector", "variable", "value",  "Group")] %>% 
      ungroup %>%  as.data.frame()
    df2 <- rbind(df, cp2) %>% 
      filter(variable != "close_price") %>%
      arrange(date, sector)%>%
      droplevels("close_price")
    
    
    
    # etf_melt %>%   filter(   date >= input$dates_etf[1],
    #                         date <= input$dates_etf[2],
    #                         Group %in% input$etfgroupInput
    #                       
    # ) 
  })
  
  
  
  output$results_etf <- DT::renderDT(
    xdata_etf(),caption = "Results",filter = c("top"),
    extensions = c('Buttons', 'ColReorder','KeyTable'),
    options = list( pageLength = 50, autoWidth = TRUE, colReorder=TRUE,
                    dom = 'Bfrtip', keys = TRUE,
                    # columnDefs = list(list(width = '5px', targets = list(4:25)),
                    #                   list(width = '25px', targets = list(1,2,3,26))),
                    buttons = c('copy', 'csv', 'excel', 'pdf', 'print')
    )
  )
  
  
  
  
  #------etf plot data tab output plot-----------
  
  
  output$etf_plots <-         renderPlot({
    
    # conditional functions to ensure plots render properly and inform user of incorrect selections.
    req(input$dates_etf != 0  )
    req( input$etfgroupInput != "")
    
    x.col <-  c('red', 'orange', 'yellow', 'green', 'cyan', 'blue', 'purple', 'gray55', 'black', "hotpink")
    x.shape <-  c('solid', 'solid', 'solid', 'solid', 'solid', 'solid' ,'solid', 'solid', 'solid', "solid")
    x.size <-  c(rep(1.25, 9), .9)
    names(x.col) <- levels(    xdata_etf()$variable)
    names(x.shape) <- levels(    xdata_etf()$variable)
    names(x.size) <- levels(    xdata_etf()$variable)
    colScalevar <- scale_colour_manual(name = "Parameter",values = x.col )
    lineshapevar <-  scale_linetype_manual(name = "Parameter",values = x.shape )
    linesizevar <-  scale_size_manual(name = "Parameter",values = x.size )
    # sector <- unique(me2$sector)
    time.diff <- difftime(max(xdata_etf()$date), min(xdata_etf()$date), units ="days")
    px1 <- ggplot(xdata_etf(), aes(x=date, y=value, color=variable,  size=variable))    + geom_point(alpha=.2, size=.6)      +  
      geom_hline(yintercept=0, color="grey31",  linetype="dashed") +  colScalevar +
      # scale_y_continuous(limits = c(input$axislimits[1], input$axislimits[2]), expand = c(0, .1)) +  scale_y_continuous(limits = c(input$axislimitsetf[1], input$axislimitsetf[2]), expand = c(0, .1)) +
      theme(strip.text.y = element_text(angle = 90 ,size=5),
            axis.text= element_text(size=15, color="black"),
            axis.title = element_blank(),
            axis.text.x = element_text(angle = 45, hjust = 1),
            legend.title=element_text(size=19,face="bold"),
            legend.key.width=unit(1,"line"),
            legend.key.height=unit(1,"line"),
            legend.text=element_text(size=15),
            legend.key.size = unit(5, "lines"),
            strip.text.x = element_text(size = 14),
            plot.margin = unit(c(0,1,0,1),"cm"),
            legend.background = element_rect(fill=alpha('white', 0.7)))  
    px1 <- px1 +  scale_x_date(expand = c(.01, 0), labels=date_format("%b %d %Y")  ,breaks = ifelse( time.diff > 90 & length((unique(px1$data$variable)))  <  2   ,   "7 day", 
                                                                                                     ifelse(  time.diff > 90 &   length((unique(px1$data$variable)))  >  1   , "30 day",
                                                                                                              ifelse(  time.diff < 90 &   length((unique(px1$data$variable)))  >  1   , "7 day", "3 day")))) 
    px1  <-     px1  + stat_smooth(method = "loess", formula = y ~ x, size = 1, alpha=0,span = .2 ) + linesizevar  +  
      scale_y_continuous(limits = c(input$axislimitsetf[1], input$axislimitsetf[2]), expand = c(0, .1)) +
      facet_wrap(sector~., scales= input$scale_choice_etf)  
    px1
  }, height= 750)
  
  
  
  
  
  
  
}
shinyApp(ui, server)
