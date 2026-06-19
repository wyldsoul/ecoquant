#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
STATE_DIR="${PROJECT_ROOT}/.state"
COMPOSE_CMD="${COMPOSE_CMD:-docker compose}"
LOG_DIR="${LOG_DIR:-${STATE_DIR}/logs}"
LOCK_FILE="${STATE_DIR}/update_ecoplots_data.lock"
LAST_DATE_FILE="${STATE_DIR}/last_complete_results_date"
LAST_HEATMAP_DATE_FILE="${STATE_DIR}/last_heatmap_date"
MANIFEST_FILE="${PROJECT_ROOT}/EcoPlots/manifest_1y.csv"

mkdir -p "${LOG_DIR}" "${STATE_DIR}"

exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
  echo "Another EcoPlots update is already running; skipping."
  exit 0
fi

cd "${PROJECT_ROOT}"

RESULTS_DIR="${RESULTS_DIR:-$(cd "${PROJECT_ROOT}/../.." && pwd)/results}"

latest_complete_date() {
  local latest=""
  local stock_file date etf_file stock_lines etf_lines
  for stock_file in "${RESULTS_DIR}"/results_stock_xtest_*.csv; do
    [[ -e "${stock_file}" ]] || continue
    date="$(basename "${stock_file}")"
    date="${date#results_stock_xtest_}"
    date="${date%.csv}"
    etf_file="${RESULTS_DIR}/results_etf_xtest_${date}.csv"
    [[ -f "${etf_file}" ]] || continue
    stock_lines="$(wc -l < "${stock_file}" 2>/dev/null || echo 0)"
    etf_lines="$(wc -l < "${etf_file}" 2>/dev/null || echo 0)"
    [[ "${stock_lines:-0}" -gt 1 && "${etf_lines:-0}" -gt 1 ]] || continue
    latest="${date}"
  done
  [[ -n "${latest}" ]] || return 1
  printf '%s\n' "${latest}"
}

manifest_latest_date() {
  [[ -f "${MANIFEST_FILE}" ]] || return 1
  awk -F, 'NR == 2 { print $3 }' "${MANIFEST_FILE}"
}

heatmap_exists() {
  local date="$1"
  local date_folder="${date//-/}"
  compgen -G "${PROJECT_ROOT}/EcoPlots/www/heatmap/${date_folder}/sectors_dual_branded_${date}_vs_*.png" >/dev/null &&
    compgen -G "${PROJECT_ROOT}/EcoPlots/www/heatmap/${date_folder}/stocks_top16_dual_branded_${date}_vs_*.png" >/dev/null &&
    compgen -G "${PROJECT_ROOT}/EcoPlots/www/heatmap/${date_folder}/etf_top16_dual_branded_${date}_vs_*.png" >/dev/null
}

generate_heatmap() {
  local date="$1"
  if [[ "${HEATMAP_ENABLED:-1}" != "1" ]]; then
    return 0
  fi
  if heatmap_exists "${date}"; then
    printf '%s\n' "${date}" > "${LAST_HEATMAP_DATE_FILE}"
    echo "Heatmaps already current at ${date}."
    return 0
  fi
  if "${PROJECT_ROOT}/scripts/post_batch_heatmap.sh" "${date}" >> "${LOG_DIR}/heatmap_update_$(date +%Y%m%d).log" 2>&1; then
    printf '%s\n' "${date}" > "${LAST_HEATMAP_DATE_FILE}"
    echo "Heatmaps updated for ${date}."
    return 0
  fi
  echo "Warning: heatmap generation failed; see ${LOG_DIR}/heatmap_update_$(date +%Y%m%d).log" >&2
  return 1
}

LATEST_DATE="$(latest_complete_date)"
LAST_DATE="$(cat "${LAST_DATE_FILE}" 2>/dev/null || true)"
MANIFEST_DATE="$(manifest_latest_date || true)"

if [[ -z "${LAST_DATE}" && -n "${MANIFEST_DATE}" && "${MANIFEST_DATE}" == "${LATEST_DATE}" ]]; then
  printf '%s\n' "${LATEST_DATE}" > "${LAST_DATE_FILE}"
  echo "EcoPlots already current at ${LATEST_DATE}; initialized state and skipped rebuild."
  generate_heatmap "${LATEST_DATE}" || true
  exit 0
fi

if [[ "${LAST_DATE}" == "${LATEST_DATE}" && "${FORCE_ECOPLOTS_UPDATE:-0}" != "1" ]]; then
  echo "EcoPlots already current at ${LATEST_DATE}; skipped rebuild."
  generate_heatmap "${LATEST_DATE}" || true
  exit 0
fi

WAS_RUNNING=0
if ${COMPOSE_CMD} ps --status running --services 2>/dev/null | grep -qx "ecoplots"; then
  WAS_RUNNING=1
fi

restart_if_needed() {
  if [[ "${WAS_RUNNING}" == "1" ]]; then
    ${COMPOSE_CMD} up -d ecoplots >/dev/null 2>&1 || true
  fi
}
trap restart_if_needed EXIT

if [[ "${WAS_RUNNING}" == "1" && "${STOP_APP_DURING_UPDATE:-1}" == "1" ]]; then
  echo "Stopping ecoplots during rebuild to avoid memory pressure."
  ${COMPOSE_CMD} stop ecoplots
fi

echo "Rebuilding EcoPlots data for new complete result date ${LATEST_DATE}."
Rscript "${PROJECT_ROOT}/update_ecoplots_rds.R" "$@"

printf '%s\n' "${LATEST_DATE}" > "${LAST_DATE_FILE}"
generate_heatmap "${LATEST_DATE}" || true
echo "EcoPlots data update complete for ${LATEST_DATE}."
