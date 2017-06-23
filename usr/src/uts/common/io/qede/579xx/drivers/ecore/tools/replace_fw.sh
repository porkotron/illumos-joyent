#!/bin/bash

csv_file=`dirname $0`/replace_fw.csv

files_modified_p4_edit=()
files_modified_no_p4_edit=()

function usage () {
	echo "Usage: replace_fw.sh <source fw> <destination ecore> [-p <p4 client>] [-t <tag filter>]"
	echo ""
	echo "       source fw            path of the root folder of the source fw"
	echo "       destination ecore    path of the destination ecore folder"
	echo ""
	echo "       p4 client            different p4 client instead of the one that is currently in use"
	echo "                            (a value of AVOID_P4 will avoid p4 processing at all)"
	echo ""
	echo "       tag filter           preform operations on files that are specified in the tag filter"
	echo "                            if tag filter is not specified preform opreations on all files"
}

function get_last_char() {
	echo ${1: -1}
}

function trim_last_char() {
	echo ${1%?}
}

# $1 - string
# $2 - delimiter
function get_last_substr() {
	echo ${1##*$2}
}

function check_p4_exist() {
	p4 -V &> /dev/null
	ret=$?
	return $ret
}

function check_p4_login() {
	p4 login -s &> /dev/null
	ret=$?
	return $ret
}

function get_abs_filename() {
	echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
}

# $1 - array
# $2 - item
function is_item_in_array() {
	if [[ `echo $1 | grep $2 | wc -l` > 0 ]]; then true; else false; fi
}

# $1 - target file
# $2 - modified files array ('0' - "p4_edit" array, '1' - "no_p4_edit" array)
function add_file_to_modified_array() {
	local abs_file_path=$(get_abs_filename $1)

	# add the file only if it wasn't already added to the array
	if [[ $2 == 0 ]]; then
		is_item_in_array "${files_modified_p4_edit[*]}" $abs_file_path || files_modified_p4_edit=(${files_modified_p4_edit[@]} $abs_file_path)
	else
		is_item_in_array "${files_modified_no_p4_edit[*]}" $abs_file_path || files_modified_no_p4_edit=(${files_modified_no_p4_edit[@]} $abs_file_path)
	fi
}

#
# check usage
#
if [ $# -lt 2 ]; then
	usage
	exit 1
fi

fw_path=$1
ecore_path=$2
shift 2

# If the user doesn't enter tag filter, then don't filter by tag
tag_filter="none"

# Parse options received from user
while getopts ":p:t:" option; do
	case $option in
	p)
		p4_client=$OPTARG
		;;
	t)
		tag_filter=$OPTARG
		;;
	\?)
		echo "unknown option: -$OPTARG"
		usage
		exit 1
		;;
	:)
		echo "missing option argument for -$OPTARG"
		usage
		exit 1
		;;
	esac
done

if [ ! $p4_client ]; then
	p4cmd="p4"
else
	p4cmd="p4 -c $p4_client"
fi

#
# remove a possible "/" suffix from the paths for a common handling
#
if [ $(get_last_char $fw_path) = "/" ]; then
	fw_path=$(trim_last_char $fw_path)
fi
if [ $(get_last_char $ecore_path) = "/" ]; then
	ecore_path=$(trim_last_char $ecore_path)
fi

#
# avoid p4 processing if an "AVOID_P4" argument was provided.
# if "AVOID_P4" wasn't used - exit in case (1) p4 doesn't exist, or (2) no p4 client is logged in
#
avoid_p4_at_all=0
if [ "$p4_client" = "AVOID_P4" ]; then
	echo " Avoiding any p4 actions"
	avoid_p4_at_all=1
else
	check_p4_exist
	if [ $? != 0 ]; then
		echo " p4 is not installed - can either:"
		echo "   (1) install p4"
		echo "   (2) use '-p AVOID_P4' as an argument to avoid p4 processing"
		echo " Aborting"
		exit 1
	else
		check_p4_login
		if [ $? != 0 ]; then
			echo " No p4 user is logged in - can either:"
			echo "   (1) log in to p4"
			echo "   (2) use '-p AVOID_P4' as an argument to avoid p4 processing"
			echo " Aborting"
			exit 1
		fi
	fi
fi

#
# go over the csv file and verify that all src/dst actually exist
#
abort_file_not_exist=0
abort_no_destination=0
found_tag=0
line_num=0
while read line
do
	line_num=$((line_num+1))
	# skip the titles line
	if [ $line_num == 1 ]; then continue; fi

	# extract the csv line inputs
	enabled=`echo $line | cut -d ',' -f1`
	tag=`echo $line | cut -d ',' -f2`
	src=`echo $line | cut -d ',' -f4`
	dst=`echo $line | cut -d ',' -f5`

	if [[ "$enabled" == "0" ]]; then continue; fi
	if [ "$tag_filter" != "none" ]; then
		if [ "$tag" != "$tag_filter" ]; then continue; else found_tag=1; fi
	fi

	src_files_num=0
	if [ $src ]; then
		src=${fw_path}/${src}
		ls $src &> /dev/null
		if [ $? != 0 ]; then
			echo " $csv_file: line $line_num: error: cannot access $src"
			abort_file_not_exist=1
		else
			src_files_num=`ls $src | wc -l`
		fi
	fi

	dst_files_num=0
	if [ $dst ]; then
		dst=${ecore_path}/${dst}
		ls $dst &> /dev/null
		if [ $? != 0 ]; then
			echo " $csv_file: line $line_num: error: cannot access $dst"
			abort_file_not_exist=1
		else
			dst_files_num=`ls $dst | wc -l`
		fi
	else
		echo " $csv_file: line $line_num: error: no destination"
		abort_no_destination=1
	fi

	# for a case where the destination is a folder (valid when the source is a regular expression)
	if [ $src_files_num != 0 ] && [ $dst_files_num -lt $src_files_num ]; then
		echo " $csv_file: line $line_num: error: the number of source files and destination files is not equal ($src_files_num source files, $dst_files_num destination files)"
		abort_no_destination=1
	fi
done < $csv_file

if [[ "$tag_filter" != "none" && $found_tag == 0 ]]; then
	echo " tag $tag_filter doesn't exist"
	exit 1
fi

if [ $abort_file_not_exist == 1 ] || [ $abort_no_destination == 1 ]; then
	echo " Aborting"
	exit 1
fi

#
# go over the csv file and process (copy / add prefix / sed script) where needed
#
echo "Updating the files according to the $csv_file file"
line_num=0
while read line
do
	line_num=$((line_num+1))
	# skip the titles line
	if [ $line_num == 1 ]; then continue; fi

	# extract the csv line inputs
	enabled=`echo $line | cut -d ',' -f1`
	tag=`echo $line | cut -d ',' -f2`
	src=`echo $line | cut -d ',' -f4`
	dst=`echo $line | cut -d ',' -f5`
	skip_p4_this_file=`echo $line | cut -d ',' -f6`
	prefix=`echo $line | cut -d ',' -f7`
	sed_cmd=`echo $line | cut -d ',' -f8`
	binary=`echo $line | cut -d ',' -f10`

	if [[ "$enabled" == "0" ]]; then continue; fi
	if [[ "$tag_filter" != "none" && "$tag" != "$tag_filter" ]]; then continue; fi

	if [[ $avoid_p4_at_all == 0 && $skip_p4_this_file != 1 ]]; then modified_array=0; else modified_array=1; fi

	skip_copy=0
	if [ ! $src ]; then skip_copy=1; fi
	src=${fw_path}/${src}
	dst=${ecore_path}/${dst}

	# detect a case where the destination is a folder (valid when the source is a regular expression)
	is_dst_folder=0
	dst_regex=$dst
	if [ $(get_last_char $dst) = "/" ]; then
		is_dst_folder=1
		# append the source regular expression to the destination folder path
		dst_regex=${dst_regex}$(get_last_substr "$src" "/")
	fi

	# copy
	if [ $skip_copy == 0 ]; then
		for src_file in `ls $src 2> /dev/null`
		do
			dst_file=$dst
			if [ $is_dst_folder == 1 ]; then
				# append the source file name to the destination folder path
				dst_file=${dst_file}$(get_last_substr "$src_file" "/")
			fi

			if [ `diff --strip-trailing-cr $src_file $dst_file | wc -l` -gt 0 ]; then
				chmod u+w $dst_file
				cp -f $src_file $dst_file
				if [ "$binary" == "" ]; then
					$ecore_path/tools/dos2unix.sh $dst_file
				fi
				add_file_to_modified_array $dst_file $modified_array
			fi
		done
	fi

	# prefix
	if [ "$prefix" != "" ]; then
		for dst_file in `ls $dst_regex 2> /dev/null`; do
			(echo -e $prefix && cat $dst_file) > $dst_file.new
			chmod u+w $dst_file
			mv -f $dst_file.new $dst_file
			add_file_to_modified_array $dst_file $modified_array
		done
	fi

	# sed
	if [ "$sed_cmd" != "" ]; then
		echo -e "$sed_cmd" > sed_cmd.tmp
		for dst_file in `ls $dst_regex 2> /dev/null`; do
			sed -f sed_cmd.tmp $dst_file > $dst_file.new
			chmod u+w $dst_file
			mv -f $dst_file.new $dst_file
			add_file_to_modified_array $dst_file $modified_array
		done
		rm -f sed_cmd.tmp
	fi
done < $csv_file

#
# Check out the files which were marked as modified
#
if [[ ${#files_modified_p4_edit[@]} > 0 ]]; then
	echo "Checking out the modified files"
	$p4cmd edit ${files_modified_p4_edit[@]} > /dev/null

	# undo checking out in case a file is unchanged
	$p4cmd revert -a ${files_modified_p4_edit[@]} > revert.tmp
	for ((i=0; i<${#files_modified_p4_edit[@]}; i++)); do
		partial_file_path=`echo ${files_modified_p4_edit[$i]} | sed -e 's/\(.*\)\/579xx\/\(.*\)/\/579xx\/\2/g'`
		if [ `grep $partial_file_path revert.tmp | wc -l` -gt 0 ]; then
			files_modified_p4_edit=(${files_modified_p4_edit[@]:0:$i} ${files_modified_p4_edit[@]:$(expr $i + 1)})
			# update the index since the array size was decreased and the elements were shifted
			i=$((i-1))
		fi
	done
	rm -f revert.tmp
fi

#
# summary
#
for ((i=0; i<${#files_modified_p4_edit[@]}; i++)); do
	if [[ $i == 0 ]]; then
		echo "The following [ ${#files_modified_p4_edit[@]} ] files were modified and checked out:"
	fi
	echo "  ${files_modified_p4_edit[$i]}"
done
for ((i=0; i<${#files_modified_no_p4_edit[@]}; i++)); do
	if [[ $i == 0 ]]; then
		echo "The following [ ${#files_modified_no_p4_edit[@]} ] files were modified but were not checked out:"
	fi
	echo "  ${files_modified_no_p4_edit[$i]}"
done

exit 0
