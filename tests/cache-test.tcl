set output cache-test-out.txt
set input cache-test-in.txt

set val [clock seconds]

make_target main $output make-in "echo $val > $output"

make_target make-in $input {} "echo fixed > $input"
