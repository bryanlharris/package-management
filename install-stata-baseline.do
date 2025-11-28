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

    local subdir = substr("`p'", 1, 1)
    // When mirroring, Stata unpacks the package files and writes `stata.trk`
    // directly under the first-letter folder (e.g., `mirror\r\`). Point `from()`
    // at that lettered folder so `net install` reads the manifest without a
    // `.pkg` file.
    local fromdir "`mirror'\`subdir'"

    display "Installing `p' from `fromdir'"
    cap net install `p', from(`"`fromdir'"') replace
    if (_rc) {
        display as error "Failed: `p'"
        exit _rc
    }
}

exit 0
