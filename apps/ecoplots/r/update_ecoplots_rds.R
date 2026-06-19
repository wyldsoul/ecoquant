#!/usr/bin/env Rscript

script_arg <- commandArgs(FALSE)[grep("^--file=", commandArgs(FALSE))][1]
script_path <- if (length(script_arg) == 0 || is.na(script_arg)) {
  file.path("r", "update_ecoplots_rds.R")
} else {
  sub("^--file=", "", script_arg)
}
project_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
source(file.path(project_root, "update_ecoplots_rds.R"), echo = FALSE)
