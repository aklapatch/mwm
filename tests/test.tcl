#!/usr/bin/env tclsh

set parent_dir [file normalize [info script]]
set parent_dir [file dirname [file dirname $parent_dir]]
cd $parent_dir
set mwm [file join $parent_dir mwm.tcl]

set test_list [dict create  \
    "No folder provided" {--cd} \
    "does not exist or is not a folder" {--cd bad-dir} \
    "does not exist or is not a file" {--file bad-file} \
    "No file provided for --file" {--file} \
]

dict for {text args} $test_list {
    if {[catch {exec  $mwm {*}$args 2>@1} output] == 0} {
        error "This test should have failed! $args output=$output"
    } else {
        if {[string match "*$text*" $output] == 0} {
            error "$args test failed! Failed to find \"$text\" in $output"
        } else {
            puts "$args Test succeeded."
        }
    }
}

puts "Yippee! All tests passed!"

