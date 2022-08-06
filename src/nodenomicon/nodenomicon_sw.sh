#!/bin/bash

# ----- Defaults & Config -----------------------------------------------------

APP_ID="NodeNomicon StartWorker"
APP_VERSION="0.2.20 beta"
APP_BANNER="$APP_ID $APP_VERSION"
APP_AUTHOR="Kaleb @ OpenBASH"
APP_DATETIME="2022-08-06"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
NMAP_MERGER="$SCRIPT_DIR/external/nMap_Merger/nMapMerge.py"

# ----- Log prefix for tool
_XECHO_PREFIX="nodenomicon_sw"

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
	xecho "  $0 -c /etc/nodenomicon -q /tmp/monitor_queue.list -d ./work -n testing -f worker-00001.data"
	xecho "  $0 --config-pool /etc/nodenomicon --monitor-queue /tmp/monitor_queue.list --work-dir ./work --node-prefix testing --file worker-00001.data"
	xecho ""
	xecho "Help:"
	xecho "  -c, --config-pool DIR     Specifies a directory to pool the virtualization provider configurations. Will pick"
	xecho "                            a random .cfg file, and if no slots are available using that configuration, it will "
	xecho "                            'round-robin' through them. Defaults to '/etc/nodenomicon'."
	xecho "  -q, --monitor-queue FILE  Specifies the monitor queue where the node will be added."
	xecho "  -d, --work-dir STRING     Specifies the working directory."
	xecho "  -n, --node-prefix STRING  Specifies a prefix for node naming convention."
	xecho "  -f, --file STRING         Specifies the input data file. Input file must have format like worker-N.data, where N is the worker id with leading zeros."
	xecho "  --nmap-params STRING      Specifies custon nmap parameters, enclosed with quotes. If ommited, the scan will be"
	xecho "                            done with '-sV -T4 -Pn --resolve-all'. Avoid using these parameters: -iL, -p, -oA."
	xecho "  --xml-output FILE         Makes a copy of output.xml (partial and final) to desired destination."
	xecho "  --nmap-output FILE        Makes a copy of output.nmap (partial and final) to desired destination."
	xecho "  --gnmap-output FILE       Makes a copy of output.gnmap (partial and final) to desired destination."
	xecho "  --queue-output FILE       Makes a copy of monitor queue to desired destination."
	xecho "  --torify                  Specifies if tor network must be used to reach the nodes provider API."
	xecho "  -h, --help                This help."
	xecho ""
}

function update_monitor_queue
{
	local n_status="$1"
	local status_timestamp=$( date -Is )
	local in_queue

	# ----- CRITICAL SECTION START --------------------------------------------
	# Only one process at a time can update monitor queue (to prevent parallelism race conditions and get accurate results)
	eval "exec $LOCK_FD>$LOCK_FILE"
	flock --exclusive "$LOCK_FD" || { xecho "$NODE_LABEL: ERROR: 'flock' failed (LOCK_FILE: '$LOCK_FILE', LOCK_FD: '$LOCK_FD'." ; exit 1 ; }
 
	# Add node to monitor queue, in JSON
	[[ ! -f $MONITOR_QUEUE ]] && { echo '{"started_at":"'"$status_timestamp"'","queue":[]}' > $MONITOR_QUEUE ; }
	in_queue=$( jq -c --arg nlabel $NODE_LABEL '.queue[] | select(.label == $nlabel)' $MONITOR_QUEUE )
	if [ "$in_queue" == "" ] ; then
		# Add element if not found
		cat <<< $( jq --arg nlabel $NODE_LABEL \
			--arg nstatus $n_status \
			--arg nipv4 $NODE_IPV4 \
			--arg nregion $NODE_REGION \
			--arg ntimestamp $status_timestamp \
			'.queue[.queue|length] |= {"label":$nlabel,"status":$nstatus,"ipv4":$nipv4,"region":$nregion,"timestamp":$ntimestamp}' \
			$MONITOR_QUEUE ) > $MONITOR_QUEUE
	else
		# Update found element
		cat <<< $( jq --arg nlabel $NODE_LABEL --arg nstatus $n_status '(.queue[] | select(.label == $nlabel) | .status) |= $nstatus' $MONITOR_QUEUE ) > $MONITOR_QUEUE
		cat <<< $( jq --arg nlabel $NODE_LABEL --arg nipv4 $NODE_IPV4 '(.queue[] | select(.label == $nlabel) | .ipv4) |= $nipv4' $MONITOR_QUEUE ) > $MONITOR_QUEUE
		cat <<< $( jq --arg nlabel $NODE_LABEL --arg nregion $NODE_REGION '(.queue[] | select(.label == $nlabel) | .region) |= $nregion' $MONITOR_QUEUE ) > $MONITOR_QUEUE
		cat <<< $( jq --arg nlabel $NODE_LABEL --arg ntimestamp $status_timestamp '(.queue[] | select(.label == $nlabel) | .timestamp) |= $ntimestamp' $MONITOR_QUEUE ) > $MONITOR_QUEUE
	fi

	# Old format
	# jq -r '.queue[] | .label + " = " + .status' $MONITOR_QUEUE > monitor_queue.list

	if [ "$OUTPUT_QUEUE" != "" ] ; then
		xecho "Copying monitor queue output to '$OUTPUT_QUEUE'..."
		cp $MONITOR_QUEUE $OUTPUT_QUEUE
	fi

	# release lock
	flock --unlock "$LOCK_FD"
	# ----- CRITICAL SECTION END ----------------------------------------------	
}

function generate_partial_output
{
	local tmp_output_dir merged_output

	# ----- CRITICAL SECTION START --------------------------------------------
	# Only one process at a time can update monitor queue (to prevent parallelism race conditions and get accurate results)
	eval "exec $LOCK_FD>$LOCK_FILE"
	flock --exclusive "$LOCK_FD" || { xecho "$NODE_LABEL: ERROR: 'flock' failed (LOCK_FILE: '$LOCK_FILE', LOCK_FD: '$LOCK_FD'." ; exit 1 ; }
 
	# ----- Converting output & copy optional duplicates
	if [ -f "$NMAP_MERGER" ] ; then 
		xecho "Creating partial NMAP XML output..."
		tmp_output_dir=$( mktemp -d -p "$WORKING_DIR/output/" )
		cp $WORKING_DIR/output/*.xml "$tmp_output_dir"
		[[ -f $tmp_output_dir/output.xml ]] && rm $tmp_output_dir/output.xml
		merged_output=$( $NMAP_MERGER --dir $tmp_output_dir --quiet )
		if [ "$merged_output" != "" ] && [ -f "$merged_output" ] ; then
			mv $merged_output $WORKING_DIR/output/output.xml
			xecho "Partial XML output in '$WORKING_DIR/output/output.xml'"
		else
			xecho "Cannot merge partial output; missing merged output file."
		fi
		[[ -d "$tmp_output_dir" ]] && rm -rf $tmp_output_dir
	else
		xecho "Cannot merge partial output; missing nMapMerge."
	fi
	if [ "$OUTPUT_XML" != "" ] ; then
		xecho "Copying NMAP XML output to '$OUTPUT_XML'..."
		cp $WORKING_DIR/output/output.xml $OUTPUT_XML
	fi

	xecho "Creating partial NMAP output..."
	tmp_output_dir=$( mktemp -d -p "$WORKING_DIR/output/" )
	cp $WORKING_DIR/output/*.nmap "$tmp_output_dir"
	[[ -f $tmp_output_dir/output.nmap ]] && rm $tmp_output_dir/output.nmap
	xecho "Merging NMAP output into one file..."
	cat $tmp_output_dir/*.nmap > $WORKING_DIR/output/output.nmap
	[[ -d "$tmp_output_dir" ]] && rm -rf $tmp_output_dir
	xecho "NMAP output in '$WORKING_DIR/output/output.nmap'"
	if [ "$OUTPUT_NMAP" != "" ] ; then
		xecho "Copying NMAP output to '$OUTPUT_NMAP'..."
		cp $WORKING_DIR/output/output.nmap $OUTPUT_NMAP
	fi

	xecho "Creating partial GNMAP output..."
	tmp_output_dir=$( mktemp -d -p "$WORKING_DIR/output/" )
	cp $WORKING_DIR/output/*.gnmap "$tmp_output_dir"
	[[ -f $tmp_output_dir/output.gnmap ]] && rm $tmp_output_dir/output.gnmap
	xecho "Merging GNMAP output into one file..."
	cat $tmp_output_dir/*.gnmap > $WORKING_DIR/output/output.gnmap
	[[ -d "$tmp_output_dir" ]] && rm -rf $tmp_output_dir
	xecho "GNMAP output in '$WORKING_DIR/output/output.gnmap'"
	if [ "$OUTPUT_GNMAP" != "" ] ; then
		xecho "Copying GNMAP output to '$OUTPUT_GNMAP'..."
		cp $WORKING_DIR/output/output.gnmap $OUTPUT_GNMAP
	fi

	# release lock
	flock --unlock "$LOCK_FD"
	# ----- CRITICAL SECTION END ----------------------------------------------		
}

# -----------------------------------------------------------------------------
# ----- Entry Point -----------------------------------------------------------
# -----------------------------------------------------------------------------

NODE_PREFIX="node-$( openssl rand -hex 8 )"
WORKING_DIR="."
INPUT_FILE=""
MONITOR_QUEUE=$( mktemp )
MONITOR_DELAY=10
CREATE_RETRY_DELAY=30
TORIFY_PARAM=""
NMAP_PARAMS="-sV -T4 -Pn --resolve-all"
PROVIDER_CONF_DIR="/etc/nodenomicon"
PROVIDER_CONF_POOL=""
PROVIDER_CONF_SIZE=0
OUTPUT_XML=""
OUTPUT_NMAP=""
OUTPUT_GNMAP=""
OUTPUT_QUEUE=""

# ----- Parameter control -----------------------------------------------------
while [ "$1" != "" ]; do
	case $1 in
		-c | --config-pool)   shift; PROVIDER_CONF_DIR=$1 ;;
		-q | --monitor-queue) rm $MONITOR_QUEUE; shift; MONITOR_QUEUE=$1 ;;
		-d | --work-dir)      shift; WORKING_DIR=$1 ;;
		-n | --node-prefix)   shift; NODE_PREFIX=$1 ;;
		-f | --file)          shift; INPUT_FILE=$1 ;;
		--nmap-params)        shift; NMAP_PARAMS=$1 ;;
		--xml-output)		  shift; OUTPUT_XML=$1 ;;
		--nmap-output)		  shift; OUTPUT_NMAP=$1 ;;
		--gnmap-output)		  shift; OUTPUT_GNMAP=$1 ;;
		--queue-output)		  shift; OUTPUT_QUEUE=$1 ;;
		--torify)             TORIFY_PARAM="--torify" ;;
		* )                   call_for_help ; exit 1
	esac
	shift
done

FLAG_ERROR_PARAMS=false
[[ "$MONITOR_QUEUE" == "" ]] && { xecho "ERROR: Must specify a monitor queue file." ; FLAG_ERROR_PARAMS=true ; }
[[ "$WORKING_DIR" == "" ]]   && { xecho "ERROR: Must specify working directory."    ; FLAG_ERROR_PARAMS=true ; }
[[ "$INPUT_FILE" == "" ]]    && { xecho "ERROR: Must specify input data file."      ; FLAG_ERROR_PARAMS=true ; }
WORKER_ID=$( basename $INPUT_FILE | sed -r 's/worker-([0-9]+)\.data/\1/g' )
[[ "$WORKER_ID" == "" ]]     && { xecho "ERROR: Invalid name for input data file."  ; FLAG_ERROR_PARAMS=true ; }
[[ "$NMAP_PARAMS" == "" ]]   && { xecho "ERROR: Must specify nmap parameters."      ; FLAG_ERROR_PARAMS=true ; }
if [ ! -d "$PROVIDER_CONF_DIR" ] ; then
	xecho "ERROR: Provider configuration directory does not exists."
	FLAG_ERROR_PARAMS=true
else
	PROVIDER_CONF_POOL=$( find $PROVIDER_CONF_DIR -maxdepth 1 -name '*.cfg' -type f )
	[[ "$PROVIDER_CONF_POOL" == "" ]] && { xecho "ERROR: No provider configuration files found at '$PROVIDER_CONF_DIR'."; FLAG_ERROR_PARAMS=true; }
fi

[[ "${OUTPUT_XML}" != "" && ! -d "$( dirname ${OUTPUT_XML} )" ]] && { xecho "ERROR: XML output file destination directory do not exists."; FLAG_ERROR_PARAMS=true; }
[[ "${OUTPUT_NMAP}" != "" && ! -d "$( dirname ${OUTPUT_NMAP} )" ]] && { xecho "ERROR: NMAP output file destination directory do not exists."; FLAG_ERROR_PARAMS=true; }
[[ "${OUTPUT_GNMAP}" != "" && ! -d "$( dirname ${OUTPUT_GNMAP} )" ]] && { xecho "ERROR: GNMAP output file destination directory do not exists."; FLAG_ERROR_PARAMS=true; }
[[ "${OUTPUT_QUEUE}" != "" && ! -d "$( dirname ${OUTPUT_QUEUE} )" ]] && { xecho "ERROR: QUEUE output file destination directory do not exists."; FLAG_ERROR_PARAMS=true; }

[[ "$FLAG_ERROR_PARAMS" == true ]] && { call_for_help; exit 1; }

# ----- Process start ---------------------------------------------------------

LOCK_FILE="$WORKING_DIR/nodenomicon_sw.lock"
LOCK_FD=138

# ----- OpenBASH integration
if [ ! -z "$ID_APLICACION" ] ; then
	OPENBASH_PATH_NODES="/opt/tmp/$ID_APLICACION.nodes"
fi

# ----- Script default config
NODE_LABEL="$NODE_PREFIX-$WORKER_ID"
NODE_IPV4="?"
NODE_REGION="?"
NM_CMD="$SCRIPT_DIR/nm.sh $TORIFY_PARAM --work-dir $WORKING_DIR --label $NODE_LABEL"

# ----- Batch process ---------------------------------------------------------
xecho "$NODE_LABEL: Processing file: $INPUT_FILE"
xecho "$NODE_LABEL: Generating nmap script..."
s_id=1

update_monitor_queue "creating_payload"

# Node setup script validation
NODE_SETUP_SCRIPT="$SCRIPT_DIR/payloads/nodenomicon_node_setup.sh"
if [ ! -f $NODE_SETUP_SCRIPT ] ; then
	xecho "$NODE_LABEL: ERROR: Cannot find node setup script '$NODE_SETUP_SCRIPT'"
	exit 1
fi

# Worker payload
PAYLOAD_DIR="$WORKING_DIR/nodenomicon_$NODE_LABEL"
mkdir -p $PAYLOAD_DIR

PAYLOAD_SCRIPT="$PAYLOAD_DIR/nodenomicon_${WORKER_ID}.sh"
echo "#!/bin/bash" >> $PAYLOAD_SCRIPT
echo "# Script created with $APP_BANNER @ $( log_ts )" >> $PAYLOAD_SCRIPT
echo "" >> $PAYLOAD_SCRIPT
echo "cd /root/nodenomicon" >> $PAYLOAD_SCRIPT
echo "mkdir -p /root/nodenomicon/output" >> $PAYLOAD_SCRIPT
echo "" >> $PAYLOAD_SCRIPT

OLDIFS=$IFS
while IFS= read -r line; do
	target_file="targets_${WORKER_ID}_${s_id}.list"
	output_file="/root/nodenomicon/output/output_${WORKER_ID}_${s_id}"

	ports=$( echo $line | cut -d' ' -f2 )
	echo $line | cut -d' ' -f1 | tr , '\n' > $PAYLOAD_DIR/$target_file

	echo "nmap $NMAP_PARAMS -iL $target_file -p $ports -oA $output_file" >> $PAYLOAD_SCRIPT

	let "s_id+=1"
done < $INPUT_FILE
IFS=$OLDIFS

xecho "$NODE_LABEL: grabbing provider configuration pool..."
PROVIDER_CONF_POOL=($( echo "$PROVIDER_CONF_POOL" ))
PROVIDER_CONF_SIZE="${#PROVIDER_CONF_POOL[@]}"
xecho "$NODE_LABEL: found $PROVIDER_CONF_SIZE configurations."

xecho "$NODE_LABEL: Creating node with payload..."
update_monitor_queue "creating"
CREATE_EXIT_CODE=""

provider_index=$(($RANDOM % $PROVIDER_CONF_SIZE))
while [ "$CREATE_EXIT_CODE" != "0" ] ; do
	xecho "$NODE_LABEL: '${PROVIDER_CONF_POOL[$provider_index]}' selected."
	$NM_CMD create "${PROVIDER_CONF_POOL[$provider_index]}"
	CREATE_EXIT_CODE="$?"

	if [ "$CREATE_EXIT_CODE" != "0" ] ; then 
		update_monitor_queue "waiting_slot"
		xecho "$NODE_LABEL: WARNING: cannot create node (exit code: $CREATE_EXIT_CODE). Retrying in $CREATE_RETRY_DELAY seconds..."
		sleep $CREATE_RETRY_DELAY
		# round robin configuration pool
		let "provider_index+=1"
		[[ "$provider_index" -ge "$PROVIDER_CONF_SIZE" ]] && provider_index=0
	else
		NODE_IPV4=$( $NM_CMD ipv4 | grep -Pio 'IPv4: [0-9\.]+$' | cut -d' ' -f2 )
		NODE_REGION=$( $NM_CMD region | grep -Pio 'region: .+$' | cut -d' ' -f2 )
		xecho "$NODE_LABEL: node created sucessfully!"
	fi
done

# ---- If called from OpenBASH app, save the node ID
if [ ! -z "$OPENBASH_PATH_NODES" ] ; then echo $NODE_LABEL >> $OPENBASH_PATH_NODES ; fi

update_monitor_queue "setup"

# ---- Install needed packages at node
xecho "$NODE_LABEL: uploading setup script & installing packages needed to work..."
$NM_CMD cmd mkdir -p /root/nodenomicon
$NM_CMD scpput $NODE_SETUP_SCRIPT /root/nodenomicon
setup_result=$( $NM_CMD cmd 'cd /root/nodenomicon ; chmod +x nodenomicon_node_setup.sh ; ./nodenomicon_node_setup.sh' | grep -Pv '^#' )
if [ "$( echo $setup_result | grep -P '^OK:' )" == "" ] ; then
	xecho "$NODE_LABEL: ERROR: cannot setup node, reason: '$setup_result'. Dumping setup log..."
	$NM_CMD cmd 'if [ -f /root/nodenomicon/nodenomicon_node_setup.log ] ; then cat /root/nodenomicon/nodenomicon_node_setup.log ; else echo "Setup log not found!" ; fi'
	exit 1
else
	xecho "$NODE_LABEL: setup finished! status: '$setup_result'"
fi

# ---- Upload & run payload
$NM_CMD upload $PAYLOAD_DIR/ /root/nodenomicon
$NM_CMD cmd chmod +x /root/nodenomicon/nodenomicon_$WORKER_ID.sh

update_monitor_queue "working"

$NM_CMD cmd screen -S nodenomicon_$NODE_LABEL -d -m /root/nodenomicon/nodenomicon_$WORKER_ID.sh

# ---- Monitor node
xecho "$NODE_LABEL: Monitoring node..."
node_status="working"
while [ "$node_status" != "done" ] ; do
	task_status=$( $NM_CMD cmd screen -list | grep -Pi "nodenomicon_$NODE_LABEL" )
	if [ "$task_status" == "" ] ; then
		xecho "$NODE_LABEL: has finished! grabbing output and deleting node..."
		mkdir -p $WORKING_DIR/output
		$NM_CMD download /root/nodenomicon/output/ $WORKING_DIR/output/
		$NM_CMD delete
		update_monitor_queue "done"
		# ---- If called from OpenBASH app, remove the node ID
		[ ! -z "$OPENBASH_PATH_NODES" ] && sed -i "s/$NODE_LABEL//g" $OPENBASH_PATH_NODES
	else
		xecho "$NODE_LABEL: still working, waiting $MONITOR_DELAY secs..."
		sleep $MONITOR_DELAY
	fi
	#node_status=$( get_param $MONITOR_QUEUE $NODE_LABEL "unknown" )
	node_status=$( jq -r --arg nlabel $NODE_LABEL '.queue[] | select(.label == $nlabel).status' $MONITOR_QUEUE )
done

# ---- Generate partial results
generate_partial_output

xecho "$NODE_LABEL: finished!"