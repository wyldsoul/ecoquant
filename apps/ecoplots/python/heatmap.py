# eqi_dashboard.py
# Generates three dual heatmaps for a given day (current & Δ vs a prior day)
# Requirements: pandas, numpy, matplotlib, pillow

import os, re
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from datetime import datetime
from typing import Optional
from PIL import Image, ImageDraw, ImageFont

# ---------- CONFIG ----------
DATA_DIR = os.environ.get("EQI_RESULTS_DIR", "/eqi/results")                    # input directory for CSV files
OUTPUT_DIR = os.environ.get("EQI_HEATMAP_OUTPUT_DIR", "/eqi/exports/heatmap")   # output directory for PNG files
TIMEFRAMES = ["x1","x2","x3","x4","x5","x9","x14","x21","x30"]
TITLE_PREFIX = "EcoQuant Insight — Power Rankings"
SECTOR_EXCLUDE_KEYS = {"UNKNOWN","NAN","MISC","MISCELLANEOUS","", None}
STOCK_MIN_D30_VOL = 1_000_000

ETF_DESC = {
    "URTY": "Small Caps — 3× Bull (Russell 2000)",
    "CURE": "Healthcare — 3× Bull",
    "MIDU": "Mid Caps — 3× Bull (S&P 400)",
    "AGQ":  "Silver — 2× Bull",
    "XBI":  "Biotech (SPDR)",
    "LABU": "Biotech — 3× Bull",
    "TNA":  "Small Caps — 3× Bull",
    "UWM":  "Small Caps — 2× Bull",
    "SOXL": "Semiconductors — 3× Bull",
    "SOXS": "Semiconductors — 3× Bear",
    "RETL": "Retail — 3× Bull",
    "SQQQ": "Nasdaq-100 — 3× Bear",
    "TQQQ": "Nasdaq-100 — 3× Bull",
    "SPXL": "S&P 500 — 3× Bull",
    "SPXS": "S&P 500 — 3× Bear",
    "UDOW": "Dow 30 — 3× Bull",
    "TLT":  "U.S. Treasuries 20+ Yr",
    "UGL":  "Gold — 2× Bull",
    "DZZ":  "Gold — 2× Bear (ETN)",
    "IWM":  "Russell 2000",
    "TYD":  "7–10Y Treasuries — 3× Bull",
}

plt.rcParams.update({
    "figure.dpi": 200,
    "axes.spines.top": False,
    "axes.spines.right": False,
    "font.size": 12,
    "axes.labelsize": 14,
    "axes.titlesize": 24,
    "xtick.labelsize": 14,
    "ytick.labelsize": 12,
})

# ---------- UTILS ----------
def list_dates(prefix):
    pat = re.compile(rf"{re.escape(prefix)}_(\d{{4}}-\d{{2}}-\d{{2}})\.csv$")
    dates = []
    for f in os.listdir(DATA_DIR):
        m = pat.match(f)
        if m:
            dates.append(m.group(1))
    return sorted(set(dates))

def prev_date(cur_date, dates, prefix="results_stock_xtest"):
    """Find the most recent prior date with non-empty CSV files."""
    d_cur = datetime.strptime(cur_date, "%Y-%m-%d").date()
    prior = [d for d in dates if datetime.strptime(d, "%Y-%m-%d").date() < d_cur]
    
    # Try dates in reverse order (most recent first) and return first non-empty
    for candidate in reversed(prior):
        stock_path = os.path.join(DATA_DIR, f"results_stock_xtest_{candidate}.csv")
        etf_path = os.path.join(DATA_DIR, f"results_etf_xtest_{candidate}.csv")
        try:
            # Check if both files exist and have content
            if os.path.exists(stock_path) and os.path.exists(etf_path):
                stock_df = pd.read_csv(stock_path, low_memory=False, nrows=1)
                etf_df = pd.read_csv(etf_path, low_memory=False, nrows=1)
                if not stock_df.empty and not etf_df.empty:
                    return candidate
        except:
            continue
    
    return None

def read_csv_sure(path):
    df = pd.read_csv(path, low_memory=False)
    if df.empty:
        raise ValueError(f"{os.path.basename(path)} has 0 rows")
    return df

def std_key(x):
    if pd.isna(x): return None
    return str(x).strip().upper()

def find_col(df, names):
    lower = {c.lower(): c for c in df.columns}
    for n in names:
        if n.lower() in lower:
            return lower[n.lower()]
    # soft match
    for c in df.columns:
        lc = c.lower()
        for n in names:
            if n.lower() in lc:
                return c
    return None

def find_tf_col(df, tf):
    candidates = [f"{tf}slope", f"{tf}_slope", f"{tf} slope", tf]
    lower = {c.lower(): c for c in df.columns}
    for p in candidates:
        if p.lower() in lower: return lower[p.lower()]
    for c in df.columns:
        lc = c.lower()
        if tf in lc and "slope" in lc:
            return c
    return None

def sym_limits(A):
    if A.size == 0: return (-1, 1)
    m = float(np.nanmax(np.abs(A)))
    if not np.isfinite(m) or m == 0: m = 1.0
    return (-m, m)

def imsave_with_brand_header(png_body_path, out_path, header_text, date_text, header_px=110):
    img = Image.open(png_body_path).convert("RGBA")
    W = img.width
    banner = Image.new("RGBA", (W, header_px), (0, 0, 0, 0))
    d = ImageDraw.Draw(banner)
    # EQI gradient from aqua to green
    aqua = (100, 208, 228); green = (0, 181, 81)
    for y in range(header_px):
        t = y / float(header_px)
        r = int(aqua[0] + (green[0] - aqua[0]) * t)
        g = int(aqua[1] + (green[1] - aqua[1]) * t)
        b = int(aqua[2] + (green[2] - aqua[2]) * t)
        d.line([(0, y), (W, y)], fill=(r, g, b))
    try:
        f_lg = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", int(header_px*0.46))
        f_sm = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", int(header_px*0.28))
    except:
        f_lg = ImageFont.load_default(); f_sm = ImageFont.load_default()
    d.text((int(W*0.03), int(header_px*0.20)), header_text, fill=(255,255,255), font=f_lg)
    bbox = d.textbbox((0, 0), date_text, font=f_sm)
    tw = bbox[2] - bbox[0]
    d.text((W - tw - int(W*0.03), int(header_px*0.34)), date_text, fill=(255,255,255), font=f_sm)

    canvas = Image.new("RGBA", (W, header_px + img.height), (255,255,255,255))
    canvas.paste(banner, (0,0))
    canvas.paste(img, (0, header_px))
    canvas.convert("RGB").save(out_path, "PNG")

def render_heatmap(A, rows, cols, title, out_path, vmin=None, vmax=None):
    # Increased figure size and adjusted spacing for better readability
    fig, ax = plt.subplots(figsize=(16, max(8, 0.65*len(rows)+5)))
    im = ax.imshow(A, aspect='auto', interpolation='nearest',
                   vmin=vmin, vmax=vmax, cmap='RdYlGn')
    
    # Set ticks and labels with larger fonts
    ax.set_xticks(np.arange(len(cols)))
    ax.set_xticklabels(cols, rotation=45, ha='right', fontsize=14)
    ax.set_yticks(np.arange(len(rows)))
    ax.set_yticklabels(rows, fontsize=12)
    ax.set_title(title, fontsize=24, pad=20)
    
    # Annotate cell values with larger, more readable font
    for i in range(A.shape[0]):
        for j in range(A.shape[1]):
            val = A[i, j]
            if np.isfinite(val):
                ax.text(j, i, f"{val:.3f}", ha='center', va='center', 
                       fontsize=11, color='black', weight='bold')
    
    fig.colorbar(im, ax=ax, fraction=0.046, pad=0.04)
    plt.tight_layout()
    fig.savefig(out_path, bbox_inches='tight', dpi=200)
    plt.close(fig)

def stack_vertical(png_top, png_bottom, out_path, gap=10):
    top = Image.open(png_top).convert("RGB")
    bot = Image.open(png_bottom).convert("RGB")
    W = max(top.width, bot.width)
    if top.width != W:
        top = top.resize((W, int(top.height*W/top.width)))
    if bot.width != W:
        bot = bot.resize((W, int(bot.height*W/bot.width)))
    H = top.height + gap + bot.height
    canvas = Image.new("RGB", (W, H), "white")
    canvas.paste(top, (0, 0))
    canvas.paste(bot, (0, top.height + gap))
    canvas.save(out_path, "PNG")

# ---------- CORE PIPELINE ----------
def load_tf_block(df, tf_list):
    tf_cols = []
    df2 = df.copy()
    for tf in tf_list:
        col = find_tf_col(df2, tf)
        if col is not None:
            df2[f"__{tf}__"] = pd.to_numeric(df2[col], errors="coerce")
            tf_cols.append(f"__{tf}__")
    return df2, tf_cols

def sectors_dual(stock_cur, stock_prev, cur_date, prev_date):
    sector_col = find_col(stock_cur, ["sector","gics_sector","industry_sector","industry sector"]) or "sector"
    sc, sp = stock_cur.copy(), stock_prev.copy()
    sc["__SECKEY__"] = sc[sector_col].map(std_key)
    sp["__SECKEY__"] = sp[sector_col].map(std_key)

    sc = sc[~sc["__SECKEY__"].isin(SECTOR_EXCLUDE_KEYS)]
    sp = sp[~sp["__SECKEY__"].isin(SECTOR_EXCLUDE_KEYS)]

    sc, tf_cols_cur = load_tf_block(sc, TIMEFRAMES)
    sp, tf_cols_prev = load_tf_block(sp, TIMEFRAMES)
    use = [t for t in TIMEFRAMES if f"__{t}__" in tf_cols_cur and f"__{t}__" in tf_cols_prev]

    cur_sec = sc.groupby("__SECKEY__")[[f"__{t}__" for t in use]].mean()
    pre_sec = sp.groupby("__SECKEY__")[[f"__{t}__" for t in use]].mean()
    idx = sorted(set(cur_sec.index).intersection(pre_sec.index))
    cur_sec = cur_sec.loc[idx]; pre_sec = pre_sec.loc[idx]
    delta = cur_sec - pre_sec

    rank_keys = [t for t in ["x14","x21","x30"] if t in use] or use
    rank = cur_sec[[f"__{t}__" for t in rank_keys]].mean(axis=1)
    top12 = rank.sort_values(ascending=False).head(12).index.tolist()

    name_map = (sc.dropna(subset=["__SECKEY__"])
                  .drop_duplicates("__SECKEY__")
                  .set_index("__SECKEY__")[sector_col]
                  .to_dict())
    row_labels = [f"{i:2d}. {name_map.get(k,k)}" for i,k in enumerate(top12, start=1)]
    col_labels = use

    cur_mat = cur_sec.loc[top12, [f"__{t}__" for t in use]].values
    del_mat = delta.loc[top12, [f"__{t}__" for t in use]].values
    vmin_c, vmax_c = sym_limits(cur_mat)
    vmin_d, vmax_d = sym_limits(del_mat)

    date_folder = cur_date.replace('-', '')
    out_dir = os.path.join(OUTPUT_DIR, date_folder)
    
    # Generate intermediate PNGs (commented out to save space - only keep branded final)
    # png_cur = os.path.join(out_dir, f"sectors_current_{cur_date}_vs_{prev_date}.png")
    # png_del = os.path.join(out_dir, f"sectors_delta_{cur_date}_vs_{prev_date}.png")
    # png_dual = os.path.join(out_dir, f"sectors_dual_{cur_date}_vs_{prev_date}.png")
    # render_heatmap(cur_mat, row_labels, col_labels, f"Sectors — Current Slopes — {cur_date}", png_cur, vmin=vmin_c, vmax=vmax_c)
    # render_heatmap(del_mat, row_labels, col_labels, f"Sectors — Δ vs {prev_date}", png_del, vmin=vmin_d, vmax=vmax_d)
    # stack_vertical(png_cur, png_del, png_dual)
    
    # Generate directly to temp files for branding
    import tempfile
    with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as tmp_cur, \
         tempfile.NamedTemporaryFile(suffix='.png', delete=False) as tmp_del, \
         tempfile.NamedTemporaryFile(suffix='.png', delete=False) as tmp_dual:
        png_cur, png_del, png_dual = tmp_cur.name, tmp_del.name, tmp_dual.name
    
    render_heatmap(cur_mat, row_labels, col_labels, f"Sectors — Current Slopes — {cur_date}", png_cur, vmin=vmin_c, vmax=vmax_c)
    render_heatmap(del_mat, row_labels, col_labels, f"Sectors — Δ vs {prev_date}", png_del, vmin=vmin_d, vmax=vmax_d)
    stack_vertical(png_cur, png_del, png_dual)

    final = os.path.join(out_dir, f"sectors_dual_branded_{cur_date}_vs_{prev_date}.png")
    imsave_with_brand_header(png_dual, final, TITLE_PREFIX, f"{cur_date} vs {prev_date}")
    
    # Clean up temp files
    os.unlink(png_cur)
    os.unlink(png_del)
    os.unlink(png_dual)
    return final

def top16_stocks_dual(stock_cur, stock_prev, etf_cur, cur_date, prev_date):
    sym_col = find_col(stock_cur, ["symbol","ticker","sid"]) or stock_cur.columns[0]
    vol_col = find_col(stock_cur, ["D30_volume","d30_volume","D30Volume","d30vol","d30_vol","30d_volume","volume30d","vol30d"])
    etf_sym_col = find_col(etf_cur, ["symbol","ticker","sid","etf"]) if etf_cur is not None and not etf_cur.empty else None
    etf_syms = set(etf_cur[etf_sym_col].astype(str).str.upper()) if etf_sym_col else set()

    sc, sp = stock_cur.copy(), stock_prev.copy()
    sc["__SYMKEY__"] = sc[sym_col].map(std_key)
    sp["__SYMKEY__"] = sp[sym_col].map(std_key)

    # D30 volume filter & ETF exclusion
    if vol_col and vol_col in sc.columns:
        sc = sc[pd.to_numeric(sc[vol_col], errors='coerce') >= STOCK_MIN_D30_VOL]
    sc = sc[~sc["__SYMKEY__"].isin(etf_syms)]

    sc, tf_cols_cur = load_tf_block(sc, TIMEFRAMES)
    sp, tf_cols_prev = load_tf_block(sp, TIMEFRAMES)
    use = [t for t in TIMEFRAMES if f"__{t}__" in tf_cols_cur and f"__{t}__" in tf_cols_prev]

    cur_st = sc.groupby("__SYMKEY__")[[f"__{t}__" for t in use]].mean()
    pre_st = sp.groupby("__SYMKEY__")[[f"__{t}__" for t in use]].mean()
    idx = sorted(set(cur_st.index).intersection(pre_st.index))
    cur_st = cur_st.loc[idx]; pre_st = pre_st.loc[idx]
    delta = cur_st - pre_st

    rank_keys = [t for t in ["x14","x21","x30"] if t in use] or use
    rank = cur_st[[f"__{t}__" for t in rank_keys]].mean(axis=1)
    top16 = rank.sort_values(ascending=False).head(16).index.tolist()

    label_map = (sc.dropna(subset=["__SYMKEY__"])
                  .drop_duplicates("__SYMKEY__")
                  .set_index("__SYMKEY__")[sym_col]
                  .to_dict())
    sector_col = find_col(sc, ["sector","gics_sector","industry_sector","industry sector"])
    sector_map = (sc.dropna(subset=["__SYMKEY__"]).drop_duplicates("__SYMKEY__")
                    .set_index("__SYMKEY__")[sector_col].to_dict()) if sector_col in sc.columns else {}
    row_labels = [f"{label_map.get(k,k)} ({sector_map.get(k,'Unknown')})" for k in top16]
    col_labels = use

    cur_mat = cur_st.loc[top16, [f"__{t}__" for t in use]].values
    del_mat = delta.loc[top16, [f"__{t}__" for t in use]].values
    vmin_c, vmax_c = sym_limits(cur_mat)
    vmin_d, vmax_d = sym_limits(del_mat)

    date_folder = cur_date.replace('-', '')
    out_dir = os.path.join(OUTPUT_DIR, date_folder)
    
    # Generate intermediate PNGs (commented out to save space - only keep branded final)
    # png_cur = os.path.join(out_dir, f"stocks_top16_current_{cur_date}_vs_{prev_date}.png")
    # png_del = os.path.join(out_dir, f"stocks_top16_delta_{cur_date}_vs_{prev_date}.png")
    # png_dual = os.path.join(out_dir, f"stocks_top16_dual_{cur_date}_vs_{prev_date}.png")
    # render_heatmap(cur_mat, row_labels, col_labels, f"Top 16 Stocks — Current Slopes — {cur_date}", png_cur, vmin=vmin_c, vmax=vmax_c)
    # render_heatmap(del_mat, row_labels, col_labels, f"Top 16 Stocks — Δ vs {prev_date}", png_del, vmin=vmin_d, vmax=vmax_d)
    # stack_vertical(png_cur, png_del, png_dual)
    
    # Generate directly to temp files for branding
    import tempfile
    with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as tmp_cur, \
         tempfile.NamedTemporaryFile(suffix='.png', delete=False) as tmp_del, \
         tempfile.NamedTemporaryFile(suffix='.png', delete=False) as tmp_dual:
        png_cur, png_del, png_dual = tmp_cur.name, tmp_del.name, tmp_dual.name
    
    render_heatmap(cur_mat, row_labels, col_labels, f"Top 16 Stocks — Current Slopes — {cur_date}", png_cur, vmin=vmin_c, vmax=vmax_c)
    render_heatmap(del_mat, row_labels, col_labels, f"Top 16 Stocks — Δ vs {prev_date}", png_del, vmin=vmin_d, vmax=vmax_d)
    stack_vertical(png_cur, png_del, png_dual)

    final = os.path.join(out_dir, f"stocks_top16_dual_branded_{cur_date}_vs_{prev_date}.png")
    imsave_with_brand_header(png_dual, final, TITLE_PREFIX, f"{cur_date} vs {prev_date}")
    
    # Clean up temp files
    os.unlink(png_cur)
    os.unlink(png_del)
    os.unlink(png_dual)
    return final

def top16_etfs_dual(etf_cur, etf_prev, cur_date, prev_date):
    sym_e = find_col(etf_cur, ["symbol","ticker","sid","etf"]) or etf_cur.columns[0]
    vol_e = find_col(etf_cur, ["D30_volume","d30_volume","D30Volume","d30vol","d30_vol","30d_volume","volume30d","vol30d"])

    ec, ep = etf_cur.copy(), etf_prev.copy()
    ec["__SYMKEY__"] = ec[sym_e].map(std_key)
    ep["__SYMKEY__"] = ep[sym_e].map(std_key)

    if vol_e and vol_e in ec.columns:
        ec = ec[pd.to_numeric(ec[vol_e], errors='coerce') >= STOCK_MIN_D30_VOL]

    ec, tf_cols_cur = load_tf_block(ec, TIMEFRAMES)
    ep, tf_cols_prev = load_tf_block(ep, TIMEFRAMES)
    use = [t for t in TIMEFRAMES if f"__{t}__" in tf_cols_cur and f"__{t}__" in tf_cols_prev]

    cur_e = ec.groupby("__SYMKEY__")[[f"__{t}__" for t in use]].mean()
    pre_e = ep.groupby("__SYMKEY__")[[f"__{t}__" for t in use]].mean()
    idx = sorted(set(cur_e.index).intersection(pre_e.index))
    cur_e = cur_e.loc[idx]; pre_e = pre_e.loc[idx]
    delta = cur_e - pre_e

    rank_keys = [t for t in ["x14","x21","x30"] if t in use] or use
    rank = cur_e[[f"__{t}__" for t in rank_keys]].mean(axis=1)
    top16 = rank.sort_values(ascending=False).head(16).index.tolist()

    name_map_e = (ec.dropna(subset=["__SYMKEY__"])
                    .drop_duplicates("__SYMKEY__")
                    .set_index("__SYMKEY__")[sym_e].to_dict())
    row_labels = [f"{name_map_e.get(k,k)} — {ETF_DESC.get(name_map_e.get(k,k), 'ETF')}" for k in top16]
    col_labels = use

    # Use the correctly aggregated current ETF dataframe (cur_e)
    cur_mat = cur_e.loc[top16, [f"__{t}__" for t in use]].values
    del_mat = delta.loc[top16, [f"__{t}__" for t in use]].values
    vmin_c, vmax_c = sym_limits(cur_mat)
    vmin_d, vmax_d = sym_limits(del_mat)

    date_folder = cur_date.replace('-', '')
    out_dir = os.path.join(OUTPUT_DIR, date_folder)
    
    # Generate intermediate PNGs (commented out to save space - only keep branded final)
    # png_cur = os.path.join(out_dir, f"etf_top16_current_{cur_date}_vs_{prev_date}.png")
    # png_del = os.path.join(out_dir, f"etf_top16_delta_{cur_date}_vs_{prev_date}.png")
    # png_dual = os.path.join(out_dir, f"etf_top16_dual_{cur_date}_vs_{prev_date}.png")
    # render_heatmap(cur_mat, row_labels, col_labels, f"Top 16 ETFs — Current Slopes — {cur_date}", png_cur, vmin=vmin_c, vmax=vmax_c)
    # render_heatmap(del_mat, row_labels, col_labels, f"Top 16 ETFs — Δ vs {prev_date}", png_del, vmin=vmin_d, vmax=vmax_d)
    # stack_vertical(png_cur, png_del, png_dual)
    
    # Generate directly to temp files for branding
    import tempfile
    with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as tmp_cur, \
         tempfile.NamedTemporaryFile(suffix='.png', delete=False) as tmp_del, \
         tempfile.NamedTemporaryFile(suffix='.png', delete=False) as tmp_dual:
        png_cur, png_del, png_dual = tmp_cur.name, tmp_del.name, tmp_dual.name
    
    render_heatmap(cur_mat, row_labels, col_labels, f"Top 16 ETFs — Current Slopes — {cur_date}", png_cur, vmin=vmin_c, vmax=vmax_c)
    render_heatmap(del_mat, row_labels, col_labels, f"Top 16 ETFs — Δ vs {prev_date}", png_del, vmin=vmin_d, vmax=vmax_d)
    stack_vertical(png_cur, png_del, png_dual)

    final = os.path.join(out_dir, f"etf_top16_dual_branded_{cur_date}_vs_{prev_date}.png")
    imsave_with_brand_header(png_dual, final, TITLE_PREFIX, f"{cur_date} vs {prev_date}")
    
    # Clean up temp files
    os.unlink(png_cur)
    os.unlink(png_del)
    os.unlink(png_dual)
    
    return final

def run_dashboard(cur_date: str, prev_date_arg: Optional[str] = None):
    """
    cur_date: 'YYYY-MM-DD' for the current day
    prev_date_arg: 'YYYY-MM-DD' for the comparison; if None, auto-pick latest prior file
    Returns dict of output PNG paths.
    """
    # Ensure output directory for this date exists
    date_folder = cur_date.replace('-', '')
    out_dir = os.path.join(OUTPUT_DIR, date_folder)
    os.makedirs(out_dir, exist_ok=True)
    
    stock_path_cur = os.path.join(DATA_DIR, f"results_stock_xtest_{cur_date}.csv")
    etf_path_cur   = os.path.join(DATA_DIR, f"results_etf_xtest_{cur_date}.csv")
    stock_dates = list_dates("results_stock_xtest")
    etf_dates   = list_dates("results_etf_xtest")

    # choose previous automatically if not provided
    if prev_date_arg is None:
        prev_date_arg = prev_date(cur_date, stock_dates) or prev_date(cur_date, etf_dates) or cur_date

    # load CSVs
    s_cur = read_csv_sure(stock_path_cur)
    e_cur = read_csv_sure(etf_path_cur)
    s_prev = read_csv_sure(os.path.join(DATA_DIR, f"results_stock_xtest_{prev_date_arg}.csv"))
    e_prev = read_csv_sure(os.path.join(DATA_DIR, f"results_etf_xtest_{prev_date_arg}.csv"))

    # generate
    sectors_png = sectors_dual(s_cur, s_prev, cur_date, prev_date_arg)
    stocks_png  = top16_stocks_dual(s_cur, s_prev, e_cur, cur_date, prev_date_arg)
    etfs_png    = top16_etfs_dual(e_cur, e_prev, cur_date, prev_date_arg)

    return {
        "sectors_dual": sectors_png,
        "stocks_top16_dual": stocks_png,
        "etf_top16_dual": etfs_png,
    }

# ---------- simple CLI ----------
if __name__ == "__main__":
    # Example: run for 2025-11-19 (auto-detect previous date)
    outputs = run_dashboard(cur_date="2025-11-19", prev_date_arg=None)
    for k, v in outputs.items():
        print(k, "->", v)
