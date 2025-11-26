#!/usr/bin/env Rscript
# Emit a tab-separated report for packages in r_requirements.txt using metadata
# from a local Windows mirror. Each row includes the package name, version,
# source, and mirror details so the output can be pasted into a spreadsheet.

get_script_dir <- function() {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- "--file="
  file_args <- args[grepl(paste0("^", file_arg), args)]

  if (!length(file_args)) {
    return(normalizePath(getwd(), winslash = "\\", mustWork = TRUE))
  }

  normalizePath(dirname(sub(file_arg, "", file_args[1])), winslash = "\\", mustWork = TRUE)
}

default_requirements <- file.path(get_script_dir(), "r_requirements.txt")
default_mirror <- normalizePath("C:/admin/r_mirror", winslash = "\\", mustWork = FALSE)
primary_library <- function() {
  normalizePath(.Library, winslash = "\\", mustWork = FALSE)
}

ensure_windows <- function() {
  if (!identical(tolower(Sys.info()[["sysname"]]), "windows")) {
    stop("This script is intended to run on Windows hosts only.")
  }
}

read_requirements <- function(path) {
  if (!file.exists(path)) {
    stop(sprintf("Missing requirements file at: %s", path))
  }

  entries <- readLines(path, warn = FALSE)
  entries <- trimws(entries)
  entries <- entries[entries != "" & !grepl("^#", entries)]
  unique(entries)
}

prepare_repos <- function() {
  repos <- getOption("repos")

  if (!length(repos) || is.na(repos["CRAN"]) || repos["CRAN"] == "@CRAN@") {
    repos["CRAN"] <- "https://cloud.r-project.org"
  }

  options(repos = repos)
}

mirror_dir <- function(base_path) {
  r_version <- paste(R.version$major, sub("\\..*$", "", R.version$minor), sep = ".")
  file.path(base_path, "bin", "windows", "contrib", r_version)
}

load_package_metadata <- function(mirror_path) {
  packages_file <- file.path(mirror_path, "PACKAGES")

  if (!file.exists(packages_file)) {
    stop(
      sprintf(
        "PACKAGES index not found at %s. Run build-r-mirror.R to populate the mirror.",
        packages_file
      )
    )
  }

  entries <- read.dcf(packages_file)
  as.data.frame(entries, stringsAsFactors = FALSE)
}

load_cran_metadata <- function(packages) {
  prepare_repos()
  available <- available.packages(fields = c("Title", "URL"))

  available[rownames(available) %in% packages, , drop = FALSE]
}

cran_field <- function(metadata, package, field) {
  if (!nrow(metadata) || !package %in% rownames(metadata)) {
    return("")
  }

  value <- metadata[package, field]

  if (is.null(value) || is.na(value) || !length(value) || value == "") {
    return("")
  }

  value
}

safe_field <- function(entry, field) {
  if (!field %in% names(entry)) {
    return("")
  }

  value <- entry[[field]]

  if (is.null(value) || is.na(value) || !length(value)) {
    return("")
  }

  value
}

first_non_empty <- function(values) {
  values <- values[!is.na(values) & values != ""]

  if (!length(values)) {
    return("")
  }

  values[[1]]
}

print_report <- function(requirements_path, mirror_path) {
  ensure_windows()
  packages <- read_requirements(requirements_path)

  if (!length(packages)) {
    message(sprintf("No packages listed in %s; nothing to report.", requirements_path))
    return(invisible(NULL))
  }

  mirror <- mirror_dir(mirror_path)

  if (!dir.exists(mirror)) {
    stop(
      sprintf(
        "Local mirror not found at %s. Run build-r-mirror.R to download the binaries.",
        mirror
      )
    )
  }

  metadata <- load_package_metadata(mirror)
  cran_metadata <- load_cran_metadata(packages)
  installed <- as.data.frame(
    installed.packages(lib.loc = primary_library(), fields = c("Package", "LibPath")),
    stringsAsFactors = FALSE
  )
  matching <- metadata[metadata$Package %in% packages, , drop = FALSE]
  missing <- setdiff(packages, matching$Package)

  if (length(missing)) {
    warning(sprintf("Missing %d package(s) in mirror: %s", length(missing), paste(missing, collapse = ", ")))
  }

  for (row in seq_len(nrow(matching))) {
    entry <- matching[row, ]
    name <- entry$Package
    version <- entry$Version
    summary <- first_non_empty(c(safe_field(entry, "Title"), cran_field(cran_metadata, name, "Title")))
    url <- first_non_empty(c(safe_field(entry, "URL"), cran_field(cran_metadata, name, "URL")))
    install_base <- installed$LibPath[installed$Package == name]
    location <- if (length(install_base)) {
      normalizePath(file.path(install_base[[1]], name), winslash = "\\", mustWork = FALSE)
    } else {
      mirror
    }

    cat(sprintf("%s\t%s\tCRAN\tReviewer\tInstaller\t%s\t%s\t%s\n", name, version, summary, url, location))
  }
}

print_report(default_requirements, default_mirror)
