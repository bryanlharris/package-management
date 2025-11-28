/***************************************************************************************************
 * Install Stata packages directly into the shared ado directory using requirement metadata.
 *
 * This replaces the older mirror-building approach by pointing Stata's PLUS directory to the
 * shared ado location and installing each listed package from its upstream source with
 * `replace`, allowing repeatable reinstallation without a separate mirror tree.
 *
 * Usage (from the project root on Windows):
 *
 *   Right-click the file and choose "Do" in Stata (or run via Stata's batch CLI if available).
 *
 * Requirements:
 *   - Windows host.
 *   - `stata_requirements.txt` with headers `packagename,url` saved in this repository's root.
 *   - Shared ado directory at `C:\\Program Files\\Stata18\\shared_ado` (created if missing).
 ***************************************************************************************************/

version 17.0

local requirements "`c(pwd)'\stata_requirements.txt"
local target "C:\\Program Files\\Stata18\\shared_ado"

if (lower(c(os)) != "windows") {
    display as error "Windows only."
    exit 9
}

capture confirm file "`requirements'"
if (_rc) {
    display as error "Missing: `requirements'"
    exit 601
}

// Ensure the target directory exists and becomes the PLUS location for installations.
cap mkdir "`target'"
sysdir set PLUS "`target'"

import delimited using "`requirements'", clear stringcols(_all) varnames(1)

rename packagename pkg

if (_N == 0) {
    display "Nothing to install."
    exit 0
}

set more off

quietly forvalues i = 1/`=_N' {
    local p = pkg[`i']
    local src = url[`i']

    if ("`p'" == "" | "`src'" == "") continue

    display "Installing `p' from `src'"
    cap net install `p', from(`"`src'"') replace
    if (_rc) {
        display as error "Failed: `p'"
        exit _rc
    }
}

exit 0
