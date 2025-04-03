#!/usr/bin/env tclsh

set test_dir [file normalize [info script]]
set test_dir [file dirname $test_dir]
set parent_dir [file dirname $test_dir]
cd $test_dir
set mwm [file join $parent_dir mwm.tcl]
set cache_file [file join $test_dir .mwmdata.tcld]
file delete -- $cache_file

set test_list [dict create  \
    "No folder provided" "--cd" \
    "does not exist or is not a folder" "--cd bad-dir" \
    "does not exist or is not a file" "--file bad-file" \
    "No file provided for --file" "--file" \
    "No target provided for --target" "--target" \
    "Target bad-target does not exist" "--target bad-target --file [file join $test_dir empty-mwmfile.tcl]" \
    "does not exist after an update" "--file [file join $test_dir bad-output-mwmfile.tcl]" \
    "is not a file or a target" "--file [file join $test_dir bad-input.tcl]" \
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

set ok_test_list [list \
    "--file [file join $test_dir works-zero-input.tcl]" \
    "--file [file join $test_dir works-one-io.tcl]" \
]
foreach args $ok_test_list {
    file delete -- $cache_file
    if {[catch {exec  $mwm {*}$args 2>@1} output]} {
        error "Test ($args) failed! output=(\n$output\n)"
    } else {
        puts "Test succeeded. ($args)"
    }
}

# Do cache testing
set cache_in_file [file join $test_dir cache-test-in.txt]
file delete -- $cache_file $cache_in_file

set args "--verbose --file [file join $test_dir cache-test.tcl]"
puts [exec  $mwm {*}$args 2>@1]

set out_f [file join $test_dir cache-test-out.txt]
set out_h [open $out_f r]
set old_val [read $out_h]
close $out_h

after 1001

puts [exec  $mwm {*}$args 2>@1]

set out_h [open $out_f r]
set new_val [read $out_h]
close $out_h

if {[string compare $new_val $old_val] != 0} {
    error "Error, file should not have re-built"
}

puts "Yippee! All tests passed!"
