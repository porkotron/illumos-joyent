#!/bin/bash
#
# This Script generates  a .pdf from Latex src
###############################################

TEX_FILE=""
TEX_DIR=""
CUR_DIR=`pwd`;

# Check inputs
if [ $# -eq 1 ]; then
	TEX_FILE=$(basename $1)
	TEX_DIR=$(dirname $1)
	echo "File is located at $TEX_DIR"
else
	echo "Need to receive a .tex file as input"
	exit 1
fi

cd $TEX_DIR

# Create temporary directory for products
if [ -d tmp ]; then
	rm -rf tmp/*
else
	mkdir tmp
fi

# Create list of funcs
FUNCS=`grep myfunc ${TEX_FILE}.tex | grep -v newcommand | grep -v "^%" | sed -e 's/.*\myfunc{\([a-zA-Z0-9_\\]*\)}.*/\1/' | sed -e 's/\\\_/\_/g' `

# Create Snippets
for func in $FUNCS; do
	API_FILE=`grep -l ecore_$func\( ../*_api*.h`
	if [ -z "$API_FILE" ]; then
		echo "$func - Missing definition in API header files"
		continue
	fi

	BACK=1
	while [ $BACK -lt 100 ]; do
		EMPTY_BACK=`grep ${func}\( -B${BACK} $API_FILE | grep "^$" | wc --lines`;
		if [ $EMPTY_BACK -gt 0 ]; then
			BACK=`expr $BACK - 1`
			break;
		else
			BACK=`expr $BACK + 1`
		fi
	done

	FORWARD=0
	while [ $FORWARD -lt 100 ]; do
		EMPTY_FORWARD=`grep ${func}\( -A${FORWARD} $API_FILE | grep ");" | wc --lines`;
		EMPTY_FORWARD2=`grep ${func}\( -A${FORWARD} $API_FILE | grep "{" | wc --lines`;
		EMPTY=`expr $EMPTY_FORWARD + $EMPTY_FORWARD2`
		if [ $EMPTY -gt 0 ]; then
			break;
		else
			FORWARD=`expr $FORWARD + 1`
		fi
	done

	snippet=`grep ${func}\( -A${FORWARD} -B${BACK} $API_FILE | sed -e 's/ {/;/g' | grep -v "^\s*\*\s*$"`

	echo "$snippet" > snippets/${func}_generated.h
done

# Generate the File
pdflatex -output-directory=tmp -interaction=nonstopmode $TEX_FILE.tex
pdflatex -output-directory=tmp -interaction=nonstopmode $TEX_FILE.tex
makeindex tmp/$TEX_FILE.idx
makeindex tmp/$TEX_FILE.idx
bibtex -terse tmp/$TEX_FILE.aux
bibtex -terse tmp/$TEX_FILE.aux
pdflatex -output-directory=tmp -interaction=nonstopmode $TEX_FILE.tex
pdflatex -output-directory=tmp -interaction=nonstopmode $TEX_FILE.tex

# Move the Generated file and cleanup
cp tmp/$TEX_FILE.pdf .
rm -rf tmp

cd $CUR_DIR

