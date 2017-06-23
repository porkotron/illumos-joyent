err_file='/tmp/dos2unix.err'

for file in $*
do
	dos2unix -n $file $file.new 2> $err_file
	grep -v 'dos2unix: converting file' $err_file
	rm -f $err_file
	mv -f $file.new $file
done
