/***************************************************************************************************
 * Install Stata packages from the local mirror into the shared ado directory.
 *
 * Usage (from the project root on Windows):
 *
 *   Right-click the file and choose "Do" in Stata (or run via Stata's batch CLI if available).
 *
 * The script installs packages listed in `stata_requirements.txt` from `C:\admin\stata_mirror`
 * into `C:\Program Files\Stata18\shared_ado` using `net install`.
 ***************************************************************************************************/

version 17.0

local requirements "`c(pwd)'\stata_requirements.txt"
local mirror "C:\admin\stata_mirror"
local target "C:\Program Files\Stata18\shared_ado"

if (lower(c(os)) != "windows") {
    display as error "Windows only."
    exit 9
}

capture confirm file "`requirements'"
if (_rc) {
    display as error "Missing: `requirements'"
    exit 601
}

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

    if ("`p'" == "") continue

    // The mirror exposes a single `stata.trk` file at its root that contains
    // pointers to the lettered subfolders. Point `from()` at the mirror root so
    // `net install` reads that manifest and follows it to the right subfolder.
    local fromdir "`mirror'"

    display "Installing `p' from `fromdir'"
    cap net install `p', from(`"`fromdir'"') replace
    if (_rc) {
        display as error "Failed: `p'"
        exit _rc
    }
}

exit 0
