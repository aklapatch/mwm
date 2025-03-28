#!/usr/bin/env tclsh

set main_target "main"
set cd_dir "."
set mwm_file mwmfile.tcl
set g_verbose 0

proc p_usage {} {
	puts "$::argv0 usage:
    --cd <path>
        Changes to <path> before executing commands.
    --file <other-mwmfile.tcl>
        Source targets from <other-mwmfile.tcl> instead of mwmfile.tcl
    --target <main-target>
        Build this target instead of \"$main_target\"
        "
}

for {set i 0} {$i < $argc} {incr i} {
	set arg [lindex $argv $i]
	switch $arg {
        -h - 
        --help { 
            p_usage
            exit 0
        }
        --cd { 
			incr i
            if {$argc == $i} {
                error "No folder provided for --cd"
            }
			set cd_dir [lindex $argv $i]
        }
		--target {
			incr i
            if {$argc == $i} {
                error "No target provided for --target"
            }
			set main_target [lindex $argv $i]
        }
		--file {
			incr i
            if {$argc == $i} {
                error "No file provided for --file"
            }
			set mwm_file [lindex $argv $i]
        }
        --verbose {
            set g_verbose 1
		}
		default { error "Unrecognized arg $arg!" }
    }
}

# Store values in a {up-to-date inputs outputs}
set g_targets [dict create]

proc make_target {name outputs inputs command} {
    global g_targets
    if {[dict exists $g_targets $name]} {
        error "$name is already a target!"
    }
    set add_val [list 0 $outputs $inputs $command]
    global g_verbose
    if {$g_verbose} {
        puts "Adding target $name with these values ($add_val)"
    }
    dict set g_targets $name $add_val
}

if {[file isdirectory $cd_dir] == 0} {
    error "$cd_dir does not exist or is not a folder!"
}
cd $cd_dir

if {[file isfile $mwm_file] == 0} {
    error "$mwm_file does not exist or is not a file!"
}
source $mwm_file

# This file holds the lengths for each file.
set data_file .mwmdata.tsv
set g_f_lens [dict create]
if {[file exists $data_file]} {
    set data_f [open $data_file r]
    while {[gets $data_f line] >= 0} {
        set re_pat "^(.*)\t(\\d+) (\\d+)$"
        puts $line
        if {[regexp $re_pat $line full_match f_name f_len f_hash] == 0} {
            error "Failed to parse data line! ($line)"
        }
        dict set g_f_lens $f_name [list $f_len $f_hash]
    }
    close $data_f
    if {$g_verbose} {
        puts "File cache:\n$g_f_lens"
    }
}

proc hash_file {f_path} {
    set read_sz 8
    # The golden ratio, 64 bit.
    set state 0x9e3779b97f4a7c13
    if {[file size $f_path] == 0} {
        return $state
    }
    set f_h [open $f_path rb]
    while {1} {
        set rd [read $f_h $read_sz]
        foreach char [split $rd ""] {
           set char_int [scan $char %c]
           set state [expr $state + $char_int]
        }
        # Mixing function from https://jonkagstrom.com/mx3/mx3_rev2.html.
        set state [expr $state ^ ($state >> 32)]
        set state [expr $state * 0xe9846af9b1a615d]
        set state [expr $state ^ ($state >> 32)]
        set state [expr $state * 0xe9846af9b1a615d]
        set state [expr $state ^ ($state >> 28)]
        set state [expr $state & 0xffffffffffffffff]
        if {[eof $f_h]} { break }
    }
    close $f_h
    return $state
}

# TODO: Optimize for multithreading.
proc update_target {t_name} {
    global g_targets
    if {[dict exists $g_targets $t_name] == 0} {
        error "Target $t_name does not exist!"
    }
    set t_info [dict get $g_targets $t_name]

    global g_verbose
    set inputs [lindex $t_info 2]
    set up_to_date 1
    foreach input $inputs {
        if {[file isfile $input]} {
            if {[dict exists $g_f_lens $input]} {
                set f_meta [dict get $g_f_lens $input]
                set f_len [lindex $f_meta 0]
                set f_hash [lindex $f_meta 1]
                set f_size [file size $input]
                if {[string compare $f_len $f_size] != 0} {
                    if {$g_verbose} {
                        puts "$input is out of date old len=$f_len, new len=$f_size"
                    }
                    set up_to_date 0
                }
                set new_f_hash [hash_file $input]
                if {[string compare $new_f_hash $f_hash] != 0} {
                    if {$g_verbose} {
                        puts "$input is out of date old hash=$f_hash, new hash=$new_f_hash"
                    }
                    set up_to_date 0
                }
            } else {
                # The file did not exist before.
                set up_to_date 0
            }
        } elseif {[file isdirectory $input]} {
            if {$g_verbose} {
                puts "\"$input\" is a folder, skipping"
            }
        } elseif {[dict exists $g_targets $input]} {
            if {$g_verbose} {
                puts "Updating \"$input\" for \"$t_name\""
            }
            set in_info [dict get $g_targets $input]
            set in_up_to_date [lindex $in_info 0]
            if {$in_up_to_date == 0} {
                # Avoid checking input targets many times if they're already updated.
                if {[update_target $input] > 0} {
                    set up_to_date 0
                }
            }
        } else {
            error "$input for target \"$t_name\" is not a file or a target!"
        }
    }
    set updated 0
    if {$up_to_date == 0 || [llength $inputs] == 0} {
        set command [lindex $t_info 3]
        if {$g_verbose} {
            puts "Running $command for $t_name"
        }
        # Assume the file is an output of the command.
        if {[llength [info procs $command]] == 1} {
            # Run this TCL proc
            $command
        } else {
            exec >@stdout 2>@stderr {*}$command
        }
        global g_f_lens
        foreach output [lindex $t_info 1] {
            if {[file exists $output] == 0} {
                error "Output \"$output\" does not exist after an update!"
            } elseif {[file isfile $output]} {
                set new_sz [file size $output]
                set f_hash [hash_file $output]
                if {[dict exists $g_f_lens $output]} {
                    # Only say we updated if our outputs are different
                    set old_vals [dict get $g_f_lens $output]
                    set old_sz [lindex $old_vals 0]
                    set old_hash [lindex $old_vals 1]
                    if {[string compare $old_sz $new_sz] != 0} {
                        if {$g_verbose} {
                           puts "File $output changed size old=$old_sz new=$new_sz" 
                        }
                        set updated 1
                    } elseif {[string compare $old_hash $f_hash] != 0} {
                        if {$g_verbose} {
                           puts "File $output changed hash old=$old_hash new=$f_hash" 
                        }
                        set updated 1
                    }
                }
                if {$g_verbose} {
                    puts "Updating size for \"$output\" to $new_sz and hash to $f_hash"
                }
                dict set g_f_lens $output [list $new_sz $f_hash]
            } 
        }
    }
    # Mark that we're up to date in the global list.
    lset t_info 0 1
    dict set g_targets $t_name $t_info
    return $updated
}

update_target $main_target

if {[dict size $g_f_lens] > 0} {
    if {$g_verbose} {
        puts "Updating $data_file with new lengths and hashes"
    }
    set data_f [open $data_file w]
    dict for {f_name data} $g_f_lens {
        set f_len [lindex $data 0]
        set f_hash [lindex $data 1]
        set add_str "$f_name\t$f_len $f_hash"
        if {$g_verbose} {
            puts "Writing entry: \"($add_str)\""
        }
        puts $data_f $add_str
    }
    close $data_f
}
