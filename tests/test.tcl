#!/usr/bin/env tclsh

set test_dir [file normalize [info script]]
set test_dir [file dirname $test_dir]
set parent_dir [file dirname $test_dir]
cd $parent_dir
set mwm [file join $parent_dir mwm.tcl]

set test_list [dict create  \
    "No folder provided" "--cd" \
    "does not exist or is not a folder" "--cd bad-dir" \
    "does not exist or is not a file" "--file bad-file" \
    "No file provided for --file" "--file" \
    "No target provided for --target" "--target" \
    "Target bad-target does not exist" "--target bad-target --file [file join $test_dir empty-mwmfile.tcl]" \
    "does not exist after an update" "--file [file join $test_dir bad-output-mwmfile.tcl]" \
]
dict for {text args} $test_list {
    if {[catch {exec  $mwm {*}$args 2>@1} output] == 0} {
        error "This test should have failed! $args output=$output"
    } else {
        if {[string match "*$text*" $output] == 0} {
            error "Test failed! ($args) Failed to find \"$text\" in (\n$output\n)"
        } else {
            puts "Test succeeded. ($args)"
        }
    }
}

puts "Yippee! All tests passed!"
