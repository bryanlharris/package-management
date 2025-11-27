/***************************************************************************************************
* Prepare a local mirror of Stata packages listed in `stata_requirements.txt`.
*
* Usage (from the project root on Windows):
*
*   stata-se -b do build-stata-mirror.do
*   // or: StataMP-64 -b do build-stata-mirror.do
*
* The script downloads each package into `C:\admin\stata_mirror` using `net install`.
* Each requirement entry should provide a package name and a base URL (CSV with headers
* `packagename` and `url`).
***************************************************************************************************/

version 17.0

local requirements "`c(pwd)'\stata_requirements.txt"
local mirror "C:\admin\stata_mirror"

if (lower(c(os)) != "windows") {
    display as error "Windows only."
    exit 9
}

capture confirm file "`requirements'"
if (_rc) {
    display as error "Missing: `requirements'"
    exit 601
}

capture mkdir "`mirror'"

sysdir set PLUS "`mirror'"

import delimited using "`requirements'", clear stringcols(_all)

rename packagename pkg
rename url baseurl

if (_N == 0) {
    display "Nothing to mirror."
    exit 0
}

set more off

quietly forvalues i = 1/`=_N' {
    local p = pkg[`i']
    local u = baseurl[`i']

    if ("`p'" == "" | "`u'" == "") continue

    display "Installing `p' from `u'"
    cap net install `p', from(`"`u'"') replace
    if (_rc) {
        display as error "Failed: `p'"
        exit _rc
    }
}

exit 0
