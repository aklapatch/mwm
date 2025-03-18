
set output one-io-out.txt
set input one-io-in.txt

make_target main $output make-in "echo hello > $output"

make_target make-in $input {} "echo hello > $input"
