/***************************************************************************************************
 * Install Stata packages from a locally cloned mirror into the shared ado directory.
 *
 * Usage (from the project root on Windows):
 *
 *   Right-click the file and choose "Do" in Stata (or run via Stata's batch CLI if available).
 *
 * The script installs packages listed in `stata_requirements.txt` from the local mirror at
 * `C:\admin\stata_mirror`. Each package is expected to live in its own subfolder named after the
 * package (e.g., `C:\admin\stata_mirror\rdmulti\...`) that was created by `build-stata-mirror.py`.
 * No remote URLs are used during installation.
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

    // Install from the package-specific mirror folder. No remote URLs are referenced.
    local fromdir "`mirror'\`p'"

    display "Installing `p' from `fromdir'"
    cap net install `p', from(`"`fromdir'"') replace
    if (_rc) {
        display as error "Failed: `p'"
        exit _rc
    }
}

exit 0
