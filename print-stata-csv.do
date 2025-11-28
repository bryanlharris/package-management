/***************************************************************************************************
 * Emit a tab-separated package report for Stata add-ons installed in the managed shared ado tree.
 *
 * Columns: name, version, source, reviewer, installer, summary, URL, location
 *
 * The script scans per-letter folders under C:\\Program Files\\Stata18\\shared_ado (created by
 * install-stata-baseline.do), looks for .pkg manifests, and reads metadata from the manifest and
 * accompanying .ado files. Missing fields are printed as empty strings so the output can be pasted
 * into a spreadsheet alongside the Python and R exporters.
 ***************************************************************************************************/

version 17.0

local shared_root "C:\\Program Files\\Stata18\\shared_ado"

if (lower(c(os)) != "windows") {
    display as error "This script is intended for Windows hosts."
    exit 9
}

if (!fileexists("`shared_root'")) {
    display as error "Shared ado directory not found: `shared_root'"
    exit 601
}

set more off

local letters ""
forvalues i = 97/122 {
    local letters "`letters' `=char(`i')'"
}
local letters "`letters' _"
local tab = char(9)

local seen_packages ""

program define emit_pkg, rclass
    syntax anything(name=pkgpath) , DIR(string)

    local package_name = substr("`pkgpath'", 1, length("`pkgpath'") - 4)
    local package_dir  "`dir'"
    local summary ""
    local url ""
    local version ""

    tempname fh
    capture file open `fh' using "`package_dir'\`pkgpath'", read text
    if (!_rc) {
        file read `fh' line
        while (r(eof) == 0) {
            local trimmed = trim("`line'")
            if ("`summary'" == "" & regexm("`trimmed'", "^d\\s+(.+)$")) {
                local summary = regexs(1)
                local summary = subinstr("`summary'", '"', "", .)
                local summary = subinstr("`summary'", "`tab'", " ", .)
                local summary = trim("`summary'")
            }
            if ("`url'" == "" & regexm("`line'", "https?://[^\\s\"]+")) {
                local url = regexs(0)
            }
            file read `fh' line
        }
        file close `fh'
    }

    local adofile "`package_dir'\`package_name'.ado"
    capture confirm file "`adofile'"
    if (!_rc) {
        tempname vfh
        capture file open `vfh' using "`adofile'", read text
        if (!_rc) {
            file read `vfh' aline
            while (r(eof) == 0 & "`version'" == "") {
                if (regexm(trim("`aline'"), "^\*!\\s*version\\s+(.+)$")) {
                    local version = trim(regexs(1))
                }
                file read `vfh' aline
            }
            file close `vfh'
        }
    }

    if ("`version'" == "") {
        local ados : dir "`package_dir'" files "*.ado"
        foreach ado of local ados {
            capture file open `vfh' using "`package_dir'\`ado'", read text
            if (_rc) continue
            file read `vfh' aline
            while (r(eof) == 0 & "`version'" == "") {
                if (regexm(trim("`aline'"), "^\*!\\s*version\\s+(.+)$")) {
                    local version = trim(regexs(1))
                }
                file read `vfh' aline
            }
            file close `vfh'
            if ("`version'" != "") continue, break
        }
    }

    display "`package_name'`tab'`version'`tab'Stata`tab'Reviewer`tab'Installer`tab'`summary'`tab'`url'`tab'`package_dir'"
end

local queue ""
foreach letter of local letters {
    local maybe "`shared_root'\`letter'"
    if (fileexists("`maybe'")) {
        local queue "`queue' `maybe'"
    }
}

while ("`queue'" != "") {
    gettoken current queue : queue

    local pkgfiles : dir "`current'" files "*.pkg"
    foreach pkgfile of local pkgfiles {
        local pkgname = substr("`pkgfile'", 1, length("`pkgfile'") - 4)
        if (strpos(" `seen_packages' ", " `pkgname' ")) continue
        local seen_packages "`seen_packages' `pkgname'"
        local dirname "`current'"
        quietly emit_pkg "`pkgfile'", dir("`current'")
    }

    local subdirs : dir "`current'" dirs "*"
    foreach sub of local subdirs {
        local queue "`queue' `current'\`sub'"
    }
}

exit 0
