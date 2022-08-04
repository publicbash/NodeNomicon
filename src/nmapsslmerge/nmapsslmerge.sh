#!/bin/bash

# ----- Defaults & Config -----------------------------------------------------

APP_ID="NMapSSLMerge"
APP_VERSION="0.0.2 beta"
APP_BANNER="$APP_ID $APP_VERSION"
APP_AUTHOR="Dex0r & Kaleb @ OpenBASH"
APP_DATETIME="2022-08-04"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# ----- Needed tools
TOOL_LIST=(awk head sort tempfile xmlstarlet) 

# ----- Log prefix for tool
_XECHO_PREFIX="nmapsslmerge"

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
	xecho "  $0 -i nmap_output.xml -o merged_output.csv"
	xecho "  $0 --input nmap_output.xml --output merged_output.csv"
	xecho ""
	xecho "Help:"
	xecho "  -i, --input FILE   Specifies the nmap output xml file to be parsed."
	xecho "  -o, --output FILE  Specifies the csv output file. If not specified, 'output.csv' will be used."
	xecho "  -h, --help         This help."
	xecho ""
}

# -----------------------------------------------------------------------------
# ----- Entry Point -----------------------------------------------------------
# -----------------------------------------------------------------------------

# ----- Parameter control -----------------------------------------------------
TMP_OUTPUT=$( tempfile )
XML_INPUT=""
CSV_OUTPUT="./output.csv"

while [ "$1" != "" ]; do
	case $1 in
		-i | --input)  shift; XML_INPUT=$1 ;;
		-o | --output) shift; CSV_OUTPUT=$1 ;;
		* ) 			
			call_for_help
			free_resources $TMP_LOG $TMP_OUTPUT
			exit 1
	esac
	shift
done

ERROR_MSG=""
[[ "$XML_INPUT" == "" ]] && ERROR_MSG="${ERROR_MSG}; ERROR: Must specify input xml file."
[[ ! -f "$XML_INPUT"  ]] && ERROR_MSG="${ERROR_MSG}; ERROR: Input file not found."

if [ "$ERROR_MSG" != "" ] ; then
	header "$APP_BANNER" "$APP_AUTHOR" "$APP_DATETIME"
	xecho "$ERROR_MSG"
	xecho "" 
	call_for_help
	free_resources $TMP_LOG $TMP_NMAP_OUTPUT $TMP_TARGETS $TMP_PORTS $TMP_FULL_TARGET 
	exit 1 
fi

# ----- Enviroment control 
FLAG_MISSING_TOOL=false
for t in "${TOOL_LIST[@]}"; do 
	toolpath=$( command -v $t )
	if [ "$toolpath" == "" ] ; then
		FLAG_MISSING_TOOL=true
		xecho "  WARNING: '$t' not found!"
	fi
done
if [ "$FLAG_MISSING_TOOL" == true ] ; then
	xecho "ERROR: cannot find needed tools. Try with 'apt install <tool name>'."
	free_resources $TMP_LOG $TMP_NMAP_OUTPUT $TMP_TARGETS $TMP_PORTS $TMP_FULL_TARGET 
	exit 1
fi

# ----- Process start ---------------------------------------------------------
# Content
xmlstarlet select --template \
		--match "/nmaprun/host/ports/port/script/table/table[@key='ciphers']/table" \
			--value-of "ancestor::host[1]/address/@addr" \
			--output "," \
			--value-of "ancestor::port[1]/@portid" \
			--output "," \
			--value-of "ancestor::table[2]/@key" \
			--output "," \
			--value-of "elem[@key='strength']" \
			--output ":" \
			--value-of "elem[@key='name']" \
		--nl \
		$XML_INPUT | \
	awk -F':' '{ data[$1] = (data[$1] == "" ? $2 : data[$1] " " $2) } END { for (key in data) print key","data[key] }' | \
	sort -u >> $TMP_OUTPUT

# Header
echo "ip,Port,SSLv2,SSLv3,TLSv10,TLSv11,TLSv12,TLSv13,cipher,action,status" > $CSV_OUTPUT

# Control group results
group_ip_port=$( head -n 1 $TMP_OUTPUT | cut -d',' -f1,2 )
ip_port=""
has_sslv2=""
has_sslv3=""
has_tlsv10=""
has_tlsv11=""
has_tlsv12=""
has_tlsv13=""
ciphers=""
status=""

OLDIFS=$IFS
IFS=$'\n'
for data in $( cat $TMP_OUTPUT ) ; do
	ip_port=$( echo $data | cut -d',' -f1,2 )
	curr_protocol=$( echo $data | cut -d',' -f3 )
	curr_status=$( echo $data | cut -d',' -f4 )
	curr_ciphers=$( echo $data | cut -d',' -f5 )
	if [ "$ip_port" != "$group_ip_port" ] ; then
		[[ "$status" != "" && "$status" != "A" ]] && status="FAIL" || status="PASS"
		if [ "$status" == "PASS" ] ; then
			ciphers=""
		else
			if [ "$has_sslv2" == "Yes" ] || [ "$has_sslv3" == "Yes" ] || [ "$has_tlsv10" == "Yes" ] || [ "$has_tlsv11 " == "Yes" ] ; then
				ciphers=""
			else
				ciphers=$( echo "$ciphers" | tr ' ' '\n' | sort -u | sed -r '/^\s*$/d' | tr '\n' ' ' | sed -r 's/\s*$//g' )
			fi
		fi
		echo "$ip_port,$has_sslv2,$has_sslv3,$has_tlsv10,$has_tlsv11,$has_tlsv12,$has_tlsv13,$ciphers,,$status" >> $CSV_OUTPUT
		group_ip_port="$ip_port"
		has_sslv2=""
		has_sslv3=""
		has_tlsv10=""
		has_tlsv11=""
		has_tlsv12=""
		has_tlsv13=""
		ciphers=""
		status=""
	fi
	[[ "$curr_protocol" == "SSLv2"   ]] && { has_sslv2="Yes" ; status="F" ; }
	[[ "$curr_protocol" == "SSLv3"   ]] && { has_sslv3="Yes" ; status="F" ; }
	[[ "$curr_protocol" == "TLSv1.0" ]] && { has_tlsv10="Yes" ; status="F" ; }
	[[ "$curr_protocol" == "TLSv1.1" ]] && { has_tlsv11="Yes" ; status="F" ; }
	[[ "$curr_protocol" == "TLSv1.2" ]] && has_tlsv12="Yes"
	[[ "$curr_protocol" == "TLSv1.3" ]] && has_tlsv13="Yes"
	[[ "$curr_protocol" == "TLSv1.3" ]] && has_tlsv13="Yes"
	[[ "$curr_status" > "$status" ]] && status="$curr_status"
	ciphers="${ciphers} $curr_ciphers"
done
IFS=$OLDIFS

# Save last group
[[ "$status" != "" && "$status" != "A" ]] && status="FAIL" || status="PASS"
if [ "$status" == "PASS" ] ; then
	ciphers=""
else
	if [ "$has_sslv2" == "Yes" ] || [ "$has_sslv3" == "Yes" ] || [ "$has_tlsv10" == "Yes" ] || [ "$has_tlsv11 " == "Yes" ] ; then
		ciphers=""
	else
		ciphers=$( echo "$ciphers" | tr ' ' '\n' | sort -u | sed -r '/^\s*$/d' | tr '\n' ' ' | sed -r 's/\s*$//g' )
	fi
fi
echo "$ip_port,$has_sslv2,$has_sslv3,$has_tlsv10,$has_tlsv11,$has_tlsv12,$has_tlsv13,$ciphers,,$status" >> $CSV_OUTPUT

# Remove temp files
[[ -f $TMP_OUTPUT ]] && rm $TMP_OUTPUT