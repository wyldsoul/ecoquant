/* =========================================================
   EQI MASTER DATABASE + OUTPUTS PIPELINE
   ---------------------------------------------------------
   Purpose:
     One SAS program that imports/stitches results_stock_xtest*.csv once,
     creates one living permanent daily stock database, and reproduces the
     known EQI outputs from the three source programs.

   Preserved output families:
     1) EQ Focus PDF:
        - Authoritative EQ list = Top 50
        - Table 1 changes = Top 20 only
        - Table 2 tenure/return = Top 50
        - Chart pack = Top 20 only
        - Volatility table = Top 50

     2) Alert lifecycle / conviction outputs:
        - daily_ranked_universe
        - curr_topN / prev_topN
        - eq_topN_events_vol / eq_topN_exits_vol
        - alert_entries / entry_snapshot / lifecycle tables
        - EQI_alert_lifecycle_panels.pdf
        - EQI_conviction_quadrant_shaded_poly_v5_full_ranked_delta.jpeg
        - EQI_conviction_plus_top20_lifecycle.pdf

     3) EQMI outputs:
        - EQMI_daily_last60.csv
        - EQMI_EMA3_last60_bars.png
        - EQMI_EMA3_by_sector_bars_DAILY.png
        - eqmi_run.html / eqmi_bars.html / eqmi_sector_bars_daily.html

   Master permanent tables:
     - EQI.file_inventory
     - EQI.import_audit
     - EQI.stock_master_raw
     - EQI.stock_master_daily
     - EQI.daily_ranked_universe
     - EQI.eq_topN_events_vol
     - EQI.vol_top50_today
     - EQI.eqmi_daily
     - EQI.eqmi_sector_daily

   Notes:
     - Imports are done once.
     - The master daily database keeps both term-structure definitions:
         term_structure_pdf       = (x9-x30)+(x14-x30)+(x21-x30)
         term_structure_lifecycle = mean(x14,x21,x30)-mean(x3,x4,x5)
     - The generic term_structure used in lifecycle tables is mapped to
       term_structure_lifecycle.
     - The EQ Focus PDF tables use term_structure_pdf to preserve Program 1.
   ========================================================= */

options mprint mlogic symbolgen nodate nonumber;
ods noproctitle;

/* =========================================================
   0) CONTROL PANEL
   ========================================================= */
%let BASEDIR              = /home/u51238257/sasuser.v94;

/* One import window large enough for all modules */
%let USE_FULL_HISTORY     = 0;
%let master_days_back     = 180;

/* Ranking / reports */
%let topN                 = 50;   /* authoritative Top50 for Table 2 and database */
%let table1N              = 20;   /* Table 1 changes only */
%let chartN               = 20;   /* LR chart pack only */
%let lifecycle_topN       = 20;   /* seeded alerts and lifecycle module */
%let d30_floor            = 1000000;
%let TENURE_MONTHS        = 3;

/* EQ score weights */
%let W_LONG               = 0.65;
%let W_SHORT              = 0.25;
%let W_VOL                = 0.10;

/* Lifecycle thresholds */
%let TOP_STRONG              = 20;
%let TOP_WEAK                = 50;
%let TOP_BROKEN              = 100;
%let RANK_DROP_1D_REEVAL     = -15;
%let RANK_DROP_ENTRY_REEVAL  = -25;
%let RANK_DROP_ENTRY_BROKEN  = -75;
%let continuity_lookback_dates = 60;
%let continuity_min_obs        = 40;

/* EQMI */
%let EQMI_LOOKBACK_DAYS   = 60;
%let EQMI_W_LONG          = 0.60;
%let EQMI_W_ACCEL         = 0.40;
%let EMA_ALPHA            = 0.5;
%let EQMI_SECTOR_TOPK     = 12;

libname EQI "&BASEDIR";

/* =========================================================
   0B) RESET PERMANENT OUTPUT TABLES
   ========================================================= */
proc datasets lib=EQI nolist;
  delete file_inventory
         import_audit
         stock_master_raw
         stock_master_daily
         daily_ranked_universe
         curr_topN
         prev_topN
         curr_lifecycle_topN
         prev_lifecycle_topN
         eq_topN_events_vol
         eq_topN_exits_vol
         vol_top50_today
         alert_entries
         entry_snapshot
         entry_snapshot_audit
         signal_lifecycle_daily
         active_signals_today
         status_changes_today
         broken_signals_today
         signal_status_summary_today
         eqmi_daily
         eqmi_sector_daily;
quit;

/* =========================================================
   1) FILE INVENTORY, DATE PARSING, AND IMPORT WINDOW
   ========================================================= */
filename _dir "&BASEDIR";

data work._filelist_raw;
  length fname $256 path $512;
  did = dopen('_dir');
  if did=0 then do;
    put "ERROR: Cannot open directory: &BASEDIR";
    stop;
  end;

  n = dnum(did);
  do i=1 to n;
    fname = dread(did,i);
    if prxmatch('/^results_stock_xtest.*\.csv$/i', strip(fname)) then do;
      path = cats("&BASEDIR/", fname);
      output;
    end;
  end;

  rc = dclose(did);
  drop did rc n i;
run;

data work._filelist;
  set work._filelist_raw;
  length ymd $8;
  ymd = '';

  if prxmatch('/(\d{8})\.csv$/i', strip(fname)) then
    ymd = prxchange('s/.*(\d{8})\.csv$/$1/i', -1, strip(fname));
  else if prxmatch('/(\d{4})-(\d{2})-(\d{2})\.csv$/i', strip(fname)) then
    ymd = prxchange('s/.*(\d{4})-(\d{2})-(\d{2})\.csv$/$1$2$3/i', -1, strip(fname));

  if ymd ne '' then do;
    file_date = input(ymd, yymmdd8.);
    format file_date yymmdd10.;
  end;
  else file_date = .;

  if missing(file_date) then delete;
run;

proc sort data=work._filelist nodupkey;
  by file_date fname;
run;

data EQI.file_inventory;
  set work._filelist;
run;

proc sql noprint;
  select max(file_date) into :MAX_DT_NUM trimmed from work._filelist;
  select max(file_date) into :YDAY_DT_NUM trimmed from work._filelist
  where file_date < (select max(file_date) from work._filelist);
quit;

%if %superq(MAX_DT_NUM)= %then %do;
  %put ERROR: No eligible results_stock_xtest*.csv files found.;
  %abort cancel;
%end;

%if %superq(YDAY_DT_NUM)= %then %do;
  %put ERROR: Could not find a prior file date before MAX_FILE_DT. Need at least 2 files.;
  %abort cancel;
%end;

%let MAX_FILE_DT = %sysfunc(putn(&MAX_DT_NUM,yymmdd10.));
%let YDAY_DT     = %sysfunc(putn(&YDAY_DT_NUM,yymmdd10.));
%let CUT_DT      = %sysfunc(intnx(day,&MAX_DT_NUM,-%eval(&master_days_back-1),same));
%let EQMI_CUT_DT = %sysfunc(intnx(day,&MAX_DT_NUM,-&EQMI_LOOKBACK_DAYS,same));
%let TENURE_CUTDT = %sysfunc(intnx(month,&MAX_DT_NUM,-&TENURE_MONTHS,same));

%put NOTE: MAX_FILE_DT=&MAX_FILE_DT MAX_DT_NUM=&MAX_DT_NUM;
%put NOTE: YDAY_DT=&YDAY_DT YDAY_DT_NUM=&YDAY_DT_NUM;
%put NOTE: MASTER CUT_DT=%sysfunc(putn(&CUT_DT,yymmdd10.));
%put NOTE: EQMI CUT_DT=%sysfunc(putn(&EQMI_CUT_DT,yymmdd10.));

data work._filelist_win;
  set work._filelist;
  %if &USE_FULL_HISTORY = 1 %then %do;
    output;
  %end;
  %else %do;
    if file_date >= &CUT_DT and file_date <= &MAX_DT_NUM then output;
  %end;
run;

proc sort data=work._filelist_win;
  by file_date fname;
run;

proc sql noprint;
  select count(*) into :NFILES trimmed from work._filelist_win;
quit;

%if %eval(&NFILES)=0 %then %do;
  %put ERROR: No files selected for import window.;
  %abort cancel;
%end;

/* =========================================================
   2) IMPORT + NORMALIZE ONCE
   ========================================================= */
proc datasets lib=work nolist;
  delete all_imported import_audit _raw_: _norm_: _audit_row;
quit;

data work.all_imported;
  length symbol $32 name $200 sector $100 industry $120 source_file $256;
  format date yymmdd10.;
  length close_price d30_volume 8;
  length x1slope x2slope x3slope x4slope x5slope x9slope x14slope x21slope x30slope 8;
  stop;
run;

data work.import_audit;
  length filepath $512 status $24 message $200;
  stop;
run;

data _null_;
  set work._filelist_win end=eof;
  call symputx(cats('FILE',_n_), path, 'L');
  call symputx(cats('FDT', _n_), file_date, 'L');
  if eof then call symputx('NFILES2', _n_, 'L');
run;

%macro import_xtest_once;
  %local i thisfile thisdt;

  %do i=1 %to &NFILES2;
    %let thisfile = &&FILE&i;
    %let thisdt   = &&FDT&i;

    proc import datafile="&thisfile"
      out=work._raw_&i
      dbms=csv
      replace;
      guessingrows=max;
      getnames=yes;
    run;

    %if not %sysfunc(exist(work._raw_&i)) %then %do;
      data work._audit_row;
        length filepath $512 status $24 message $200;
        filepath="&thisfile";
        status='IMPORT_FAILED';
        message='PROC IMPORT did not create WORK._RAW_ dataset';
      run;
      proc append base=work.import_audit data=work._audit_row force; run;
      %goto next_file;
    %end;

    data work._norm_&i;
      length symbol $32 name $200 sector $100 industry $120 source_file $256;
      length _txt $256;
      format date yymmdd10.;
      set work._raw_&i;

      date = &thisdt;
      symbol = upcase(strip(vvaluex('symbol')));
      if missing(symbol) then symbol = upcase(strip(vvaluex('ticker')));

      if not missing(vvaluex('name')) then name = strip(vvaluex('name'));
      else name = symbol;

      sector   = strip(coalescec(vvaluex('sector'),   vvaluex('Sector')));
      industry = strip(coalescec(vvaluex('industry'), vvaluex('Industry')));
      source_file = scan("&thisfile", -1, '/');

      _txt = strip(coalescec(vvaluex('close_price'), vvaluex('close')));
      _txt = compress(_txt, '$, ');
      close_price = input(_txt, ?? best32.);

      _txt = strip(coalescec(vvaluex('d30_volume'), vvaluex('D30_volume')));
      _txt = compress(_txt, '$, ');
      d30_volume = input(_txt, ?? best32.);

      _txt = compress(strip(vvaluex('x1slope')),  ', '); x1slope  = input(_txt, ?? best32.);
      _txt = compress(strip(vvaluex('x2slope')),  ', '); x2slope  = input(_txt, ?? best32.);
      _txt = compress(strip(vvaluex('x3slope')),  ', '); x3slope  = input(_txt, ?? best32.);
      _txt = compress(strip(vvaluex('x4slope')),  ', '); x4slope  = input(_txt, ?? best32.);
      _txt = compress(strip(vvaluex('x5slope')),  ', '); x5slope  = input(_txt, ?? best32.);
      _txt = compress(strip(vvaluex('x9slope')),  ', '); x9slope  = input(_txt, ?? best32.);
      _txt = compress(strip(vvaluex('x14slope')), ', '); x14slope = input(_txt, ?? best32.);
      _txt = compress(strip(vvaluex('x21slope')), ', '); x21slope = input(_txt, ?? best32.);
      _txt = compress(strip(vvaluex('x30slope')), ', '); x30slope = input(_txt, ?? best32.);

      if missing(symbol) then delete;
      if missing(date) then delete;
      if missing(close_price) then delete;
      if missing(d30_volume) then delete;

      if missing(sector) then delete;
      if upcase(strip(sector)) in ('ETF','ETFS','UNKNOWN','N/A','NA','NULL','NONE','.') then delete;

      keep date symbol name sector industry source_file close_price d30_volume
           x1slope x2slope x3slope x4slope x5slope x9slope x14slope x21slope x30slope;
    run;

    proc append base=work.all_imported data=work._norm_&i force;
    run;

    data work._audit_row;
      length filepath $512 status $24 message $200;
      filepath="&thisfile";
      status='IMPORTED';
      message='Imported and normalized successfully';
    run;
    proc append base=work.import_audit data=work._audit_row force; run;

    %next_file:
  %end;
%mend;

%import_xtest_once;

proc sort data=work.all_imported nodupkey;
  by date symbol;
run;

data EQI.import_audit;
  set work.import_audit;
run;

data EQI.stock_master_raw;
  set work.all_imported;
run;

/* =========================================================
   3) MASTER FEATURES: ROLLING PRICE POSITION + TERM STRUCTURES
   ========================================================= */
proc sort data=work.all_imported out=work.master_s;
  by symbol date;
run;

data work.master_features;
  set work.master_s;
  by symbol date;

  length trigger_reason_edge_pdf trigger_reason_edge_lifecycle $140;
  retain prior_x21slope nbuf;
  array win[20] _temporary_;

  if first.symbol then do;
    prior_x21slope = .;
    nbuf = 0;
    do _k = 1 to 20; win[_k] = .; end;
  end;

  if nbuf < 20 then do;
    nbuf + 1;
    win[nbuf] = close_price;
  end;
  else do;
    do _k = 1 to 19; win[_k] = win[_k+1]; end;
    win[20] = close_price;
  end;

  close_min_20 = .;
  close_max_20 = .;
  do _k = 1 to nbuf;
    if missing(close_min_20) then close_min_20 = win[_k];
    else close_min_20 = min(close_min_20, win[_k]);

    if missing(close_max_20) then close_max_20 = win[_k];
    else close_max_20 = max(close_max_20, win[_k]);
  end;

  if close_max_20 > close_min_20 then
    price_pos_20 = (close_price - close_min_20) / (close_max_20 - close_min_20);
  else price_pos_20 = .;

  if not first.symbol then delta_x21slope = x21slope - prior_x21slope;
  else delta_x21slope = .;

  term_structure_pdf = (x9slope  - x30slope)
                     + (x14slope - x30slope)
                     + (x21slope - x30slope);

  term_structure_lifecycle = mean(x14slope, x21slope, x30slope)
                           - mean(x3slope,  x4slope,  x5slope);

  slope_edge_pdf = (delta_x21slope > 0)
                and (term_structure_pdf > 0)
                and (price_pos_20 <= 0.70);

  slope_edge_lifecycle = (delta_x21slope > 0)
                      and (term_structure_lifecycle > 0)
                      and (price_pos_20 <= 0.70);

  if slope_edge_pdf then trigger_reason_edge_pdf = 'delta_x21>0 & term_structure_pdf>0 & price_pos_20<=0.70';
  else trigger_reason_edge_pdf = '';

  if slope_edge_lifecycle then trigger_reason_edge_lifecycle = 'delta_x21>0 & term_structure_lifecycle>0 & price_pos_20<=0.70';
  else trigger_reason_edge_lifecycle = '';

  prior_x21slope = x21slope;
  drop _k nbuf prior_x21slope;
run;

/* =========================================================
   3B) STRICT CONTINUITY / DATA-GAP FILTER
   ---------------------------------------------------------
   Purpose:
     Prevent symbols with discontinuous recent history from entering
     the scoring universe, Top20, Top50, lifecycle tables, or charts.

   Logic:
     - Build the most recent N trading dates from the imported files.
     - For each symbol, count observations over those dates.
     - Require the symbol to be present on the latest date.
     - Require complete recent coverage if STRICT_CONTINUITY=1.
     - Require all score-critical fields to be nonmissing over that window.

   This is the safeguard that should remove names like NINE when they
   have data gaps.
   ========================================================= */

%let STRICT_CONTINUITY = 1;

/* Recent trading dates from the master imported universe */
proc sort data=work.master_features(keep=date) out=work._all_recent_dates nodupkey;
  by descending date;
run;

data work._recent_dates_required;
  set work._all_recent_dates(obs=&continuity_lookback_dates);
run;

proc sql noprint;
  select count(*)
    into :N_RECENT_DATES trimmed
  from work._recent_dates_required;
quit;

%put NOTE: N_RECENT_DATES=&N_RECENT_DATES;

/* Check symbol coverage and missing score-critical fields */
proc sql;
  create table work._symbol_continuity_check as
  select
      a.symbol,
      count(distinct a.date) as n_obs_recent,
      max(a.date) as max_symbol_dt format=yymmdd10.,

      sum(missing(a.close_price)) as miss_close_price,
      sum(missing(a.d30_volume))  as miss_d30_volume,

      sum(missing(a.x3slope))     as miss_x3slope,
      sum(missing(a.x4slope))     as miss_x4slope,
      sum(missing(a.x5slope))     as miss_x5slope,
      sum(missing(a.x14slope))    as miss_x14slope,
      sum(missing(a.x21slope))    as miss_x21slope,
      sum(missing(a.x30slope))    as miss_x30slope

  from work.master_features a
  inner join work._recent_dates_required b
    on a.date = b.date
  group by a.symbol;
quit;

/* Eligible symbols */
proc sql;
  create table work._eligible_symbols_continuous as
  select symbol
  from work._symbol_continuity_check
  where max_symbol_dt = &MAX_DT_NUM

    %if &STRICT_CONTINUITY = 1 %then %do;
      and n_obs_recent = &N_RECENT_DATES
    %end;
    %else %do;
      and n_obs_recent >= &continuity_min_obs
    %end;

    and miss_close_price = 0
    and miss_d30_volume  = 0
    and miss_x3slope     = 0
    and miss_x4slope     = 0
    and miss_x5slope     = 0
    and miss_x14slope    = 0
    and miss_x21slope    = 0
    and miss_x30slope    = 0
  ;
quit;

/* Apply continuity filter before scoring */
proc sql;
  create table work.master_features_continuous as
  select a.*
  from work.master_features a
  inner join work._eligible_symbols_continuous b
    on a.symbol = b.symbol
  order by a.symbol, a.date;
quit;

/* QA: show any excluded current-day names that would otherwise be visible */
title "QA - Symbols Excluded by Continuity Filter";
proc sql;
  select
      c.symbol,
      c.n_obs_recent,
      c.max_symbol_dt,
      c.miss_close_price,
      c.miss_d30_volume,
      c.miss_x3slope,
      c.miss_x4slope,
      c.miss_x5slope,
      c.miss_x14slope,
      c.miss_x21slope,
      c.miss_x30slope
  from work._symbol_continuity_check c
  where c.symbol not in
        (select symbol from work._eligible_symbols_continuous)
    and c.max_symbol_dt = &MAX_DT_NUM
  order by c.n_obs_recent, c.symbol;
quit;
title;

/* Specific QA for NINE */
title "QA - NINE Continuity Check";
proc print data=work._symbol_continuity_check noobs;
  where symbol = 'NINE';
run;
title;


/* =========================================================
   4) DAILY SCORING + RANKING DATABASE
   ========================================================= */

data work.daily_features;
  set work.master_features_continuous;

  if d30_volume < &d30_floor then delete;
  if missing(x3slope)  then delete;
  if missing(x4slope)  then delete;
  if missing(x5slope)  then delete;
  if missing(x14slope) then delete;
  if missing(x21slope) then delete;
  if missing(x30slope) then delete;

  avg_long    = mean(x14slope, x21slope, x30slope);
  short_alpha = (0.5*x4slope) + (0.3*x3slope) + (0.2*x5slope);
  logvol      = log10(max(d30_volume,1));
run;

proc sort data=work.daily_features;
  by date symbol;
run;

proc summary data=work.daily_features nway;
  class date;
  var avg_long short_alpha logvol;
  output out=work.daily_stats(drop=_type_ _freq_)
    mean(avg_long)=mu_avg_long
    std(avg_long)=sd_avg_long
    mean(short_alpha)=mu_short_alpha
    std(short_alpha)=sd_short_alpha
    mean(logvol)=mu_logvol
    std(logvol)=sd_logvol;
run;

proc sort data=work.daily_stats;
  by date;
run;

data work.daily_scored;
  merge work.daily_features(in=a)
        work.daily_stats(in=b);
  by date;
  if a;

  if missing(sd_avg_long) or sd_avg_long=0 then z_avg_long=0;
  else z_avg_long=(avg_long-mu_avg_long)/sd_avg_long;

  if missing(sd_short_alpha) or sd_short_alpha=0 then z_short_alpha=0;
  else z_short_alpha=(short_alpha-mu_short_alpha)/sd_short_alpha;

  if missing(sd_logvol) or sd_logvol=0 then z_logvol=0;
  else z_logvol=(logvol-mu_logvol)/sd_logvol;

  avg_long_raw    = avg_long;
  short_alpha_raw = short_alpha;
  logvol_raw      = logvol;

  EQ_score_vol = (&W_LONG*z_avg_long) + (&W_SHORT*z_short_alpha) + (&W_VOL*z_logvol);
run;

proc sort data=work.daily_scored;
  by date descending EQ_score_vol descending d30_volume symbol;
run;

data work.rank_temp;
  set work.daily_scored;
  by date descending EQ_score_vol descending d30_volume symbol;
  retain rank_EQ;
  if first.date then rank_EQ = 1;
  else rank_EQ + 1;
run;

proc sql;
  create table work.universe_size as
  select date, max(rank_EQ) as universe_n
  from work.rank_temp
  group by date;
quit;

proc sql;
  create table EQI.stock_master_daily as
  select
      a.date,
      a.symbol,
      a.name,
      a.sector,
      a.industry,
      a.close_price,
      a.d30_volume,
      a.x1slope,
      a.x2slope,
      a.x3slope,
      a.x4slope,
      a.x5slope,
      a.x9slope,
      a.x14slope,
      a.x21slope,
      a.x30slope,
      a.close_min_20,
      a.close_max_20,
      a.price_pos_20,
      a.delta_x21slope,
      a.term_structure_pdf,
      a.term_structure_lifecycle,
      a.slope_edge_pdf,
      a.slope_edge_lifecycle,
      a.trigger_reason_edge_pdf,
      a.trigger_reason_edge_lifecycle,
      a.avg_long_raw,
      a.short_alpha_raw,
      a.logvol_raw,
      a.z_avg_long,
      a.z_short_alpha,
      a.z_logvol,
      a.EQ_score_vol,
      a.rank_EQ,
      b.universe_n,
      a.source_file
  from work.rank_temp a
  left join work.universe_size b
    on a.date=b.date
  order by a.date, a.rank_EQ, a.symbol;
quit;

/* Lifecycle-compatible ranked universe */
proc sql;
  create table EQI.daily_ranked_universe as
  select
      date,
      symbol,
      name,
      sector,
      industry,
      close_price,
      d30_volume,
      x3slope,
      x4slope,
      x5slope,
      x14slope,
      x21slope,
      x30slope,
      avg_long_raw,
      short_alpha_raw,
      logvol_raw,
      z_avg_long,
      z_short_alpha,
      z_logvol,
      EQ_score_vol,
      rank_EQ,
      universe_n,
      delta_x21slope,
      term_structure_lifecycle as term_structure,
      price_pos_20,
      slope_edge_lifecycle as slope_edge,
      trigger_reason_edge_lifecycle as trigger_reason_edge,
      source_file
  from EQI.stock_master_daily
  order by date, rank_EQ, symbol;
quit;

/* =========================================================
   5) TOP50/TOP20 SNAPSHOTS AND EQ FOCUS TABLES
   ========================================================= */
proc sql;
  create table work.top50_today_rank as
  select *, term_structure_pdf as term_structure, slope_edge_pdf as slope_edge
  from EQI.stock_master_daily
  where date=&MAX_DT_NUM and rank_EQ <= &topN
  order by rank_EQ, symbol;

  create table work.top50_yday_rank as
  select *, term_structure_pdf as term_structure, slope_edge_pdf as slope_edge
  from EQI.stock_master_daily
  where date=&YDAY_DT_NUM and rank_EQ <= &topN
  order by rank_EQ, symbol;

  create table EQI.curr_topN as
  select *
  from EQI.daily_ranked_universe
  where date=&MAX_DT_NUM and rank_EQ <= &topN
  order by rank_EQ, symbol;

  create table EQI.prev_topN as
  select *
  from EQI.daily_ranked_universe
  where date=&YDAY_DT_NUM and rank_EQ <= &topN
  order by rank_EQ, symbol;

  create table EQI.curr_lifecycle_topN as
  select *
  from EQI.daily_ranked_universe
  where date=&MAX_DT_NUM and rank_EQ <= &lifecycle_topN
  order by rank_EQ, symbol;

  create table EQI.prev_lifecycle_topN as
  select *
  from EQI.daily_ranked_universe
  where date=&YDAY_DT_NUM and rank_EQ <= &lifecycle_topN
  order by rank_EQ, symbol;
quit;

/* Permanent Top50 event table from current/prior Top50 */
proc sql;
  create table EQI.eq_topN_events_vol as
  select
      c.date,
      c.symbol,
      c.name,
      c.sector,
      c.industry,
      c.close_price,
      c.d30_volume,
      c.rank_EQ,
      p.rank_EQ as prior_rank_EQ,
      calculated prior_rank_EQ - c.rank_EQ as rank_delta_1d,
      c.EQ_score_vol,
      p.EQ_score_vol as prior_EQ_score_vol,
      c.EQ_score_vol - p.EQ_score_vol as EQ_delta_1d,
      c.delta_x21slope,
      c.term_structure,
      c.price_pos_20,
      c.slope_edge,
      c.trigger_reason_edge,
      case
        when p.symbol is null then 'Entry'
        when p.rank_EQ > c.rank_EQ then 'Promotion'
        when p.rank_EQ < c.rank_EQ then 'Demotion'
        else 'Flat'
      end as event_type length=12
  from EQI.curr_topN c
  left join EQI.prev_topN p
    on c.symbol = p.symbol
  order by c.rank_EQ, c.symbol;

  create table EQI.eq_topN_exits_vol as
  select
      p.date as prior_date format=yymmdd10.,
      &MAX_DT_NUM as current_date format=yymmdd10.,
      p.symbol,
      p.name,
      p.sector,
      p.industry,
      p.rank_EQ as prior_rank_EQ,
      'Exit' as event_type length=12
  from EQI.prev_topN p
  left join EQI.curr_topN c
    on p.symbol = c.symbol
  where c.symbol is null
  order by p.rank_EQ, p.symbol;
quit;

/* =========================================================
   TABLE 1 DATA: TOP20 CHANGE UNIVERSE ONLY
   ---------------------------------------------------------
   Corrected:
     - Keeps only current Top20 and/or prior Top20 symbols
     - Removes history-only symbols from Table 1
     - Adds first_top20_date
     - Adds days_since_first_top20
     - Excludes SlopeEdge and TermStructure from report
   ========================================================= */

data work.top20_today_sym;
  set work.top50_today_rank;
  if rank_EQ <= &table1N;
run;

data work.top20_yday_sym;
  set work.top50_yday_rank;
  if rank_EQ <= &table1N;
run;

proc sort data=work.top20_today_sym;
  by symbol;
run;

proc sort data=work.top20_yday_sym;
  by symbol;
run;

/* Top20-specific tenure history for Table 1 */
proc sql;
  create table work.hist_top20_table1 as
  select
      symbol,
      min(date) as first_top20_date format=yymmdd10.
  from EQI.stock_master_daily
  where date >= &TENURE_CUTDT
    and date <= &MAX_DT_NUM
    and rank_EQ <= &table1N
  group by symbol;
quit;

proc sort data=work.hist_top20_table1;
  by symbol;
run;

data work.promo_demo_sorted;
  merge
    work.top20_today_sym(in=t
      keep=symbol sector industry d30_volume close_price EQ_score_vol rank_EQ
           delta_x21slope price_pos_20
      rename=(rank_EQ=rank_today
              EQ_score_vol=EQ_today
              close_price=close_today
              d30_volume=d30_today
              delta_x21slope=dx21_today
              price_pos_20=pp_today))

    work.top20_yday_sym(in=y
      keep=symbol sector industry d30_volume close_price EQ_score_vol rank_EQ
           delta_x21slope price_pos_20
      rename=(rank_EQ=rank_yday
              EQ_score_vol=EQ_yday
              close_price=close_yday
              d30_volume=d30_yday
              sector=sector_y
              industry=industry_y
              delta_x21slope=dx21_yday
              price_pos_20=pp_yday))

    work.hist_top20_table1(in=h);

  by symbol;

  /* Critical fix:
     Drop symbols that only exist in the Top20 history table.
     Table 1 should only contain the union of today's Top20 and yesterday's Top20. */
  if not (t or y) then delete;

  length change_type $12;

  sector       = coalescec(sector, sector_y);
  industry     = coalescec(industry, industry_y);
  d30_volume   = coalesce(d30_today, d30_yday);
  close_price  = coalesce(close_today, close_yday);
  EQ_score_vol = coalesce(EQ_today, EQ_yday);

  delta_x21slope = coalesce(dx21_today, dx21_yday);
  price_pos_20   = coalesce(pp_today, pp_yday);

  rank_EQ      = rank_today;
  rank_EQ_yday = rank_yday;

  if t and y then do;
    delta_rank = rank_yday - rank_today;

    if delta_rank > 0 then change_type = 'Promotion';
    else if delta_rank < 0 then change_type = 'Demotion';
    else change_type = 'Flat';
  end;
  else if t and not y then do;
    change_type = 'Entry';
    delta_rank = .;
  end;
  else if y and not t then do;
    change_type = 'Exit';
    delta_rank = .;
    rank_EQ = .;
  end;

  if missing(first_top20_date) then first_top20_date = &MAX_DT_NUM;

  days_since_first_top20 = (&MAX_DT_NUM - first_top20_date) + 1;

  if change_type = 'Promotion' then sort_order = 1;
  else if change_type = 'Entry' then sort_order = 2;
  else if change_type = 'Demotion' then sort_order = 3;
  else if change_type = 'Exit' then sort_order = 4;
  else if change_type = 'Flat' then sort_order = 5;

  sort_rank = coalesce(rank_today, rank_yday);

  promo_key = .;
  demo_key  = .;

  if change_type = 'Promotion' then promo_key = -delta_rank;
  if change_type = 'Demotion'  then demo_key  =  delta_rank;

  keep change_type symbol sector industry
       rank_EQ rank_EQ_yday delta_rank
       EQ_score_vol d30_volume close_price
       delta_x21slope price_pos_20
       first_top20_date days_since_first_top20
       sort_order promo_key demo_key sort_rank;
run;

proc sort data=work.promo_demo_sorted;
  by sort_order promo_key demo_key sort_rank symbol;
run;

data work.promo_demo_sorted;
  set work.promo_demo_sorted;
  drop sort_order promo_key demo_key sort_rank;
run;

/* QA check: Table 1 should be the union of current Top20 and prior Top20.
   It can be more than 20 rows because exits are included, but should not be 50+ or 100+. */
title "QA - Table 1 Row Count";
proc sql;
  select count(*) as table1_rows
  from work.promo_demo_sorted;

  select change_type, count(*) as n
  from work.promo_demo_sorted
  group by change_type
  order by change_type;
quit;
title;

/* Table 2: Top50 tenure */
proc sql;
  create table work.hist_3m as
  select symbol, min(date) as first_topN_date format=yymmdd10.
  from EQI.stock_master_daily
  where date >= &TENURE_CUTDT and date <= &MAX_DT_NUM and rank_EQ <= &topN
  group by symbol;
quit;

proc sql;
  create table work.hist_3m as
  select h.symbol,
         h.first_topN_date,
         e.close_price as first_topN_close
  from work.hist_3m h
  left join EQI.stock_master_daily e
    on h.symbol=e.symbol and h.first_topN_date=e.date;
quit;

proc sort data=work.hist_3m; by symbol; run;
proc sort data=work.top50_today_rank out=work.top50_today_sym; by symbol; run;

data work.top_today_enriched_sorted;
  merge work.top50_today_sym(in=t) work.hist_3m(in=h);
  by symbol;
  if t;

  if missing(first_topN_date)  then first_topN_date  = &MAX_DT_NUM;
  if missing(first_topN_close) then first_topN_close = close_price;

  days_since_first_topN = (&MAX_DT_NUM - first_topN_date) + 1;
  if not missing(first_topN_close) and first_topN_close>0 then
    pct_return_since_first = (close_price - first_topN_close) / first_topN_close;
  else pct_return_since_first = .;

  format first_topN_date yymmdd10. pct_return_since_first percent8.2;
run;

proc sort data=work.top_today_enriched_sorted;
  by rank_EQ;
run;

/* =========================================================
   6) VOLATILITY FEATURES AND TOP50
   ========================================================= */
proc sort data=EQI.stock_master_daily out=work.vol_src;
  by symbol date;
run;

data work.xtest_ret;
  set work.vol_src;
  by symbol date;
  retain prev_close;

  ret_1d = .; abs_ret_1d = .;
  if first.symbol then prev_close = .;

  if not first.symbol and prev_close > 0 and close_price > 0 then do;
    ret_1d     = (close_price / prev_close) - 1;
    abs_ret_1d = abs(ret_1d);
  end;

  prev_close = close_price;
  format ret_1d abs_ret_1d percent10.2;
run;

data work.xtest_vol_raw;
  set work.xtest_ret;
  by symbol date;

  array r[20]   _temporary_;
  array a[20]   _temporary_;
  array h3[20]  _temporary_;
  array h5[20]  _temporary_;
  retain idx n_obs;

  if first.symbol then do;
    idx=0; n_obs=0;
    do i=1 to 20; r[i]=.; a[i]=.; h3[i]=.; h5[i]=.; end;
  end;

  if not missing(ret_1d) then do;
    idx + 1;
    if idx > 20 then idx = 1;
    r[idx]  = ret_1d;
    a[idx]  = abs_ret_1d;
    h3[idx] = (abs_ret_1d >= 0.03);
    h5[idx] = (abs_ret_1d >= 0.05);
    if n_obs < 20 then n_obs + 1;
  end;

  hv_20=.; hv_20_ann=.; avg_abs_ret_20=.; max_abs_ret_20=.; hit_3pct_20=.; hit_5pct_20=.;

  if n_obs >= 20 then do;
    sum_r=0; sum_r2=0; sum_abs=0; max_abs=.; cnt=0; cnt3=0; cnt5=0;
    do i=1 to 20;
      if not missing(r[i]) then do;
        cnt+1; sum_r+r[i]; sum_r2+r[i]*r[i]; sum_abs+a[i];
        if missing(max_abs) then max_abs=a[i]; else if a[i] > max_abs then max_abs=a[i];
        if h3[i]=1 then cnt3+1;
        if h5[i]=1 then cnt5+1;
      end;
    end;
    if cnt=20 then do;
      mean_r=sum_r/cnt;
      var_r=(sum_r2 - cnt*(mean_r**2))/(cnt-1);
      if var_r < 0 then var_r=0;
      hv_20=sqrt(var_r);
      hv_20_ann=hv_20*sqrt(252);
      avg_abs_ret_20=sum_abs/cnt;
      max_abs_ret_20=max_abs;
      hit_3pct_20=cnt3;
      hit_5pct_20=cnt5;
    end;
  end;

  format hv_20 hv_20_ann avg_abs_ret_20 max_abs_ret_20 percent10.2;
  drop i idx n_obs sum_: cnt cnt3 cnt5 mean_r var_r max_abs prev_close;
run;

proc sort data=work.xtest_vol_raw; by date; run;

proc means data=work.xtest_vol_raw noprint;
  by date;
  var avg_abs_ret_20 hv_20 max_abs_ret_20 hit_3pct_20 hit_5pct_20;
  output out=work.xtest_cs_stats
    mean=mean_avg_abs_ret_20 mean_hv_20 mean_max_abs_ret_20 mean_hit_3pct_20 mean_hit_5pct_20
    std=std_avg_abs_ret_20 std_hv_20 std_max_abs_ret_20 std_hit_3pct_20 std_hit_5pct_20;
run;

data work.xtest_vol_features;
  merge work.xtest_vol_raw(in=a) work.xtest_cs_stats(in=b);
  by date;
  if a;

  if std_avg_abs_ret_20 > 0 and not missing(avg_abs_ret_20) then z_avg_abs_ret_20=(avg_abs_ret_20-mean_avg_abs_ret_20)/std_avg_abs_ret_20; else z_avg_abs_ret_20=.;
  if std_hv_20          > 0 and not missing(hv_20)          then z_hv_20=(hv_20-mean_hv_20)/std_hv_20; else z_hv_20=.;
  if std_max_abs_ret_20 > 0 and not missing(max_abs_ret_20) then z_max_abs_ret_20=(max_abs_ret_20-mean_max_abs_ret_20)/std_max_abs_ret_20; else z_max_abs_ret_20=.;
  if std_hit_3pct_20    > 0 and not missing(hit_3pct_20)    then z_hit_3pct_20=(hit_3pct_20-mean_hit_3pct_20)/std_hit_3pct_20; else z_hit_3pct_20=.;
  if std_hit_5pct_20    > 0 and not missing(hit_5pct_20)    then z_hit_5pct_20=(hit_5pct_20-mean_hit_5pct_20)/std_hit_5pct_20; else z_hit_5pct_20=.;

  swing_score_1d = 0.60*z_avg_abs_ret_20 + 0.40*z_hit_3pct_20;
run;

proc sql;
  create table work.vol_top50_today_base as
  select date, symbol, sector, industry, close_price, d30_volume,
         ret_1d, abs_ret_1d, avg_abs_ret_20, hit_3pct_20, hit_5pct_20,
         hv_20, hv_20_ann, max_abs_ret_20, z_avg_abs_ret_20, z_hit_3pct_20,
         z_hv_20, z_max_abs_ret_20, swing_score_1d
  from work.xtest_vol_features
  where date=&MAX_DT_NUM
    and not missing(swing_score_1d)
    and not missing(avg_abs_ret_20)
    and not missing(hit_3pct_20)
    and not missing(hv_20)
    and not missing(max_abs_ret_20)
    and d30_volume >= &d30_floor
    and not missing(sector)
    and strip(sector) ne ''
  order by swing_score_1d desc, avg_abs_ret_20 desc, hit_3pct_20 desc, hv_20 desc;
quit;

data work.vol_top50_today;
  set work.vol_top50_today_base(obs=50);
  rank_vol = _n_;
  format close_price 12.2 d30_volume comma15.
         ret_1d abs_ret_1d avg_abs_ret_20 hv_20 hv_20_ann max_abs_ret_20 percent10.2
         swing_score_1d 10.4;
run;

data EQI.vol_top50_today;
  set work.vol_top50_today;
run;

proc export data=EQI.vol_top50_today
  outfile="&BASEDIR./vol_top50_today.csv"
  dbms=csv replace;
run;

/* =========================================================
   7) EQ FOCUS LR CHART INPUTS: TOP20 ONLY
   ========================================================= */
data work.top_today_chart_rank;
  set work.top50_today_rank;
  if rank_EQ <= &chartN;
run;

proc sql;
  create table work.allwin_top_chart as
  select a.*, t.rank_EQ as today_rank_EQ
  from EQI.stock_master_raw a
  inner join work.top_today_chart_rank t
    on a.symbol=t.symbol
  order by a.symbol, a.date;
quit;

data work.plot_long;
  set work.allwin_top_chart;
  length tf $6;
  price = close_price;

  array s{9} x1slope x2slope x3slope x4slope x5slope x9slope x14slope x21slope x30slope;
  array lab{9} $6 _temporary_ ('x1','x2','x3','x4','x5','x9','x14','x21','x30');

  do i=1 to dim(s);
    tf=lab{i}; slope=s{i}; rank_EQ=today_rank_EQ; output;
  end;

  keep symbol rank_EQ date tf slope price;
run;

proc sort data=work.plot_long; by symbol tf date; run;

data work.plot_lr;
  set work.plot_long;
  by symbol tf date;

  length L 8;
  select (strip(tf));
    when ('x1')  L=30;
    when ('x2')  L=35;
    when ('x3')  L=40;
    when ('x4')  L=45;
    when ('x5')  L=50;
    when ('x9')  L=45;
    when ('x14') L=50;
    when ('x21') L=60;
    when ('x30') L=70;
    otherwise L=. ;
  end;

  retain filled 0;
  array ybuf[70] _temporary_;

  if first.tf then do;
    call missing(of ybuf[*]);
    filled=0;
  end;

  do _i=1 to 69; ybuf[_i]=ybuf[_i+1]; end;
  ybuf[70]=slope;
  if filled < 70 then filled+1;

  L_eff=min(L, filled);
  lr_value=. ;

  if not missing(L_eff) and L_eff >= 2 then do;
    sumt=L_eff*(L_eff+1)/2;
    sumt2=L_eff*(L_eff+1)*(2*L_eff+1)/6;
    sumy=0; sumty=0;
    start=70-L_eff+1;

    do _k=1 to L_eff;
      yv=ybuf[start+_k-1];
      if missing(yv) then do; sumy=.; leave; end;
      sumy+yv; sumty+(_k*yv);
    end;

    if not missing(sumy) then do;
      denom=(L_eff*sumt2 - sumt*sumt);
      if denom ne 0 then do;
        b=(L_eff*sumty - sumt*sumy)/denom;
        a=(sumy - b*sumt)/L_eff;
        lr_value=a + b*L_eff;
      end;
    end;
  end;

  drop L filled L_eff start sumt sumt2 sumy sumty denom a b yv _i _k;
run;

data work.plot_lr_plot;
  set work.plot_lr;
  price_plot=. ;
  if tf='x1' then price_plot=price;
run;

proc sort data=work.plot_lr_plot; by symbol date tf; run;

data work.tf_attrmap;
  length id $12 value $6 linecolor $12 linepattern $12;
  id='TFCLR'; linepattern='SOLID';
  value='x1' ; linecolor='CXFF0000'; output;
  value='x2' ; linecolor='CXFFA500'; output;
  value='x3' ; linecolor='CXFFFF00'; output;
  value='x4' ; linecolor='CX00FF00'; output;
  value='x5' ; linecolor='CX00FFFF'; output;
  value='x9' ; linecolor='CX0000FF'; output;
  value='x14'; linecolor='CX800080'; output;
  value='x21'; linecolor='CX808080'; output;
  value='x30'; linecolor='CX000000'; output;
run;

/* =========================================================
   8) ALERT LIFECYCLE MODULE
   ========================================================= */
proc sql;
  create table EQI.alert_entries as
  select a.symbol,
         min(a.date) as entry_date format=yymmdd10.,
         'BUY' as alert_type length=20,
         'Auto-seeded from current Top 20' as notes length=200
  from EQI.daily_ranked_universe a
  inner join EQI.curr_lifecycle_topN b
    on a.symbol=b.symbol
  where a.rank_EQ <= &lifecycle_topN
  group by a.symbol
  order by calculated entry_date, a.symbol;
quit;

proc sql noprint;
  select count(*) into :n_alerts trimmed from EQI.alert_entries;
  select count(*) into :n_sample_alerts trimmed from EQI.alert_entries where symbol in ('VZ','CF','PBR');
  select count(*) into :n_curr_lifecycle_topN trimmed from EQI.curr_lifecycle_topN;
quit;

%macro guard_alerts;
  %if &n_alerts = 3 and &n_sample_alerts = 3 and &n_curr_lifecycle_topN > 3 %then %do;
    %put ERROR: ALERT_ENTRIES is still only VZ/CF/PBR while CURR_LIFECYCLE_TOPN has more than 3 names.;
    %abort cancel;
  %end;
%mend;
%guard_alerts;

proc sql;
  create table EQI.entry_snapshot as
  select e.symbol, e.entry_date, e.alert_type, e.notes,
         d.name as entry_name,
         d.sector as entry_sector,
         d.industry as entry_industry,
         d.close_price as entry_price,
         d.rank_EQ as entry_rank_EQ,
         d.EQ_score_vol as entry_EQ_score_vol
  from EQI.alert_entries e
  left join EQI.daily_ranked_universe d
    on e.symbol=d.symbol and e.entry_date=d.date;
quit;

data EQI.entry_snapshot_audit;
  set EQI.entry_snapshot;
  missing_entry_row_flag = (missing(entry_price) or missing(entry_rank_EQ) or missing(entry_EQ_score_vol));
run;

proc sql;
  create table work.lifecycle_base as
  select e.symbol, e.entry_date, e.alert_type, e.notes,
         d.date, d.name, d.sector, d.industry, d.close_price, d.d30_volume,
         d.EQ_score_vol, d.rank_EQ, d.universe_n,
         d.delta_x21slope, d.term_structure, d.price_pos_20, d.slope_edge,
         s.entry_price, s.entry_rank_EQ, s.entry_EQ_score_vol
  from EQI.alert_entries e
  inner join EQI.daily_ranked_universe d
    on e.symbol=d.symbol and d.date >= e.entry_date
  left join EQI.entry_snapshot s
    on e.symbol=s.symbol and e.entry_date=s.entry_date
  order by e.symbol, e.entry_date, d.date;
quit;

data EQI.signal_lifecycle_daily;
  set work.lifecycle_base;
  by symbol entry_date date;

  format prior_date yymmdd10.;
  length rank_zone $20 status_label $30 prior_status_label $30 trigger_reason $200;
  retain prior_date prior_rank_EQ prior_EQ_score_vol prior_close_price;
  retain eq_down_streak prior_status_label trade_day_idx;

  if first.entry_date then do;
    prior_date=.; prior_rank_EQ=.; prior_EQ_score_vol=.; prior_close_price=.;
    eq_down_streak=0; prior_status_label=''; trade_day_idx=0;
  end;
  else trade_day_idx+1;

  trading_days_since_entry  = trade_day_idx;
  calendar_days_since_entry = intck('day', entry_date, date);

  if not missing(prior_rank_EQ) then rank_delta_1d = prior_rank_EQ - rank_EQ; else rank_delta_1d=.;
  if not missing(prior_EQ_score_vol) then EQ_delta_1d = EQ_score_vol - prior_EQ_score_vol; else EQ_delta_1d=.;
  if not missing(prior_close_price) and prior_close_price>0 then price_return_1d = (close_price/prior_close_price)-1; else price_return_1d=.;
  if not missing(entry_rank_EQ) then rank_delta_from_entry = entry_rank_EQ - rank_EQ; else rank_delta_from_entry=.;
  if not missing(entry_EQ_score_vol) then EQ_delta_from_entry = EQ_score_vol - entry_EQ_score_vol; else EQ_delta_from_entry=.;
  if not missing(entry_price) and entry_price>0 then price_return_since_entry = (close_price/entry_price)-1; else price_return_since_entry=.;

  if not missing(EQ_delta_1d) then do;
    if EQ_delta_1d < 0 then eq_down_streak+1;
    else eq_down_streak=0;
  end;
  else eq_down_streak=0;

  EQ_down_2d_flag = (eq_down_streak >= 2);
  EQ_down_3d_flag = (eq_down_streak >= 3);

  if rank_EQ <= &TOP_STRONG then rank_zone=cats('Top ',&TOP_STRONG);
  else if rank_EQ <= &TOP_WEAK then rank_zone=cats('Top ',&TOP_WEAK);
  else if rank_EQ <= &TOP_BROKEN then rank_zone=cats('Top ',&TOP_BROKEN);
  else rank_zone='Below Top 100';

  rank_drop_15_1d_flag         = (not missing(rank_delta_1d) and rank_delta_1d <= &RANK_DROP_1D_REEVAL);
  rank_drop_25_from_entry_flag = (not missing(rank_delta_from_entry) and rank_delta_from_entry <= &RANK_DROP_ENTRY_REEVAL);
  rank_drop_75_from_entry_flag = (not missing(rank_delta_from_entry) and rank_delta_from_entry <= &RANK_DROP_ENTRY_BROKEN);

  if universe_n > 1 then rank_percentile = 1 - ((rank_EQ - 1) / (universe_n - 1)); else rank_percentile=.;

  if rank_EQ > &TOP_BROKEN
     or rank_drop_75_from_entry_flag
     or (rank_EQ > &TOP_WEAK and price_return_since_entry < 0 and EQ_down_3d_flag=1)
  then status_label='Broken';
  else if rank_drop_15_1d_flag
       or rank_drop_25_from_entry_flag
       or EQ_down_3d_flag=1
       or rank_EQ > &TOP_WEAK
  then status_label='Re-Evaluate';
  else if rank_EQ <= &TOP_STRONG and coalesce(EQ_delta_1d,0) >= 0 and EQ_down_3d_flag=0
  then status_label='Active-Strong';
  else if rank_EQ <= &TOP_WEAK then status_label='Active-Weakening';
  else status_label='Unclassified';

  status_changed_flag = (not missing(prior_status_label) and status_label ne prior_status_label);

  trigger_reason='';
  if status_label='Broken' then do;
    if rank_EQ > &TOP_BROKEN then trigger_reason='Rank fell below allowed zone';
    else if rank_drop_75_from_entry_flag then trigger_reason='Rank deterioration from entry exceeded Broken threshold';
    else if (rank_EQ > &TOP_WEAK and price_return_since_entry < 0 and EQ_down_3d_flag=1)
      then trigger_reason='Outside weak zone + below entry + 3-day EQ decline';
  end;
  else if status_label='Re-Evaluate' then do;
    if rank_drop_15_1d_flag then trigger_reason='1-day rank deterioration exceeded threshold';
    else if rank_drop_25_from_entry_flag then trigger_reason='Rank deterioration from entry exceeded threshold';
    else if EQ_down_3d_flag=1 then trigger_reason='EQ_score_vol declined 3 straight days';
    else if rank_EQ > &TOP_WEAK then trigger_reason='Rank fell outside weak zone';
  end;
  else if status_label='Active-Strong' then trigger_reason='Top zone rank with stable/rising EQ_score';
  else if status_label='Active-Weakening' then trigger_reason='Still inside weak zone but no longer strong';
  else trigger_reason='No rule matched';

  output;

  prior_date=date;
  prior_rank_EQ=rank_EQ;
  prior_EQ_score_vol=EQ_score_vol;
  prior_close_price=close_price;
  prior_status_label=status_label;
run;

data EQI.active_signals_today EQI.status_changes_today EQI.broken_signals_today;
  set EQI.signal_lifecycle_daily;
  where date=&MAX_DT_NUM;
  if status_label in ('Active-Strong','Active-Weakening','Re-Evaluate') then output EQI.active_signals_today;
  if status_changed_flag=1 then output EQI.status_changes_today;
  if status_label='Broken' then output EQI.broken_signals_today;
run;

proc sql;
  create table EQI.signal_status_summary_today as
  select date, status_label, count(*) as n_signals
  from EQI.signal_lifecycle_daily
  where date=&MAX_DT_NUM
  group by date, status_label
  order by calculated n_signals desc, status_label;
quit;

/* =========================================================
   9) LIFECYCLE PLOT INPUTS AND QUADRANT INPUTS
   ========================================================= */
proc sql;
  create table work._seeded_latest as
  select * from EQI.signal_lifecycle_daily
  where date=&MAX_DT_NUM and symbol in (select symbol from EQI.alert_entries)
  order by rank_EQ, symbol;
quit;

data work._plot_top20;
  set work._seeded_latest(obs=20);
  keep symbol entry_date rank_EQ rank_delta_from_entry status_label;
run;

data work._plot_symbols;
  set work._plot_top20;
  keep symbol entry_date;
run;

proc sort data=work._plot_symbols nodupkey; by symbol entry_date; run;

proc sql;
  create table work._plot_base as
  select a.symbol, a.entry_date, a.date, a.name, a.sector, a.close_price,
         a.rank_EQ, a.EQ_score_vol, a.status_label, a.status_changed_flag,
         a.rank_delta_from_entry
  from EQI.signal_lifecycle_daily a
  inner join work._plot_symbols b
    on a.symbol=b.symbol and a.entry_date=b.entry_date
  order by a.symbol, a.entry_date, a.date;
quit;

data work._plot_base_prep;
  set work._plot_base;
  by symbol entry_date date;
  eq_plot=EQ_score_vol;
  if date=entry_date then do; entry_price_marker=close_price; entry_eq_marker=eq_plot; end;
  else do; entry_price_marker=.; entry_eq_marker=.; end;
  if status_changed_flag=1 then do; status_price_marker=close_price; status_eq_marker=eq_plot; end;
  else do; status_price_marker=.; status_eq_marker=.; end;
run;

data work._page1_loop;
  set work._plot_top20;
run;

/* Quadrant base */
proc sql;
  create table work.prev_eq_lookup as
  select symbol, EQ_score_vol as prior_EQ_score_vol
  from EQI.daily_ranked_universe
  where date=&YDAY_DT_NUM;
quit;

proc sql;
  create table work.quad_base as
  select c.symbol, a.entry_date, c.date,
         coalescec(l.status_label,'Other') as status_label length=30,
         c.EQ_score_vol,
         p.prior_EQ_score_vol,
         (c.EQ_score_vol - p.prior_EQ_score_vol) as EQ_delta_1d,
         c.rank_EQ,
         l.rank_delta_from_entry,
         l.price_return_since_entry,
         l.trading_days_since_entry
  from EQI.curr_lifecycle_topN c
  inner join EQI.alert_entries a
    on c.symbol=a.symbol
  left join work.prev_eq_lookup p
    on c.symbol=p.symbol
  left join EQI.signal_lifecycle_daily l
    on c.symbol=l.symbol and a.entry_date=l.entry_date and l.date=c.date
  where c.date=&MAX_DT_NUM
  order by c.rank_EQ, c.symbol;
quit;

data work.quad_points;
  length status_group $24 zone $32 poly_id $8 quad_label $32 plot_label $60;
  set work.quad_base;
  x_score=EQ_score_vol;
  y_delta=EQ_delta_1d;
  plot_label=cats(symbol,'(',strip(put(rank_EQ,2.)),')');

  if status_label='Active-Strong' then status_group='Active-Strong';
  else if status_label='Active-Weakening' then status_group='Active-Weakening';
  else if status_label='Re-Evaluate' then status_group='Re-Evaluate';
  else if status_label='Broken' then status_group='Broken';
  else status_group='Other';

  x_halo=x_score; y_halo=y_delta;
  poly_x=.; poly_y=.; quad_x=.; quad_y=.; quad_label=''; zone=''; poly_id='';
run;

data work.all_attrmap;
  length id $12 value $32 markercolor linecolor fillcolor $12;
  id='statusmap';
  value='Active-Strong'; markercolor='cx2E8B57'; linecolor='cx2E8B57'; fillcolor='cx2E8B57'; output;
  value='Active-Weakening'; markercolor='cxD9A300'; linecolor='cxD9A300'; fillcolor='cxD9A300'; output;
  value='Re-Evaluate'; markercolor='cxC65D00'; linecolor='cxC65D00'; fillcolor='cxC65D00'; output;
  value='Broken'; markercolor='cxC00000'; linecolor='cxC00000'; fillcolor='cxC00000'; output;
  value='Other'; markercolor='cx808080'; linecolor='cx808080'; fillcolor='cx808080'; output;

  id='zonemap';
  value='Broken Zone'; markercolor='cxF4CCCC'; linecolor='cxF4CCCC'; fillcolor='cxF4CCCC'; output;
  value='Re-Evaluate Zone'; markercolor='cxFCE5CD'; linecolor='cxFCE5CD'; fillcolor='cxFCE5CD'; output;
  value='Active-Weakening Zone'; markercolor='cxFFF2CC'; linecolor='cxFFF2CC'; fillcolor='cxFFF2CC'; output;
  value='Active-Strong Zone'; markercolor='cxD9EAD3'; linecolor='cxD9EAD3'; fillcolor='cxD9EAD3'; output;
run;

proc sql noprint;
  select min(x_score), max(x_score), min(y_delta), max(y_delta)
    into :x_min, :x_max, :y_min, :y_max
  from work.quad_points
  where not missing(x_score) and not missing(y_delta);
quit;

data _null_;
  x_min=input(symget('x_min'),best32.); x_max=input(symget('x_max'),best32.);
  y_min=input(symget('y_min'),best32.); y_max=input(symget('y_max'),best32.);
  x_pad=(x_max-x_min)*0.10; y_pad=(y_max-y_min)*0.15;
  if x_pad <= 0 then x_pad=0.25;
  if y_pad <= 0 then y_pad=0.05;
  call symputx('x_lo',x_min-x_pad); call symputx('x_hi',x_max+x_pad);
  call symputx('y_lo',y_min-y_pad); call symputx('y_hi',y_max+y_pad);
run;

proc means data=work.quad_points noprint;
  var x_score;
  output out=work.quad_stats median=x_mid;
run;

data _null_;
  set work.quad_stats;
  call symputx('x_mid',x_mid);
  call symputx('y_mid',0);
run;

data work.quad_polys;
  length status_group $24 zone $32 poly_id $8 quad_label $32 plot_label $60;
  x_lo=input(symget('x_lo'),best32.); x_hi=input(symget('x_hi'),best32.);
  y_lo=input(symget('y_lo'),best32.); y_hi=input(symget('y_hi'),best32.);
  x_mid=input(symget('x_mid'),best32.); y_mid=input(symget('y_mid'),best32.);
  x_score=.; y_delta=.; x_halo=.; y_halo=.; symbol=''; status_label=''; status_group=''; plot_label=''; rank_EQ=. ;

  zone='Broken Zone'; poly_id='BL'; poly_x=x_lo; poly_y=y_lo; output; poly_x=x_mid; poly_y=y_lo; output; poly_x=x_mid; poly_y=y_mid; output; poly_x=x_lo; poly_y=y_mid; output;
  zone='Re-Evaluate Zone'; poly_id='TL'; poly_x=x_lo; poly_y=y_mid; output; poly_x=x_mid; poly_y=y_mid; output; poly_x=x_mid; poly_y=y_hi; output; poly_x=x_lo; poly_y=y_hi; output;
  zone='Active-Weakening Zone'; poly_id='BR'; poly_x=x_mid; poly_y=y_lo; output; poly_x=x_hi; poly_y=y_lo; output; poly_x=x_hi; poly_y=y_mid; output; poly_x=x_mid; poly_y=y_mid; output;
  zone='Active-Strong Zone'; poly_id='TR'; poly_x=x_mid; poly_y=y_mid; output; poly_x=x_hi; poly_y=y_mid; output; poly_x=x_hi; poly_y=y_hi; output; poly_x=x_mid; poly_y=y_hi; output;
  quad_x=.; quad_y=.; quad_label='';
run;

data work.quad_labels;
  length status_group $24 zone $32 poly_id $8 quad_label $32 plot_label $60;
  x_lo=input(symget('x_lo'),best32.); x_hi=input(symget('x_hi'),best32.);
  y_lo=input(symget('y_lo'),best32.); y_hi=input(symget('y_hi'),best32.);
  x_mid=input(symget('x_mid'),best32.); y_mid=input(symget('y_mid'),best32.);
  x_score=.; y_delta=.; x_halo=.; y_halo=.; poly_x=.; poly_y=.; symbol=''; status_label=''; status_group=''; plot_label=''; rank_EQ=. ; zone=''; poly_id='';
  quad_x=(x_lo+x_mid)/2; quad_y=y_hi-(y_hi-y_mid)*0.08; quad_label='Weak but Rising'; output;
  quad_x=(x_mid+x_hi)/2; quad_y=y_hi-(y_hi-y_mid)*0.08; quad_label='Strong and Improving'; output;
  quad_x=(x_lo+x_mid)/2; quad_y=y_lo+(y_mid-y_lo)*0.08; quad_label='Weak and Deteriorating'; output;
  quad_x=(x_mid+x_hi)/2; quad_y=y_lo+(y_mid-y_lo)*0.08; quad_label='Strong but Fading'; output;
run;

data work.quad_canvas;
  set work.quad_polys work.quad_points work.quad_labels;
run;

/* =========================================================
   10) EQMI DAILY + SECTOR EQMI
   ========================================================= */
data work.all60;
  set EQI.stock_master_raw;
  if date >= &EQMI_CUT_DT and date <= &MAX_DT_NUM;
run;

proc sort data=work.all60 out=work._base60;
  by symbol date;
run;

data work._u1;
  set work._base60;
  if missing(close_price) then delete;
  if missing(d30_volume) then delete;
  if d30_volume < &d30_floor then delete;
  if missing(x14slope) or missing(x21slope) or missing(x30slope) then delete;
  avg_long = mean(x14slope, x21slope, x30slope);
  keep symbol sector date close_price d30_volume avg_long;
run;

proc sort data=work._u1;
  by symbol date;
run;

data work._u2;
  set work._u1;
  by symbol;
  prev_avg_long=lag(avg_long);
  if first.symbol then prev_avg_long=.;
  delta_avg_long=avg_long-prev_avg_long;
  if missing(delta_avg_long) then delta_avg_long=0;
  flag_long=(avg_long>0);
  flag_accel=(delta_avg_long>0);
  keep date symbol sector flag_long flag_accel;
run;

proc sql;
  create table work.eqmi_daily as
  select date format=yymmdd10., count(distinct symbol) as n,
         mean(flag_long) as p_long, mean(flag_accel) as p_accel
  from work._u2
  group by date
  order by date;
quit;

data work.eqmi_daily;
  set work.eqmi_daily;
  EQMI = 100 * (&EQMI_W_LONG*p_long + &EQMI_W_ACCEL*p_accel);
run;

data work.eqmi_daily;
  set work.eqmi_daily;
  retain EQMI_EMA3;
  if _N_=1 then EQMI_EMA3=EQMI;
  else EQMI_EMA3=(&EMA_ALPHA*EQMI) + ((1-&EMA_ALPHA)*EQMI_EMA3);
run;

data EQI.eqmi_daily;
  set work.eqmi_daily;
run;

proc export data=EQI.eqmi_daily
  outfile="&BASEDIR./EQMI_daily_last60.csv"
  dbms=csv replace;
run;

/* Sector EQMI */
proc sort data=work._u1 out=work._u1s;
  by sector symbol date;
run;

data work._u2s;
  set work._u1s;
  by sector symbol;
  prev_avg_long=lag(avg_long);
  if first.symbol then prev_avg_long=.;
  delta_avg_long=avg_long-prev_avg_long;
  if missing(delta_avg_long) then delta_avg_long=0;
  flag_long=(avg_long>0);
  flag_accel=(delta_avg_long>0);
  keep sector date symbol flag_long flag_accel;
run;

proc sql;
  create table work.eqmi_sector_daily as
  select sector, date format=yymmdd10., count(distinct symbol) as n,
         mean(flag_long) as p_long, mean(flag_accel) as p_accel
  from work._u2s
  where not missing(sector) and lowcase(strip(sector)) not in ('n/a','na','unknown','')
  group by sector, date
  order by sector, date;
quit;

data work.eqmi_sector_daily;
  set work.eqmi_sector_daily;
  EQMI = 100 * (&EQMI_W_LONG*p_long + &EQMI_W_ACCEL*p_accel);
run;

proc sort data=work.eqmi_sector_daily;
  by sector date;
run;

data work.eqmi_sector_daily;
  set work.eqmi_sector_daily;
  by sector;
  retain EQMI_EMA3;
  if first.sector then EQMI_EMA3=EQMI;
  else EQMI_EMA3=(&EMA_ALPHA*EQMI) + ((1-&EMA_ALPHA)*EQMI_EMA3);
run;

data EQI.eqmi_sector_daily;
  set work.eqmi_sector_daily;
run;

proc sql;
  create table work._sector_rank as
  select sector, mean(n) as avg_n
  from work.eqmi_sector_daily
  group by sector
  order by avg_n desc;
quit;

data work._sector_rank_top;
  set work._sector_rank(obs=&EQMI_SECTOR_TOPK);
run;

proc sql;
  create table work.eqmi_sector_plot as
  select a.*
  from work.eqmi_sector_daily a
  inner join work._sector_rank_top b
    on a.sector=b.sector
  order by a.sector, a.date;
quit;

/* =========================================================
   11) OUTPUT PDF: EQ FOCUS TOP50 + VOLATILITY
   ========================================================= */
ods _all_ close;
ods results on;
ods html5 (id=web) file=_webout options(bitmap_mode='inline');
ods pdf file="&BASEDIR/EQI_FOCUS_PLUS_90D_TOP50.pdf" style=journal notoc;

options orientation=landscape;
ods pdf startpage=now;

/* ---------- TABLE 1: TOP20 ONLY, UPDATED ---------- */

title1 "EQ Focus (VOL-weighted) - Promotions / Demotions / Entries / Exits / Flat";
title2 "Today=&MAX_FILE_DT | Prior=&YDAY_DT | Table 1 = Top&table1N | D30 floor=&d30_floor";

proc report data=work.promo_demo_sorted nowd
  style(header)=[font_size=8pt]
  style(column)=[font_size=8pt];

  columns change_type symbol sector industry
          rank_EQ rank_EQ_yday delta_rank
          EQ_score_vol d30_volume close_price
          delta_x21slope price_pos_20
          first_top20_date days_since_first_top20;

  define change_type / display "Type";
  define symbol      / display "Symbol";
  define sector      / display "Sector";
  define industry    / display "Industry";

  define rank_EQ      / display "Rank";
  define rank_EQ_yday / display "Yday Rank";
  define delta_rank   / display "Delta Rank";

  define EQ_score_vol / display "EQ_score_vol" format=8.4;
  define d30_volume   / display "D30 Vol" format=comma12.;
  define close_price  / display "Price" format=8.2;

  define delta_x21slope / display "Delta x21" format=8.4;
  define price_pos_20   / display "Pos20" format=8.3;

  define first_top20_date       / display "First Top20 Date" format=yymmdd10.;
  define days_since_first_top20 / display "Days in Top20";

    compute days_since_first_top20;
    if change_type = 'Promotion' and days_since_first_top20 in (4, 5) then
      call define(_row_, "style",
        "style=[font_weight=bold background=cxFCE4C8 foreground=cx1F2D3A]");
  endcomp;
run;

ods pdf startpage=now;
title1 "EQ Focus (VOL-weighted) - Top &topN | Tenure + Return Since First Appearance (<=&TENURE_MONTHS months)";
title2 "Today=&MAX_FILE_DT";

proc report data=work.top_today_enriched_sorted nowd
  style(header)=[font_size=8pt]
  style(column)=[font_size=8pt];
  columns rank_EQ symbol sector industry EQ_score_vol d30_volume
          delta_x21slope price_pos_20 first_topN_date first_topN_close close_price
          days_since_first_topN pct_return_since_first;
  define rank_EQ / display "Rank";
  define symbol / display "Symbol";
  define sector / display "Sector";
  define industry / display "Industry";
  define EQ_score_vol / display "EQ_score_vol" format=8.4;
  define d30_volume / display "D30 Vol" format=comma12.;
  define delta_x21slope / display "Deltax21" format=8.4;
  define price_pos_20 / display "Pos20" format=8.3;
  define first_topN_date / display "First Top50 Date (<=window)";
  define first_topN_close / display "First Top50 Price" format=8.2;
  define close_price / display "Price" format=8.2;
  define days_since_first_topN / display "Days in Top50 (<=window)";
  define pct_return_since_first / display "Return Since First" format=percent8.2;

  compute days_since_first_topN;
    if 10 <= days_since_first_topN <= 20 then call define(_col_, "style", "style=[foreground=green font_weight=bold font_size=8pt]");
  endcomp;
  compute pct_return_since_first;
    if pct_return_since_first > 0.20 then call define(_col_, "style", "style=[foreground=green font_weight=bold font_size=8pt]");
    else if pct_return_since_first < 0 then call define(_col_, "style", "style=[foreground=gray font_size=8pt]");
  endcomp;
run;

title;
ods graphics on;
ods graphics / reset=all width=7.3in height=3.1in imagemap=off;

data _null_;
  set work.top_today_chart_rank end=eof;
  call symputx(cats('SYM',_n_),strip(symbol),'L');
  if eof then call symputx('NSYM',_n_,'L');
run;

%macro PLOT_ALL_2PERPAGE;
  %local i sym;
  %do i=1 %to &NSYM;
    %let sym=&&SYM&i;
    %if %sysfunc(mod(&i,2))=1 %then %do;
      ods pdf startpage=now;
      ods layout gridded columns=1 rows=2;
    %end;

    ods region;
    title1 height=10pt "EQI 90-Day LR - &sym  |  &MAX_FILE_DT";
    title2 height=9pt "Produced in TODAY rank order | Top &chartN chart pack only | LinReg warm-up from Day 1 (x1..x30) | Price dotted black (Y2)";

    proc sgplot data=work.plot_lr_plot(where=(symbol="&sym")) dattrmap=work.tf_attrmap noautolegend;
      series x=date y=lr_value / group=tf attrid=TFCLR lineattrs=(thickness=2 pattern=solid);
      series x=date y=price_plot / y2axis lineattrs=(thickness=2 pattern=dot color=CX000000);
      xaxis display=(nolabel) valuesformat=date9.;
      yaxis label="LinReg(x, L_eff, 0)";
      y2axis label="Price";
    run;
    title;

    %if %sysfunc(mod(&i,2))=0 %then %do; ods layout end; %end;
  %end;
  %if %sysfunc(mod(&NSYM,2))=1 %then %do; ods layout end; %end;
%mend;

%PLOT_ALL_2PERPAGE;

options orientation=landscape;
ods pdf startpage=now;
title1 "Volatility Focus - Top 50 Large Daily Movers";
title2 "Date=&MAX_FILE_DT | Score = 0.60*z(Avg Abs Ret 20D) + 0.40*z(3% Days)";

proc report data=work.vol_top50_today nowd style(header)=[font_size=8pt] style(column)=[font_size=8pt];
  columns rank_vol symbol sector industry close_price d30_volume avg_abs_ret_20 hit_3pct_20 hit_5pct_20 hv_20 max_abs_ret_20 swing_score_1d;
  define rank_vol / display "Rank";
  define symbol / display "Symbol";
  define sector / display "Sector";
  define industry / display "Industry";
  define close_price / display "Price" format=8.2;
  define d30_volume / display "D30 Vol" format=comma12.;
  define avg_abs_ret_20 / display "Avg Abs Ret 20D" format=percent8.2;
  define hit_3pct_20 / display "3% Days";
  define hit_5pct_20 / display "5% Days";
  define hv_20 / display "HV 20D" format=percent8.2;
  define max_abs_ret_20 / display "Max Abs Ret 20D" format=percent8.2;
  define swing_score_1d / display "Vol Score" format=8.4;
run;

title;
ods pdf close;
ods html5 (id=web) close;

/* =========================================================
   12) OUTPUT: ALERT LIFECYCLE PDF
   ========================================================= */
ods listing close;
ods graphics / reset width=11in height=7.5in imagename="eqi_alert_lifecycle_panels" noborder;
ods pdf file="&BASEDIR./EQI_alert_lifecycle_panels.pdf" notoc startpage=no;

%macro plot_loop(loopds=, titletext=);
  %local nplots i this_sym this_edt this_status this_title2;
  proc sql noprint; select count(*) into :nplots trimmed from &loopds; quit;
  %if %sysevalf(%superq(nplots)=, boolean) %then %let nplots=0;
  %if &nplots=0 %then %do; %put NOTE: No plots found for &loopds..; %return; %end;

  data _null_;
    set &loopds;
    call symputx(cats('symL',_n_),symbol,'l');
    call symputx(cats('edtL',_n_),put(entry_date,yymmdd10.),'l');
    call symputx(cats('stL',_n_),status_label,'l');
  run;

  %do i=1 %to &nplots;
    %let this_sym=&&symL&i;
    %let this_edt=&&edtL&i;
    %let this_status=&&stL&i;
    %let this_title2=&this_sym | &this_status | EQI Score and Price Since Entry | Entry=&this_edt;
    ods pdf startpage=now;
    title1 "&titletext";
    title2 "&this_title2";
    proc sgplot data=work._plot_base_prep;
      where symbol="&this_sym" and entry_date=input("&this_edt",yymmdd10.);
      series x=date y=close_price / lineattrs=(thickness=2);
      series x=date y=eq_plot / y2axis lineattrs=(color=cxF28C28 pattern=shortdash thickness=2);
      scatter x=date y=entry_price_marker / markerattrs=(symbol=circlefilled size=8);
      scatter x=date y=status_price_marker / markerattrs=(symbol=trianglefilled size=8);
      scatter x=date y=entry_eq_marker / y2axis markerattrs=(symbol=circlefilled size=8 color=cxF28C28);
      scatter x=date y=status_eq_marker / y2axis markerattrs=(symbol=trianglefilled size=8 color=cxF28C28);
      xaxis fitpolicy=rotate;
      yaxis label="Price";
      y2axis min=-1 max=3 label="EQI Score";
    run;
  %end;
%mend;

%plot_loop(loopds=work._page1_loop, titletext=EQI Alert Lifecycle - Top 20 Current Seeded Alerts by Current Rank);
ods pdf close;
title;
ods listing;

/* =========================================================
   13) OUTPUT: CONVICTION QUADRANT JPEG
   ========================================================= */

ods listing close;
ods listing gpath="&BASEDIR";

ods graphics / reset
    width=2400px
    height=1600px
    imagename="EQI_conviction_quadrant_shaded_poly_v5_full_ranked_delta"
    imagefmt=jpeg
    noborder;

title1 h=22pt "Conviction Momentum Quadrant";
title2 h=14pt "Current Seeded Alerts | X = EQ Score Vol | Y = 1-Day Change in EQ Score Vol";

proc sgplot data=work.quad_canvas
    noautolegend
    dattrmap=work.all_attrmap;

  polygon x=poly_x y=poly_y id=poly_id /
    group=zone
    attrid=zonemap
    fill
    outline
    transparency=0.82;

  refline &x_mid / axis=x
    lineattrs=(color=cx7F8C8D pattern=shortdash thickness=2);

  refline &y_mid / axis=y
    lineattrs=(color=cx7F8C8D pattern=shortdash thickness=2);

  scatter x=x_halo y=y_halo /
    name='halo'
    markerattrs=(symbol=circlefilled size=24 color=cxFFFFFF)
    transparency=0.35;

  scatter x=x_score y=y_delta /
    name='main'
    group=status_group
    attrid=statusmap
    datalabel=plot_label
    markerattrs=(symbol=circlefilled size=16)
    datalabelattrs=(size=14 color=cx1F2D3A weight=bold);

  text x=quad_x y=quad_y text=quad_label /
    textattrs=(size=16 weight=bold color=cx444444);

  xaxis
    min=&x_lo
    max=&x_hi
    offsetmin=0
    offsetmax=0
    label="EQ Score Vol (Current)"
    valueattrs=(size=13)
    labelattrs=(size=16 weight=bold);

  yaxis
    min=&y_lo
    max=&y_hi
    offsetmin=0
    offsetmax=0
    label="EQ Score Vol Change (1 Day)"
    valueattrs=(size=13)
    labelattrs=(size=16 weight=bold);

  keylegend 'main' /
    location=inside
    position=topright
    across=1
    valueattrs=(size=14 weight=bold)
    title="";

run;

footnote1 j=l h=12pt "Marker label = Symbol (Current Rank)";
footnote2 j=r h=12pt "Data as of &MAX_FILE_DT";

title;
footnote;

ods listing close;
ods listing;


/* =========================================================
   14) OUTPUT: CONVICTION + TOP20 LIFECYCLE PDF
   ========================================================= */

ods listing close;

ods graphics / reset noborder;

ods pdf file="&BASEDIR./EQI_conviction_plus_top20_lifecycle.pdf"
    notoc
    startpage=now;

options orientation=landscape;

ods pdf startpage=now;

ods graphics / reset
    width=11in
    height=7.5in
    noborder;

/* Recompute fill extents with stronger overfill to eliminate visible gap */
data _null_;
  x_min = input(symget('x_min'), best32.);
  x_max = input(symget('x_max'), best32.);
  y_min = input(symget('y_min'), best32.);
  y_max = input(symget('y_max'), best32.);

  x_pad = (x_max - x_min) * 0.10;
  y_pad = (y_max - y_min) * 0.15;

  if x_pad <= 0 then x_pad = 0.25;
  if y_pad <= 0 then y_pad = 0.05;

  x_lo = x_min - x_pad;
  x_hi = x_max + x_pad;
  y_lo = y_min - y_pad;
  y_hi = y_max + y_pad;

  x_lo_fill = x_lo - 0.01;
  x_hi_fill = x_hi + 0.01;
  y_lo_fill = y_lo - 0.01;
  y_hi_fill = y_hi + 0.04;

  call symputx('x_lo', x_lo);
  call symputx('x_hi', x_hi);
  call symputx('y_lo', y_lo);
  call symputx('y_hi', y_hi);

  call symputx('x_lo_fill', x_lo_fill);
  call symputx('x_hi_fill', x_hi_fill);
  call symputx('y_lo_fill', y_lo_fill);
  call symputx('y_hi_fill', y_hi_fill);
run;

/* Rebuild polygons with overfill extents */
data work.quad_polys_page1;
  length status_group $24 zone $32 poly_id $8 quad_label $32 plot_label $60;

  x_lo      = input(symget('x_lo'), best32.);
  x_hi      = input(symget('x_hi'), best32.);
  y_lo      = input(symget('y_lo'), best32.);
  y_hi      = input(symget('y_hi'), best32.);
  x_lo_fill = input(symget('x_lo_fill'), best32.);
  x_hi_fill = input(symget('x_hi_fill'), best32.);
  y_lo_fill = input(symget('y_lo_fill'), best32.);
  y_hi_fill = input(symget('y_hi_fill'), best32.);
  x_mid     = input(symget('x_mid'), best32.);
  y_mid     = input(symget('y_mid'), best32.);

  x_score = .;
  y_delta = .;
  x_halo  = .;
  y_halo  = .;
  symbol = '';
  status_label = '';
  status_group = '';
  plot_label = '';
  rank_EQ = .;

  zone = 'Broken Zone';
  poly_id = 'BL';
  poly_x = x_lo_fill; poly_y = y_lo_fill; output;
  poly_x = x_mid;     poly_y = y_lo_fill; output;
  poly_x = x_mid;     poly_y = y_mid;     output;
  poly_x = x_lo_fill; poly_y = y_mid;     output;

  zone = 'Re-Evaluate Zone';
  poly_id = 'TL';
  poly_x = x_lo_fill; poly_y = y_mid;     output;
  poly_x = x_mid;     poly_y = y_mid;     output;
  poly_x = x_mid;     poly_y = y_hi_fill; output;
  poly_x = x_lo_fill; poly_y = y_hi_fill; output;

  zone = 'Active-Weakening Zone';
  poly_id = 'BR';
  poly_x = x_mid;     poly_y = y_lo_fill; output;
  poly_x = x_hi_fill; poly_y = y_lo_fill; output;
  poly_x = x_hi_fill; poly_y = y_mid;     output;
  poly_x = x_mid;     poly_y = y_mid;     output;

  zone = 'Active-Strong Zone';
  poly_id = 'TR';
  poly_x = x_mid;     poly_y = y_mid;     output;
  poly_x = x_hi_fill; poly_y = y_mid;     output;
  poly_x = x_hi_fill; poly_y = y_hi_fill; output;
  poly_x = x_mid;     poly_y = y_hi_fill; output;

  quad_x = .;
  quad_y = .;
  quad_label = '';
run;

/* Rebuild labels with cleaner placement */
data work.quad_labels_page1;
  length status_group $24 zone $32 poly_id $8 quad_label $32 plot_label $60;

  x_lo  = input(symget('x_lo'), best32.);
  x_hi  = input(symget('x_hi'), best32.);
  y_lo  = input(symget('y_lo'), best32.);
  y_hi  = input(symget('y_hi'), best32.);
  x_mid = input(symget('x_mid'), best32.);
  y_mid = input(symget('y_mid'), best32.);

  x_score = .;
  y_delta = .;
  x_halo = .;
  y_halo = .;
  poly_x = .;
  poly_y = .;
  symbol = '';
  status_label = '';
  status_group = '';
  plot_label = '';
  rank_EQ = .;
  zone = '';
  poly_id = '';

  quad_x = (x_lo + x_mid) / 2;
  quad_y = y_hi - (y_hi - y_mid) * 0.06;
  quad_label = 'Weak but Rising';
  output;

  quad_x = (x_mid + x_hi) / 2;
  quad_y = y_hi - (y_hi - y_mid) * 0.06;
  quad_label = 'Strong and Improving';
  output;

  quad_x = (x_lo + x_mid) / 2;
  quad_y = y_lo + (y_mid - y_lo) * 0.06;
  quad_label = 'Weak and Deteriorating';
  output;

  quad_x = (x_mid + x_hi) / 2;
  quad_y = y_lo + (y_mid - y_lo) * 0.06;
  quad_label = 'Strong but Fading';
  output;
run;

/* Canvas for page 1 only */
data work.quad_canvas_page1;
  set work.quad_polys_page1
      work.quad_points
      work.quad_labels_page1;
run;

title1 h=15pt "Conviction Momentum Quadrant";
title2 h=10pt "Current Seeded Alerts | X = EQ Score Vol | Y = 1-Day Change in EQ Score Vol";

proc sgplot data=work.quad_canvas_page1
    noautolegend
    dattrmap=work.all_attrmap;

  polygon x=poly_x y=poly_y id=poly_id /
    group=zone
    attrid=zonemap
    fill
    outline
    transparency=0.86;

  refline &x_mid / axis=x
    lineattrs=(color=cx7F8C8D pattern=shortdash thickness=1.5);

  refline &y_mid / axis=y
    lineattrs=(color=cx7F8C8D pattern=shortdash thickness=1.5);

  scatter x=x_halo y=y_halo /
    name='halo'
    markerattrs=(symbol=circlefilled size=16 color=cxFFFFFF)
    transparency=0.45;

  scatter x=x_score y=y_delta /
    name='main'
    group=status_group
    attrid=statusmap
    datalabel=plot_label
    markerattrs=(symbol=circlefilled size=11)
    datalabelattrs=(size=9 color=cx1F2D3A);

  text x=quad_x y=quad_y text=quad_label /
    textattrs=(size=9 color=cx444444);

  xaxis
    min=&x_lo
    max=&x_hi
    offsetmin=0
    offsetmax=0
    label="EQ Score Vol (Current)"
    valueattrs=(size=9)
    labelattrs=(size=11);

  yaxis
    min=&y_lo
    max=&y_hi
    offsetmin=0
    offsetmax=0
    label="EQ Score Vol Change (1 Day)"
    valueattrs=(size=9)
    labelattrs=(size=11);

  keylegend 'main' /
    location=inside
    position=topright
    across=1
    valueattrs=(size=8)
    title="";

run;

title;
footnote;

/* ---------- Remaining pages: Top 20 lifecycle plots ---------- */
options orientation=landscape;

%macro plot_loop_pdf(loopds=, titletext=);

  %local nplots i this_sym this_edt this_status this_title2;

  proc sql noprint;
    select count(*)
      into :nplots trimmed
    from &loopds;
  quit;

  %if %sysevalf(%superq(nplots)=, boolean) %then %let nplots = 0;

  %if &nplots = 0 %then %do;
    %put NOTE: No plots found for &loopds..;
    %return;
  %end;

  data _null_;
    set &loopds;
    call symputx(cats('symp', _n_), symbol, 'l');
    call symputx(cats('edtp', _n_), put(entry_date, yymmdd10.), 'l');
    call symputx(cats('stp', _n_), status_label, 'l');
  run;

  %do i = 1 %to &nplots;

    %let this_sym = &&symp&i;
    %let this_edt = &&edtp&i;
    %let this_status = &&stp&i;
    %let this_title2 = &this_sym | &this_status | EQI Score and Price Since Entry | Entry=&this_edt;

    ods pdf startpage=now;

    title1 h=16pt "&titletext";
    title2 h=11pt "&this_title2";

    proc sgplot data=work._plot_base_prep;
      where symbol = "&this_sym"
        and entry_date = input("&this_edt", yymmdd10.);

      series x=date y=close_price /
        lineattrs=(thickness=2);

      series x=date y=eq_plot / y2axis
        lineattrs=(color=cxF28C28 pattern=shortdash thickness=2);

      scatter x=date y=entry_price_marker /
        markerattrs=(symbol=circlefilled size=8);

      scatter x=date y=status_price_marker /
        markerattrs=(symbol=trianglefilled size=8);

      scatter x=date y=entry_eq_marker / y2axis
        markerattrs=(symbol=circlefilled size=8 color=cxF28C28);

      scatter x=date y=status_eq_marker / y2axis
        markerattrs=(symbol=trianglefilled size=8 color=cxF28C28);

      xaxis fitpolicy=rotate;
      yaxis label="Price";
      y2axis min=-1 max=3 label="EQI Score";

    run;

    title;

  %end;

%mend;

%plot_loop_pdf(
  loopds=work._page1_loop,
  titletext=EQI Alert Lifecycle - Top 20 Current Seeded Alerts by Current Rank
);

ods pdf close;
title;
footnote;
ods listing;

/* =========================================================
   15) OUTPUT: EQMI BAR CHARTS
   ========================================================= */
/* Overall EQMI bars */
data work.eqmi_plot;
  set EQI.eqmi_daily;
  length regime $24;
  ema=EQMI_EMA3;
  if ema < 35 then regime='0-35 Bearish';
  else if ema < 50 then regime='35-50 Neutral';
  else if ema < 65 then regime='50-65 Bullish';
  else regime='65-100 Strong risk-on';
run;

data work.eqmi_attrmap;
  length id $8 value $24 fillcolor $12;
  id='REG';
  value='0-35 Bearish'; fillcolor='CXD9534F'; output;
  value='35-50 Neutral'; fillcolor='CXF0AD4E'; output;
  value='50-65 Bullish'; fillcolor='CX5CB85C'; output;
  value='65-100 Strong risk-on'; fillcolor='CX2B8CBE'; output;
run;

ods listing close;
ods graphics / reset=all imagename="EQMI_EMA3_last60_bars" imagefmt=png width=1250px height=720px border=off noborder;
ods html path="&BASEDIR" (url=none) file="eqmi_bars.html" style=htmlblue;

proc sgplot data=work.eqmi_plot dattrmap=work.eqmi_attrmap noautolegend;
  styleattrs backcolor=cxF7F7F7 wallcolor=cxF7F7F7
    datacontrastcolors=(cxd9534f cxf0ad4e cx5cb85c cx2b8cbe)
    datacolors=(cxd9534f cxf0ad4e cx5cb85c cx2b8cbe);
  vbarparm category=date response=ema / group=regime attrid=REG groupdisplay=cluster outlineattrs=(thickness=0);
  xaxis display=(nolabel) grid fitpolicy=thin offsetmin=0.01 offsetmax=0.01
        gridattrs=(color=cxE6E6E6 thickness=1)
        valueattrs=(family="Segoe UI" size=11pt color=cx5A5A5A);
  yaxis label="EQMI (EMA3)" grid min=0 max=80 values=(0 20 40 60 80) offsetmin=0 offsetmax=0.02
        gridattrs=(color=cxE6E6E6 thickness=1)
        labelattrs=(family="Segoe UI Semibold" size=13pt color=cx1F2C3C)
        valueattrs=(family="Segoe UI" size=11pt color=cx5A5A5A);
run;

ods html close;
ods listing;

/* Sector EQMI bars */
data work.eqmi_sector_plot;
  set work.eqmi_sector_plot;
  length regime $24;
  ema=EQMI_EMA3;
  if ema < 35 then regime='0-35 Bearish';
  else if ema < 50 then regime='35-50 Neutral';
  else if ema < 65 then regime='50-65 Bullish';
  else regime='65-100 Strong risk-on';
  format date date9.;
run;

ods listing close;
ods graphics / reset=all imagename="EQMI_EMA3_by_sector_bars_DAILY"
              imagefmt=png width=1800px height=1000px antialiasmax=20000;
ods html path="&BASEDIR" (url=none) file="eqmi_sector_bars_daily.html" style=htmlblue;
ods results on;

proc sgpanel data=work.eqmi_sector_plot dattrmap=work.eqmi_attrmap;
  panelby sector / columns=4 novarname uniscale=row headerattrs=(size=11 weight=bold) spacing=6;
  vbarparm category=date response=ema / group=regime attrid=REG barwidth=0.90 outlineattrs=(thickness=0);
  colaxis display=(nolabel) fitpolicy=thin valueattrs=(size=9) valuesrotate=vertical grid gridattrs=(color=cxE6E9ED thickness=1);
  rowaxis label="EQMI (EMA3)" min=0 max=80 labelattrs=(size=12 weight=bold) valueattrs=(size=9) grid gridattrs=(color=cxE6E9ED thickness=1);
  refline 35 50 65 / axis=y lineattrs=(pattern=shortdash thickness=1 color=cxC9CED6) transparency=0.35;
  keylegend / title="Regimes" position=bottom across=4 titleattrs=(size=12 weight=bold) valueattrs=(size=10);
  title "EQMI (EMA3) by Sector - Regime-colored DAILY bars (Top &EQMI_SECTOR_TOPK sectors)";
run;

ods html close;
ods listing;
title;

/* Simple EQMI run HTML summary */
ods html path="&BASEDIR" (url=none) file="eqmi_run.html" style=htmlblue;
title "EQMI Daily - last 10 sessions";
proc print data=EQI.eqmi_daily(obs=10) noobs;
  var date n p_long p_accel EQMI EQMI_EMA3;
run;
title;
ods html close;

/* =========================================================
   16) QA / FINAL OUTPUT SUMMARY
   ========================================================= */
options orientation=portrait;
title "EQI Master Pipeline Output Summary";
proc sql;
  select "EQI.stock_master_raw" as table_name length=40, count(*) as n_rows from EQI.stock_master_raw
  union all
  select "EQI.stock_master_daily", count(*) from EQI.stock_master_daily
  union all
  select "EQI.daily_ranked_universe", count(*) from EQI.daily_ranked_universe
  union all
  select "EQI.eq_topN_events_vol", count(*) from EQI.eq_topN_events_vol
  union all
  select "EQI.vol_top50_today", count(*) from EQI.vol_top50_today
  union all
  select "EQI.signal_lifecycle_daily", count(*) from EQI.signal_lifecycle_daily
  union all
  select "EQI.eqmi_daily", count(*) from EQI.eqmi_daily
  union all
  select "EQI.eqmi_sector_daily", count(*) from EQI.eqmi_sector_daily;
quit;
title;

data _null_;
  put "NOTE: MASTER DATABASE TABLE: &BASEDIR./stock_master_daily.sas7bdat via libref EQI.";
  put "NOTE: PDF: &BASEDIR./EQI_FOCUS_PLUS_90D_TOP50.pdf";
  put "NOTE: PDF: &BASEDIR./EQI_alert_lifecycle_panels.pdf";
  put "NOTE: PDF: &BASEDIR./EQI_conviction_plus_top20_lifecycle.pdf";
  put "NOTE: JPEG: &BASEDIR./EQI_conviction_quadrant_shaded_poly_v5_full_ranked_delta.jpeg";
  put "NOTE: CSV: &BASEDIR./vol_top50_today.csv";
  put "NOTE: CSV: &BASEDIR./EQMI_daily_last60.csv";
  put "NOTE: PNG: &BASEDIR./EQMI_EMA3_last60_bars.png";
  put "NOTE: PNG: &BASEDIR./EQMI_EMA3_by_sector_bars_DAILY.png";
run;
