#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || is.na(x)) y else x

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

script_arg <- commandArgs(FALSE)[grep("^--file=", commandArgs(FALSE))][1]
script_path <- if (length(script_arg) == 0 || is.na(script_arg)) {
  "update_ecoplots_rds.R"
} else {
  sub("^--file=", "", script_arg)
}
script_dir <- normalizePath(dirname(script_path), mustWork = FALSE)
workflow_root <- find_up(script_dir, "EcoPlots") %||% normalizePath(getwd(), mustWork = TRUE)

builder <- file.path(workflow_root, "build_ecoplots_rds.R")
if (!file.exists(builder)) {
  builder <- file.path(workflow_root, "r", "build_ecoplots_rds.R")
}
if (!file.exists(builder)) {
  stop("Could not find build_ecoplots_rds.R under ", workflow_root)
}

status <- system2(
  "Rscript",
  c(shQuote(builder), "--mode=incremental", args),
  stdout = "",
  stderr = ""
)

quit(save = "no", status = status)
