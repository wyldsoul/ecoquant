#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
RESULTS_DIR="${RESULTS_DIR:-$(cd "${PROJECT_ROOT}/../.." && pwd)/results}"
OUTPUT_DIR="${HEATMAP_OUTPUT_DIR:-${PROJECT_ROOT}/EcoPlots/www/heatmap}"
LOG_DIR="${LOG_DIR:-${PROJECT_ROOT}/.state/logs}"
DATE_ARG="${1:-}"

mkdir -p "${OUTPUT_DIR}" "${LOG_DIR}"

latest_complete_date() {
  local latest=""
  local stock_file date etf_file
  for stock_file in "${RESULTS_DIR}"/results_stock_xtest_*.csv; do
    [[ -e "${stock_file}" ]] || continue
    date="$(basename "${stock_file}")"
    date="${date#results_stock_xtest_}"
    date="${date%.csv}"
    etf_file="${RESULTS_DIR}/results_etf_xtest_${date}.csv"
    [[ -s "${stock_file}" && -s "${etf_file}" ]] || continue
    latest="${date}"
  done
  [[ -n "${latest}" ]] || return 1
  printf '%s\n' "${latest}"
}

if [[ -z "${DATE_ARG}" ]]; then
  DATE_ARG="$(latest_complete_date)"
fi

run_with_host_python() {
  python3 - <<'PY' >/dev/null 2>&1
import pandas, numpy, matplotlib, PIL
PY
  EQI_RESULTS_DIR="${RESULTS_DIR}" \
  EQI_HEATMAP_OUTPUT_DIR="${OUTPUT_DIR}" \
    python3 "${PROJECT_ROOT}/python/run_heatmap.py" "${DATE_ARG}"
}

run_with_docker() {
  local compose_cmd="${COMPOSE_CMD:-docker compose}"
  cd "${PROJECT_ROOT}"
  ${compose_cmd} run --rm heatmap-worker "${DATE_ARG}"
}

echo "Generating heatmaps for ${DATE_ARG}"
echo "Results: ${RESULTS_DIR}"
echo "Output: ${OUTPUT_DIR}"

if run_with_host_python; then
  exit 0
fi

echo "Host Python dependencies unavailable or failed; trying Docker heatmap-worker..."
run_with_docker
