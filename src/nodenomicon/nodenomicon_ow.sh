#!/bin/bash

# ----- Defaults & Config -----------------------------------------------------

APP_ID="NodeNomicon OptimizeWorkData"
APP_VERSION="0.0.3 beta"
APP_BANNER="$APP_ID $APP_VERSION"
APP_AUTHOR="Kaleb @ OpenBASH"
APP_DATETIME="2022-08-04"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# ----- parameters defaults
WORKING_DIR=""
INPUT_FILE=""

# ----- Log prefix for tool
_XECHO_PREFIX="nodenomicon_ow"

# ----- Functions & External scripts ------------------------------------------
if [ ! -f $SCRIPT_DIR/libopenbash.inc ] ; then 
	echo "FATAL ERROR: OpenBASH function library not found." 
	exit 1
else 
	. $SCRIPT_DIR/libopenbash.inc	
fi

function call_for_help
{
	xecho "Usage:"
	xecho "  $0 -d ./work -f worker-00001.data"
	xecho "  $0 --work-dir ./work --file worker-00001.data"
	xecho ""
	xecho "Help:"
	xecho "  -d, --work-dir STRING  Specifies the working directory."
	xecho "  -f, --file STRING      Specifies the input data file. Input file must have format like worker-N.data, where N is the worker id with leading zeros."
	xecho "  -h, --help             This help."
	xecho ""
}

# -----------------------------------------------------------------------------
# ----- Entry Point -----------------------------------------------------------
# -----------------------------------------------------------------------------

# ----- Parameter control -----------------------------------------------------
while [ "$1" != "" ]; do
	case $1 in
		-d | --work-dir) shift; WORKING_DIR=$1 ;;
		-f | --file)     shift; INPUT_FILE=$1 ;;
		* ) 			 call_for_help; exit 1
	esac
	shift
done

FLAG_ERROR_PARAMS=false

if [ "$WORKING_DIR" == "" ] ;  then xecho "ERROR: Must specify working directory."   ; FLAG_ERROR_PARAMS=true ; fi
if [ "$INPUT_FILE" == "" ] ;   then xecho "ERROR: Must specify input data file."     ; FLAG_ERROR_PARAMS=true ; fi
WORKER_ID=$( basename $INPUT_FILE | sed -r 's/x([0-9]+)-worker/\1/g' )
if [ "$WORKER_ID" == "" ] ;    then xecho "ERROR: Invalid name for input data file." ; FLAG_ERROR_PARAMS=true ; fi

if [ "$FLAG_ERROR_PARAMS" == true ] ; then
	xecho "" 
	call_for_help
	exit 1 
fi

# ----- Process start ---------------------------------------------------------

target=$( echo $INPUT_FILE | sed -r 's/x([0-9]+)-worker/worker-\1.data/g' )
tmp_byport=$( tempfile )
tmp_bytarget=$( tempfile )
tmp_byboth=$( tempfile )

sort -u -k1,1 -k2,2 --output=$INPUT_FILE $INPUT_FILE
hostcount=$( awk '{ print $1 }' $INPUT_FILE | sort -u | wc -l )
portcount=$( awk '{ print $2 }' $INPUT_FILE | sort -u | wc -l )
xecho "Worker $WORKER_ID: Raw output to $target ($hostcount hosts, $portcount ports, $( count_lines $INPUT_FILE ) possible raw scans). Optimizing..."

awk '{ g[$1] = (g[$1] == "" ? $2 : g[$1] "," $2) } END { for (k in g) print k,g[k] }' $INPUT_FILE | sort -u -k1,1 -k2,2 > $tmp_byport
count_byport=$( count_lines $tmp_byport )

awk '{ g[$2] = (g[$2] == "" ? $1 : g[$2] "," $1) } END { for (k in g) print g[k],k }' $INPUT_FILE | sort -u -k1,1 -k2,2 > $tmp_bytarget
count_bytarget=$( count_lines $tmp_bytarget )

cat $tmp_byport | awk '{ g[$2] = (g[$2] == "" ? $1 : g[$2] "," $1) } END { for (k in g) print g[k],k }' | sort -u -k1,1 -k2,2 > $tmp_byboth
count_byboth=$( count_lines $tmp_byboth )

xecho "Worker $WORKER_ID: Scans by group > $count_byport by ports, $count_bytarget by targets, $count_byboth by both"

min_count=$( min $count_byport $count_bytarget $count_byboth )

selected_output=$( tempfile )
if [ "$count_byport" -eq "$min_count" ] ; then
	mv $tmp_byport $selected_output
	xecho "Worker $WORKER_ID: Keeping grouped ports scan."
elif [ "$count_bytarget" -eq "$min_count" ] ; then
	mv $tmp_bytarget $selected_output
	xecho "Worker $WORKER_ID: Keeping grouped targets scan."
else
	mv $tmp_byboth $selected_output
	xecho "Worker $WORKER_ID: Keeping grouped by both scan."
fi

xecho "Worker $WORKER_ID: Grouping ports as intervals..."
OLDIFS=$IFS
while IFS= read -r line; do
	f_hosts=$( echo $line | cut -d' ' -f1 )
	f_ports=$( echo $line | cut -d' ' -f2 | tr ',' '\n' | sort --numeric-sort | awk 'function output() { print start (prev == start ? "" : "-"prev) } NR == 1 {start = prev = $1; next} $1 > prev+1 {output(); start = $1} {prev = $1} END {output()}' | tr '\n' ',' | sed 's/,$//g')
	echo "$f_hosts $f_ports" >> $target
done < $selected_output
IFS=$OLDIFS

if [ -f $tmp_byport ] ; then rm $tmp_byport ; fi
if [ -f $tmp_bytarget ] ; then rm $tmp_bytarget ; fi
if [ -f $tmp_byboth ] ; then rm $tmp_byboth ; fi
rm $INPUT_FILE