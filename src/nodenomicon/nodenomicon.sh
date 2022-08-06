#!/bin/bash

# ----- Defaults & Config -----------------------------------------------------

APP_ID="NodeNomicon"
APP_VERSION="0.7.9 beta"
APP_BANNER="$APP_ID $APP_VERSION"
APP_AUTHOR="Dex0r & Kaleb @ OpenBASH"
APP_DATETIME="2022-08-06"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# ----- Needed tools
TOOL_LIST=(awk basename curl cut date join jq mktemp nmap openssl shuf sort xargs) 

# ----- Parallelism config
OPTIMIZE_MULTIPROC_COUNT=4

# ----- nmap target distribution config defaults
NMAP_TARGETS=""
NMAP_TARGETS_FILE=""
NMAP_PORTS=""
NMAP_PARAMS="-sV -T4 -Pn --resolve-all"
WORKER_COUNT="1"
PROVIDER_CONF_DIR="/etc/nodenomicon"

# ----- Misc config
TORIFY_PARAM=""
WORKER_PARALLELISM="auto"
OPTIMIZE_DATA_GEN=false
DRY_RUN=false
WORKING_DIR_BASE="./work"
WORKING_DIR="$WORKING_DIR_BASE/scan_$( date "+%Y%m%d_%H%M%S" )"
MONITOR_QUEUE="$WORKING_DIR/monitor_queue.list"
OUTPUT_XML=""
OUTPUT_NMAP=""
OUTPUT_GNMAP=""
OUTPUT_QUEUE=""

# ----- Log prefix for tool
_XECHO_PREFIX="nodenomicon"

# ----- Process start time
PROCESS_STARTED_AT=$( date -Is )

# ----- Functions & External scripts ------------------------------------------
if [ ! -f $SCRIPT_DIR/libopenbash.inc ] ; then 
	echo "FATAL ERROR: OpenBASH function library not found." 
	exit 1
else 
	. $SCRIPT_DIR/libopenbash.inc	
fi

if [ ! -f $SCRIPT_DIR/nodenomicon_ow.sh ] ; then echo "FATAL ERROR: $SCRIPT_DIR/nodenomicon_ow.sh script not found." ; exit 1 ; fi
if [ ! -f $SCRIPT_DIR/nodenomicon_sw.sh ] ; then echo "FATAL ERROR: $SCRIPT_DIR/nodenomicon_sw.sh script not found." ; exit 1 ; fi

function app_banner
{
	xecho '--------------------------------------------------------------------------------'
	xecho ''
	xecho '           ▄  ████▄ ██▄  ▄███▄     ▄  ████▄ █▀▄▀█ ▄█ ▄█▄   ████▄   ▄'
	xecho '            █ █   █ █  █ █▀   ▀     █ █   █ █ █ █ ██ █▀ ▀▄ █   █    █'
	xecho '        ██   ██   █ █  █.██▄▄~~~██-._██ _.█-█~▄~█-██.█_  ▀ █   ███   █'
	xecho '        █ █  █▀████ █//█ █▄   ▄▀█ █  █▀████ █   █ ▐█ █▄\ ▄▀▀█████ █  █'
	xecho '        █  █ █      ███▀ ▀███▀  █  █ █|        █   ▐ ▀███▀      █  █ █'
	xecho '        █   ██     //           █   ██|       ▀         \\\\      █   ██'
	xecho '        █         //__...--~~~~~~-._  |  _.-~~~~~~--...__\\\\     █'
	xecho '         ▀       //__.....----~~~~._\ | /_.~~~~----.....__\\\\     ▀'
	xecho '                 ===================\\\\|//==================='
	xecho '                                    `---`'
	header "$APP_BANNER" "$APP_AUTHOR" "$APP_DATETIME"
	xecho ' Logo Art:'
	xecho '    Book: Donovan Bake'
	xecho '    Text: TextKool (textkool.com)'
	xecho '    Edit: Kaleb'
	xecho '--------------------------------------------------------------------------------'
	xecho ''
}

function call_for_help
{
	xecho "Usage:"
	xecho "  $0 -t 10.0.0.0/24 -p 1-100 -w 5 --optimize-data-gen"
	xecho "  $0 -t 10.0.0.0/24 -p top-10 -w 5 --optimize-data-gen"
	xecho "  $0 -c /etc/nodenomicon -t 'scanme.nmap.org' -p 80,443 -w 2 -d ./scan_output"
	xecho "  $0 -t 'scanme.nmap.org' -p 5900-5999 -w 4 --nmap-params '-n -sS -T5 -O -sC'"
	xecho "  $0 --config-pool /etc/nodenomicon/bigpool --targets-file scan_targets.txt -p 80,443 -w 2 -d ./scan_output --torify"
	xecho "  $0 --targets '10.0.0.0/28 10.0.0.100-200' --ports 1-100 --worker-count 5 --work-dir ./scan_output"
	xecho "  $0 -t '192.168.0.0/28' --ports top-100 --w 4 --xml-output /mnt/ssd_1/test_01.xml --nmap-output /mnt/ssd_2/nmap_output.nmap"
	xecho "  $0 -t 'scanme.nmap.org' --ports top-1000 --w 12 --gnmap-output /mnt/ssd_1/test_02.gnmap --queue-output /mnt/ssd_2/queue.json"
	xecho ""
	xecho "Help:"
	xecho "  -t, --targets EXPR    Specifies targets using same sintax as nmap. Use single quotes for multiple targets."
	xecho "  --targets-file FILE   Specifies targets using an input file. Must have one target per line."
	xecho "  -p, --ports EXPR      Specifies port range using same sintax as nmap. If the 'top-NNNN' sintax is used,"
	xecho "                        then the top-ports NNNN will be used to generate the scan targets (NNNN is a number"	
	xecho "                        between 1 and 65535)."	
	xecho "  -w, --workers NUMBER  Specifies to how many workers will the scan be distributed."
	xecho "  -c, --config-pool DIR Specifies a directory to pool the virtualization provider configurations. Will pick"
	xecho "                        a random .cfg file, and if no slots are available using that configuration, it will "
	xecho "                        'round-robin' through them. Defaults to '/etc/nodenomicon'."
	xecho "  -d, --work-dir DIR    Specifies the output working directory. Directory MUST BE EMPTY. If not specified,"
	xecho "                        a ./work/scan_NNN directory will be created."
	xecho "  -r, --parallel EXPR   Specifies how many workers (maximum) will be running in parallel (created and"
	xecho "                        monitored) to reduce api calls to VPS providers. Can be 'full', 'auto' or a positive"
	xecho "                        number. If 'full', a working node will be spawned for each work data; if 'auto',"
	xecho "                        sumatory of parameter 'max-node-count' from all of the configuration pool files will"
	xecho "                        be will be used. Defaults to 'auto'."
	xecho "  --nmap-params STRING  Specifies custom nmap parameters, enclosed with quotes. If ommited, the scan will be"
	xecho "                        done with '-sV -T4 -Pn --resolve-all'. Avoid using these parameters: -iL, -p, -oA."
	xecho "  --xml-output FILE     Makes a copy of output.xml (partial and final) to desired destination."
	xecho "  --nmap-output FILE    Makes a copy of output.nmap (partial and final) to desired destination."
	xecho "  --gnmap-output FILE   Makes a copy of output.gnmap (partial and final) to desired destination."
	xecho "  --queue-output FILE   Makes a copy of monitor queue to desired destination."
	xecho "  --torify              Specifies if tor network must be used to reach the nodes provider API."
	xecho "  --optimize-data-gen   When creating target & port working parameters, specifies to autodetect cpu core count"
	xecho "                        for parallel tasks."
	xecho "  --dry-run             Only generates workers data, but do not run the distrubuted scan."
	xecho "  -h, --help            This help."
	xecho ""
}

# -----------------------------------------------------------------------------
# ----- Entry Point -----------------------------------------------------------
# -----------------------------------------------------------------------------

app_banner

# ----- Parameter control -----------------------------------------------------

while [ "$1" != "" ]; do
	case $1 in
		-t | --targets)      shift; NMAP_TARGETS=$1 ;;
		--targets-file)      shift; NMAP_TARGETS_FILE=$1 ;;
		-p | --ports)        shift; NMAP_PORTS=$1 ;;
		-c | --config-pool)  shift; PROVIDER_CONF_DIR=$1 ;;
		--nmap-params)       shift; NMAP_PARAMS=$1 ;;
		-w | --workers)      shift; WORKER_COUNT=$1 ;;
		-d | --work-dir)     shift; WORKING_DIR=$1 ;;
		-r | --parallel)     shift; WORKER_PARALLELISM=$1 ;;
		--copy-output)		 shift; COPY_OUTPUT_XML=$1 ;;
		--copy-queue)		 shift; COPY_MONITOR_QUEUE=$1 ;;
		--xml-output)		 shift; OUTPUT_XML=$1 ;;
		--nmap-output)		 shift; OUTPUT_NMAP=$1 ;;
		--gnmap-output)		 shift; OUTPUT_GNMAP=$1 ;;
		--queue-output)		 shift; OUTPUT_QUEUE=$1 ;;
		--torify)            TORIFY_PARAM="--torify" ;;
		--optimize-data-gen) OPTIMIZE_DATA_GEN=true ;;
		--dry-run)           DRY_RUN=true ;;			
		* ) 			
			call_for_help
			free_resources $TMP_LOG $TMP_NMAP_OUTPUT $TMP_TARGETS $TMP_PORTS $TMP_FULL_TARGET 
			exit 1
	esac
	shift
done

FLAG_ERROR_PARAMS=false

[[ "$NMAP_TARGETS" == "" && "${NMAP_TARGETS_FILE}" == "" ]] && { xecho "ERROR: Must specify targets."; FLAG_ERROR_PARAMS=true; }
[[ "${NMAP_TARGETS_FILE}" != "" && ! -f "${NMAP_TARGETS_FILE}" ]] && { xecho "ERROR: Target file '${NMAP_TARGETS_FILE}' does not exists."; FLAG_ERROR_PARAMS=true; }
[[ "$NMAP_PORTS" == "" ]] && { xecho "ERROR: Must specify ports."; FLAG_ERROR_PARAMS=true; }
[[ "$NMAP_PARAMS" == "" ]] && { xecho "ERROR: Must specify nmap parameters."; FLAG_ERROR_PARAMS=true; }
[[ "$WORKER_COUNT" == "" ]] && { xecho "ERROR: Must specify workers."; FLAG_ERROR_PARAMS=true; }
if [ ! -d "$PROVIDER_CONF_DIR" ] ; then
	xecho "ERROR: Provider configuration directory does not exists."
	FLAG_ERROR_PARAMS=true
else
	[[ "$( find $PROVIDER_CONF_DIR -maxdepth 1 -name '*.cfg' -type f )" == "" ]] && { xecho "ERROR: No provider configuration files found at '$PROVIDER_CONF_DIR'."; FLAG_ERROR_PARAMS=true; }
fi

[[ "$( echo $WORKER_PARALLELISM | grep -P '^(auto|full|[0-9]+)$' )" == "" ]] && { xecho "ERROR: Invalid value for parallelism parameter."; FLAG_ERROR_PARAMS=true; }

[[ "$OUTPUT_XML" != "" && ! -d "$( dirname ${OUTPUT_XML} )" ]] && { xecho "ERROR: XML output file destination directory do not exists."; FLAG_ERROR_PARAMS=true; }
[[ "$OUTPUT_NMAP" != "" && ! -d "$( dirname ${OUTPUT_NMAP} )" ]] && { xecho "ERROR: NMAP output file destination directory do not exists."; FLAG_ERROR_PARAMS=true; }
[[ "$OUTPUT_GNMAP" != "" && ! -d "$( dirname ${OUTPUT_GNMAP} )" ]] && { xecho "ERROR: GNMAP output file destination directory do not exists."; FLAG_ERROR_PARAMS=true; }
[[ "$OUTPUT_QUEUE" != "" && ! -d "$( dirname ${OUTPUT_QUEUE} )" ]] && { xecho "ERROR: QUEUE output file destination directory do not exists."; FLAG_ERROR_PARAMS=true; }

if [ "$FLAG_ERROR_PARAMS" == true ] ; then
	xecho "" 
	call_for_help
	free_resources $TMP_LOG $TMP_NMAP_OUTPUT $TMP_TARGETS $TMP_PORTS $TMP_FULL_TARGET 
	exit 1 
fi


# ----- Process start ---------------------------------------------------------

# ----- OpenBASH integration
if [ ! -z "$ID_APLICACION" ] ; then
	OPENBASH_ID_APP="$ID_APLICACION"
	OPENBASH_PATH_NODES="/opt/tmp/$ID_APLICACION.nodes"
fi

# ----- Enviroment control 
xecho "Checking for tools..."
FLAG_MISSING_TOOL=false
for t in "${TOOL_LIST[@]}"; do 
	toolpath=$( command -v $t )
	if [ "$toolpath" == "" ] ; then
		FLAG_MISSING_TOOL=true
		xecho "  WARNING: '$t' not found!"
	else
		xecho "  '$t' found at $toolpath"
	fi
done
if [ "$FLAG_MISSING_TOOL" == true ] ; then
	xecho "ERROR: cannot find needed tools. Try with 'apt install <tool name>'."
	free_resources $TMP_LOG $TMP_NMAP_OUTPUT $TMP_TARGETS $TMP_PORTS $TMP_FULL_TARGET 
	exit 1
fi
xecho ""

# ----- Optimize data generation (Auto CPU usage)
if [ "$OPTIMIZE_DATA_GEN" == true ] ; then
	xecho "Using auto CPU usage mode for data generation. Trying to get CPU core count..."
	CPU_COUNT=$( cat /proc/cpuinfo | grep -Pi '^cpu cores' | sort -u | sed -r 's/^[^0-9]+//g' )
	if [ "$CPU_COUNT" != "" ] ; then 
		xecho "Found $CPU_COUNT CPU cores. Optimizing parallelism parameters for data generation..."
		OPTIMIZE_MULTIPROC_COUNT="$CPU_COUNT"
	else
		xecho "Cannot determine CPU core count. Falling back to defaults..."
	fi
	xecho ""
fi

# ----- Work folder
# Create if not exists, otherwise, check if it is empty.

if [ ! -d $WORKING_DIR ] ; then
	xecho "  Creating work folder at $WORKING_DIR ..."
	mkdir -p $WORKING_DIR
	if [ ! -d $WORKING_DIR ] ; then xecho "ERROR: cannot create working directory at $WORKING_DIR" ; exit 1 ; fi
else
	xecho "  Work folder $WORKING_DIR already exists..."
	if [ "$(ls -A $WORKING_DIR)" != "" ]; then xecho "ERROR: $WORKING_DIR must be empty!" ; exit 1 ; fi
fi
MONITOR_QUEUE="$WORKING_DIR/monitor_queue.json"

# ----- Dump parameters

xecho "Parameters:"
xecho "  NMAP_TARGETS              = $NMAP_TARGETS"
xecho "  NMAP_TARGETS_FILE         = ${NMAP_TARGETS_FILE}"
xecho "  NMAP_PORTS                = $NMAP_PORTS"
xecho "  NMAP_PARAMS               = $NMAP_PARAMS"
xecho "  WORKER_COUNT              = $WORKER_COUNT"
xecho "  WORKER_PARALLELISM        = $WORKER_PARALLELISM"
xecho "  PROVIDER_CONF_DIR         = $PROVIDER_CONF_DIR"
xecho "  WORKING_DIR               = $WORKING_DIR"
xecho "  TORIFY_PARAM              = $TORIFY_PARAM"
xecho "  OPTIMIZE_DATA_GEN         = $OPTIMIZE_DATA_GEN"
xecho "  DRY_RUN                   = $DRY_RUN"
xecho "  OPTIMIZE_MULTIPROC_COUNT  = $OPTIMIZE_MULTIPROC_COUNT"
xecho "  MONITOR_QUEUE             = $MONITOR_QUEUE"
[[ "$OUTPUT_XML" != "" ]]   && xecho "  OUTPUT_XML                = $OUTPUT_XML"
[[ "$OUTPUT_NMAP" != "" ]]  && xecho "  OUTPUT_NMAP               = $OUTPUT_NMAP"
[[ "$OUTPUT_GNMAP" != "" ]] && xecho "  OUTPUT_GNMAP              = $OUTPUT_GNMAP"
[[ "$OUTPUT_QUEUE" != "" ]] && xecho "  OUTPUT_QUEUE              = $OUTPUT_QUEUE"
[ ! -z "$OPENBASH_ID_APP" ] && xecho "  OPENBASH_ID_APP           = $OPENBASH_ID_APP"
xecho ""

xecho "Generating task data for workers..."

# ----- Generate target list 

xecho "  Generating target list..."
TMP_NMAP_OUTPUT=$( mktemp )
TMP_TARGETS=$( mktemp )

if [ "$NMAP_TARGETS" != "" ] ; then 
	nmap -n -sL $NMAP_TARGETS -oG $TMP_NMAP_OUTPUT > /dev/null
	grep -P '^Host: [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' $TMP_NMAP_OUTPUT | cut -d' ' -f2 | sort -u --output=$TMP_TARGETS
fi

if [ "${NMAP_TARGETS_FILE}" != "" ] ; then 
	tmp_join_targets=$( mktemp )
	xecho "  Found '${NMAP_TARGETS_FILE}'. Adding $( count_lines ${NMAP_TARGETS_FILE} ) targets to target list..."
	cat $TMP_TARGETS ${NMAP_TARGETS_FILE} >> $tmp_join_targets
	sort -u --output=$TMP_TARGETS $tmp_join_targets
	[[ -f $tmp_join_targets ]] && rm $tmp_join_targets
fi

xecho "    $( count_lines $TMP_TARGETS ) targets found."
xecho "    Saving target list to '$WORKING_DIR/targets.list' ..."
cp $TMP_TARGETS $WORKING_DIR/targets.list

# ----- Generate port list

xecho "  Generating port list..."

if [ "$( echo $NMAP_PORTS | grep -Po '^top-')" == "top-" ] ; then
	xecho "    Getting 'top-ports' from nmap..."
	top_ports_count=$( echo $NMAP_PORTS | sed -r 's/^top-//g' )
	NMAP_PORTS=$( nmap --top-ports $top_ports_count localhost -v -oG - | grep -Po 'TCP\([^\)]+' | cut -d ';' -f 2 )
	xecho "    Selected ports: $NMAP_PORTS"
fi

TMP_PORTS=$( mktemp )
OLDIFS=$IFS
IFS=',' read -ra PORTS <<< "$NMAP_PORTS"
for port in "${PORTS[@]}"; do

	# --- check for single port
	port_single=$( echo $port | grep -P '^[0-9]+$' )
	if [ "$port_single" != "" ] ; then
		xecho "    Found port: $port_single"
		echo $port_single >> $TMP_PORTS
	fi
    
    # --- check for port range
    port_range=$( echo $port | grep -P '^[0-9]+-[0-9]+$' )
    if [ "$port_range" != "" ] ; then
		port_range_from=$( echo $port_range | cut -d'-' -f1 )
		port_range_to=$( echo $port_range | cut -d'-' -f2 )
		xecho "    Found port range: from $port_range_from to $port_range_to"
		seq $port_range_from $port_range_to >> $TMP_PORTS
	fi
done
IFS=$OLDIFS

xecho "    Removing duplicated ports..."
sort -u --output=$TMP_PORTS $TMP_PORTS

xecho "    $( cat $TMP_PORTS | wc -l) ports found."
xecho "    Saving port list to '$WORKING_DIR/ports.list' ..."
cp $TMP_PORTS $WORKING_DIR/ports.list

# ----- 'Cartesian product' of targets & ports, then shuffle results
xecho "  Joining & shuffling targets and ports..."
TMP_FULL_TARGET=$( mktemp )
join -j 2 $TMP_TARGETS $TMP_PORTS | shuf --output=$TMP_FULL_TARGET

# ----- Divide results among workers
xecho "  Spliting results into $WORKER_COUNT workers (using $OPTIMIZE_MULTIPROC_COUNT parallel processes)..."
curr_dir=$( pwd )
cd $WORKING_DIR
split --additional-suffix=-worker --suffix-length=5 --numeric-suffixes=1 --elide-empty-files --number=l/$WORKER_COUNT $TMP_FULL_TARGET
cd $curr_dir

find $WORKING_DIR -maxdepth 1 -name 'x*-worker' -type f | xargs --max-lines=1 --no-run-if-empty -P $OPTIMIZE_MULTIPROC_COUNT $SCRIPT_DIR/nodenomicon_ow.sh --work-dir $WORKING_DIR --file 

xecho "...done! Check work distribution at $WORKING_DIR."
xecho ""

# ----- Check for 'dry run'
if [ "$DRY_RUN" == true ] ; then
	xecho "Running in DRY MODE. Skipping distributed scan..."
	xecho ""
	free_resources $TMP_LOG $TMP_NMAP_OUTPUT $TMP_TARGETS $TMP_PORTS $TMP_FULL_TARGET 
	exit 0
fi

# ----- Distribute work data into VM nodes and start monitoring
node_prefix="node-$( openssl rand -hex 8 )"
tmp_work_files=$( mktemp )
find $WORKING_DIR -name 'worker-*.data' -type f > $tmp_work_files

# pre-create monitor queue file
xecho "Creating monitor queue file..."
createQueueFile "$MONITOR_QUEUE" "$node_prefix" "$( cat $tmp_work_files | wc -l )" "$PROCESS_STARTED_AT"

# Determine proc count based on WORKER_PARALLELISM configuration
parallel_mode=""
if [ "$WORKER_PARALLELISM" == 'auto' ] ; then 
	parallel_mode="auto"
	proc_count=0
	for provider_cfg in $( find $PROVIDER_CONF_DIR -maxdepth 1 -name '*.cfg' -type f ) ; do
		max_node_count=$( get_param $provider_cfg max-node-count 0 )
		let "proc_count+=$max_node_count"
	done
	[[ "$proc_count" -eq 0 ]] && proc_count=1
else
	if [ "$WORKER_PARALLELISM" == 'full' ] ; then 
		parallel_mode="full"
		proc_count=$( count_lines $tmp_work_files )
	else
		parallel_mode="manual"
		proc_count="$WORKER_PARALLELISM"
	fi
fi

xecho "Distributing work into VM worker nodes, using $proc_count parallel processes (parallelism mode: $parallel_mode)..."

MORE_OUTPUT_PARAMS=""
[[ "$OUTPUT_XML" != "" ]]   && MORE_OUTPUT_PARAMS="$MORE_OUTPUT_PARAMS --xml-output $OUTPUT_XML"
[[ "$OUTPUT_NMAP" != "" ]]  && MORE_OUTPUT_PARAMS="$MORE_OUTPUT_PARAMS --nmap-output $OUTPUT_NMAP"
[[ "$OUTPUT_GNMAP" != "" ]] && MORE_OUTPUT_PARAMS="$MORE_OUTPUT_PARAMS --gnmap-output $OUTPUT_GNMAP"
[[ "$OUTPUT_QUEUE" != "" ]] && MORE_OUTPUT_PARAMS="$MORE_OUTPUT_PARAMS --queue-output $OUTPUT_QUEUE"

cat $tmp_work_files \
	| xargs --max-lines=1 --no-run-if-empty -P $proc_count \
		$SCRIPT_DIR/nodenomicon_sw.sh $TORIFY_PARAM $MORE_OUTPUT_PARAMS --config-pool "$PROVIDER_CONF_DIR" --monitor-queue $MONITOR_QUEUE --work-dir $WORKING_DIR --node-prefix $node_prefix --nmap-params "$NMAP_PARAMS" --file 

[[ -f $tmp_work_files ]] && rm $tmp_work_files

xecho "All nodes finished."

# ----- Convert output & copy optional duplicates
NMAP_MERGER="$SCRIPT_DIR/external/nMap_Merger/nMapMerge.py"
if [ -f $NMAP_MERGER ] ; then
	xecho "Removing partial NMAP XML output..."
	[[ -f $WORKING_DIR/output/output.xml ]] && rm $WORKING_DIR/output/output.xml
	xecho "Merging NMAP XML output into one file..."
	merged_output=$( $NMAP_MERGER --dir $WORKING_DIR/output/ --quiet )
	if [ "$merged_output" != "" ] && [ -f "$merged_output" ] ; then
		mv $merged_output $WORKING_DIR/output/output.xml
		xecho "NMAP XML output in '$WORKING_DIR/output/output.xml'"
	else
		xecho "Cannot merge XML output; missing merged output file."
	fi
else
	xecho "Cannot merge XML output; missing nMapMerge."
fi
if [ "$OUTPUT_XML" != "" ] ; then
	xecho "Copying NMAP XML output to '$OUTPUT_XML'..."
	cp $WORKING_DIR/output/output.xml $OUTPUT_XML
fi

xecho "Removing partial NMAP output..."
[[ -f $WORKING_DIR/output/output.nmap ]] && rm $WORKING_DIR/output/output.nmap
xecho "Merging NMAP output into one file..."
cat $WORKING_DIR/output/*.nmap > $WORKING_DIR/output/output.nmap
xecho "NMAP output in '$WORKING_DIR/output/output.nmap'"
if [ "$OUTPUT_NMAP" != "" ] ; then
	xecho "Copying NMAP output to '$OUTPUT_NMAP'..."
	cp $WORKING_DIR/output/output.nmap $OUTPUT_NMAP
fi

xecho "Removing partial GNMAP output..."
[[ -f $WORKING_DIR/output/output.gnmap ]] && rm $WORKING_DIR/output/output.gnmap
xecho "Merging GNMAP output into one file..."
cat $WORKING_DIR/output/*.gnmap > $WORKING_DIR/output/output.gnmap
xecho "GNMAP output in '$WORKING_DIR/output/output.gnmap'"
if [ "$OUTPUT_GNMAP" != "" ] ; then
	xecho "Copying GNMAP output to '$OUTPUT_GNMAP'..."
	cp $WORKING_DIR/output/output.gnmap $OUTPUT_GNMAP
fi

xecho ""
# ----- Last error checking
if [ -f $WORKING_DIR/error.log ] ; then
	xecho "There was some errors. Check $WORKING_DIR/error.log"
	free_resources $TMP_LOG $TMP_NMAP_OUTPUT $TMP_TARGETS $TMP_PORTS $TMP_FULL_TARGET 
	exit 1
fi

# ----- Finish process
free_resources $TMP_LOG $TMP_NMAP_OUTPUT $TMP_TARGETS $TMP_PORTS $TMP_FULL_TARGET 
