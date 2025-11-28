local root "C:/Program Files/Stata18/shared_ado"
local source "Stata"
local reviewer "Reviewer"
local installer "Installer"

local files : dir "`root'" files "*.ado", respectcase recurse

foreach f of local files {
    local pkg : basename "`f'"
    local pkg : subinstr local pkg ".ado" "", all
    local loc : dir "`root'" dirs "*", respectcase

    tempname buf
    tempfile log
    log using `log', text replace
    capture noisily ssc describe `pkg'
    log close

    file open `buf' using `log', read
    local version ""
    local desc ""
    local url ""

    file read `buf' line
    while r(eof)==0 {
        if strpos(lower("`line'"), "distribution-date") {
            local version : word 2 of "`line'"
        }
        if "`desc'"=="" & strpos("`line'", "TITLE") {
            file read `buf' nxt
            if r(eof)==0 local desc "`nxt'"
        }
        if strpos(lower("`line'"), "from http") {
            local url : subinstr local line "Package from " "", all
        }
        file read `buf' line
    }
    file close `buf'

    di "`pkg'" ///
    char(9) "`version'" ///
    char(9) "`source'" ///
    char(9) "`reviewer'" ///
    char(9) "`installer'" ///
    char(9) "`desc'" ///
    char(9) "`url'" ///
    char(9) "`root'/`f'"
}
