#!/usr/bin/env bash
# File watcher that monitors the results directory and automatically
# generates heatmaps when new result files appear
# Usage: ./watch_and_generate_heatmap.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
RESULTS_DIR="${RESULTS_DIR:-$(cd "${PROJECT_ROOT}/../.." && pwd)/results}"
WATCH_FILE="${SCRIPT_DIR}/.heatmap_watch_state"
LOG_DIR="${LOG_DIR:-${PROJECT_ROOT}/.state/logs}"
mkdir -p "$LOG_DIR"

LOG_FILE="${LOG_DIR}/heatmap_watcher_$(date +%Y%m%d).log"

echo "=== Heatmap File Watcher ===" | tee -a "$LOG_FILE"
echo "Started at: $(date)" | tee -a "$LOG_FILE"
echo "Watching directory: $RESULTS_DIR" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Load previously processed dates
if [[ -f "$WATCH_FILE" ]]; then
    source "$WATCH_FILE"
else
    declare -A PROCESSED_DATES
fi

# Function to check and process new files
check_for_new_files() {
    local found_new=0
    
    # Find all unique dates from result files
    for file in "${RESULTS_DIR}"/results_*_xtest_*.csv; do
        [[ -e "$file" ]] || continue
        
        # Extract date from filename (YYYY-MM-DD)
        if [[ "$(basename "$file")" =~ results_(stock|etf)_xtest_([0-9]{4}-[0-9]{2}-[0-9]{2})\.csv ]]; then
            local date="${BASH_REMATCH[2]}"
            
            # Check if we've already processed this date
            if [[ -z "${PROCESSED_DATES[$date]:-}" ]]; then
                # Check if both stock and ETF files exist for this date
                local stock_file="${RESULTS_DIR}/results_stock_xtest_${date}.csv"
                local etf_file="${RESULTS_DIR}/results_etf_xtest_${date}.csv"
                
                if [[ -f "$stock_file" ]] && [[ -f "$etf_file" ]]; then
                    # Skip processing if either file is empty or contains no data rows.
                    # Treat header-only files (<= 1 line) as having no data rows.
                    stock_lines=$(wc -l < "$stock_file" 2>/dev/null || echo 0)
                    etf_lines=$(wc -l < "$etf_file" 2>/dev/null || echo 0)

                    if [[ ${stock_lines:-0} -le 1 ]] || [[ ${etf_lines:-0} -le 1 ]]; then
                        echo "[$(date +%H:%M:%S)] Skipping $date: one or both files have no data rows (stock:$stock_lines etf:$etf_lines)" | tee -a "$LOG_FILE"
                        # Do not mark as processed; wait for real data to appear.
                        continue
                    fi

                    echo "[$(date +%H:%M:%S)] Found new complete dataset for: $date" | tee -a "$LOG_FILE"

                    # Process this date
                    echo "[$(date +%H:%M:%S)] Generating heatmaps for $date..." | tee -a "$LOG_FILE"
                    if "${SCRIPT_DIR}/post_batch_heatmap.sh" "$date" >> "$LOG_FILE" 2>&1; then
                        echo "[$(date +%H:%M:%S)] ✓ Successfully generated heatmaps for $date" | tee -a "$LOG_FILE"
                        PROCESSED_DATES[$date]=1
                        found_new=1
                    else
                        echo "[$(date +%H:%M:%S)] ✗ Failed to generate heatmaps for $date" | tee -a "$LOG_FILE"
                    fi
                    echo "" | tee -a "$LOG_FILE"
                fi
            fi
        fi
    done
    
    # Save state if we found new files
    if [[ $found_new -eq 1 ]]; then
        echo "# Processed dates - DO NOT EDIT MANUALLY" > "$WATCH_FILE"
        echo "declare -A PROCESSED_DATES" >> "$WATCH_FILE"
        for date in "${!PROCESSED_DATES[@]}"; do
            echo "PROCESSED_DATES[$date]=1" >> "$WATCH_FILE"
        done
    fi
}

# Initial check
echo "Performing initial scan..." | tee -a "$LOG_FILE"
check_for_new_files

# If running in watch mode (with --watch flag)
if [[ "${1:-}" == "--watch" ]]; then
    echo "" | tee -a "$LOG_FILE"
    echo "Entering watch mode (checking every 60 seconds)..." | tee -a "$LOG_FILE"
    echo "Press Ctrl+C to stop" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    while true; do
        sleep 60
        check_for_new_files
    done
else
    echo "" | tee -a "$LOG_FILE"
    echo "One-time scan complete. Use --watch flag for continuous monitoring." | tee -a "$LOG_FILE"
fi

exit 0
