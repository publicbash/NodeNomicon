#!/bin/bash

# ----- Defaults & Config -----------------------------------------------------

APP_ID="NodeNomicon NodeManager"
APP_VERSION="0.1.4 beta"
APP_BANNER="$APP_ID $APP_VERSION"
APP_AUTHOR="Dex0r & Kaleb @ OpenBASH"
APP_DATETIME="2022-08-06"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# ----- Needed tools
TOOL_LIST=(awk basename curl cut join jq mktemp nmap openssl realpath rsync scp shuf sort ssh-keygen torify xargs) 

# ----- Log prefix for tool
_XECHO_PREFIX="nm"

# ----- Functions & External scripts ------------------------------------------
if [ ! -f $SCRIPT_DIR/libopenbash.inc ] ; then 
	echo "FATAL ERROR: OpenBASH function library not found." 
	exit 1
else 
	. $SCRIPT_DIR/libopenbash.inc	
fi

function call_for_help
{
	xecho "Syntax:"
	xecho "  $0 -d <working_dir> -l <node_label> <action> [param_1] [param_2] [...] [param_N]"
	xecho ""
	xecho "Usage:"
	xecho "  $0 -d ../work/dir -t -l node-1337 create linode.cfg"
	xecho "  $0 --work-dir ../work/dir --torify --node node-1337 create linode.cfg"
	xecho ""
	xecho "Help:"
	xecho "  <action>               Specifies the action to be executed on node."
	xecho "  -d, --work-dir STRING  Specifies the working directory."
	xecho "  -l, --label STRING     Specifies the node label."
	xecho "  -t, --torify           Specifies if tor network must be used to reach the API."
	xecho "  -h, --help             This help."
	xecho ""
	xecho "  Actions:"
	xecho "    cmd | ssh [command]  Executes a remote command via ssh connection. If 'command' is not specified,"
	xecho "                         an interactive shell will be opened. If need to pipe or redirect remote output,"
	xecho "                         enclose the command between single/double quotes."
	xecho "    create <provider>    Creates a node, using the provider .cfg file."
	xecho "    delete               Deletes a node."
	xecho "    driver               Get the node driver type."
	xecho "    get | download       Downloads a directory/file."
	xecho "    id                   Get the node ID."
	xecho "    image                Get the node image type, OS wise."
	xecho "    ip | ipv4            Get the node IPv4 address."
	xecho "    nodecount <provider> Get the current working nodes at provider account, using the provider .cfg file."
	xecho "    put | upload         Uploads a directory/file."
	xecho "    scpget               Downloads a file using ssh protocol (scp)."	
	xecho "    scpput               Uploads a file using ssh protocol (scp)."	
	xecho "    region               Get the node region."
	xecho "    status               Get the node status."
	xecho "    type                 Get the node type, pricing/specification wise."
	xecho ""
}

function read_node_data
{
	# check node file data
	if [ ! -f $NODE_DATA_FILE ] ; then xecho "ERROR: $NODE_DATA_FILE not found." ; exit 1 ; fi

	# grab & update node params gobally
	NODE_DRIVER=$( get_param $NODE_DATA_FILE driver '' )

	# check node basic params
	if [ "$NODE_DRIVER" == "" ] ; then xecho "ERROR: undefined driver for this node data." ; exit 1 ; fi

	NODE_DRIVER_CMD=$( get_driver_name $NODE_DRIVER )
}

function get_driver_name
{
	local driver_path="$SCRIPT_DIR/nm_drivers/nm_$1.sh"
	if [ "$1" == "" ] ; then xecho "FATAL ERROR: missing driver path." ; exit 1 ; fi
	if [ ! -f $driver_path ]  ; then xecho "FATAL ERROR: driver '$driver_path' not found." ; exit 1 ; fi
	echo $driver_path
}

# -----------------------------------------------------------------------------
# ----- Entry Point -----------------------------------------------------------
# -----------------------------------------------------------------------------

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
	exit 1
fi

# ----- Parameter control -----------------------------------------------------

# ----- Script default config
NODE_LABEL="node-$( openssl rand -hex 16 )"
NODE_ACTION=""
NODE_ACTION_ARG=""
NODE_ACTION_ARGCOUNT=""
WORKING_DIR="."
TORIFY_CURL="N"

FLAG_DONE_PARAMS=false
while [ "$1" != "" ] && [ "$FLAG_DONE_PARAMS" == false ] ; do
	case $1 in
		-l | --label)     shift; NODE_LABEL=$1 ;;
		-d | --work-dir)  shift; WORKING_DIR=$1 ;;
		-t | --torify)    TORIFY_CURL="Y" ;;
		-h | --help )     call_for_help; exit 1 ;;
		*)
			NODE_ACTION=$1
			shift
			NODE_ACTION_ARG=$@
			NODE_ACTION_ARGCOUNT=$#
			FLAG_DONE_PARAMS=true
			shift
	esac
	if [ "$FLAG_DONE_PARAMS" == false ] ; then shift ; fi
done

FLAG_ERROR_PARAMS=false

if [ "$NODE_LABEL" == "" ]   ; then xecho "$NODE_LABEL: ERROR: Must specify node ID."           ; FLAG_ERROR_PARAMS=true ; fi
if [ "$WORKING_DIR" == "" ]  ; then xecho "$NODE_LABEL: ERROR: Must specify working directory." ; FLAG_ERROR_PARAMS=true ; fi
if [ ! -d $WORKING_DIR ]     ; then xecho "$NODE_LABEL: ERROR: $WORKING_DIR not found."         ; FLAG_ERROR_PARAMS=true ; fi
if [ "$NODE_ACTION" == "" ]  ; then xecho "$NODE_LABEL: ERROR: Must specify node action."       ; FLAG_ERROR_PARAMS=true ; fi

if [ "$FLAG_ERROR_PARAMS" == true ] ; then
	xecho "" 
	call_for_help
	#free_resources $TMP_LOG $TMP_NMAP_OUTPUT $TMP_TARGETS $TMP_PORTS $TMP_FULL_TARGET 
	exit 1 
fi

if [ "$TORIFY_CURL" == "Y" ] ; then CURL_CMD="torify curl" ; fi

# ----- Process start ---------------------------------------------------------

# ----- Parameters definitions
# Most of these are updated globally using read_node_data function
NODE_DRIVER=""
NODE_DRIVER_CMD=""

NODE_DATA_FILE="$( realpath $WORKING_DIR/node_$NODE_LABEL.data )"

# Get & verify node data (only if action needs it)
NO_NODE_DATA_ACTIONS=("create" "nodecount")
NODE_NEED_DATA=$( containsElement $NODE_ACTION ${NO_NODE_DATA_ACTIONS[@]} )

if [ "$NODE_NEED_DATA" == true ] ; then 
	if [ "$NODE_ACTION_ARGCOUNT" == "0" ] ; then xecho "$NODE_LABEL: ERROR: Missing service provider config." ; exit 1 ; fi

	# If creating a node, grab the driver from the provider config
	provider_cfg="$( realpath $NODE_ACTION_ARG )"

	if [ "$provider_cfg" == "" ] ; then xecho "$NODE_LABEL: ERROR: Must specify service provider."  ; exit 1 ; fi
	if [ ! -f $provider_cfg ]    ; then xecho "$NODE_LABEL: ERROR: $provider_cfg not found."        ; exit 1 ; fi

	NODE_DRIVER=$( get_param $provider_cfg driver '' )
	if [ "$NODE_DRIVER" == "" ] ; then xecho "$NODE_LABEL: ERROR: undefined driver for this provider config." ; exit 1 ; fi

	NODE_ACTION_ARG=$provider_cfg
else
	read_node_data 
fi

# ----- Action execution --------------
NODE_DRIVER_CMD=$( get_driver_name $NODE_DRIVER )
WORKING_DIR=$( realpath $WORKING_DIR )

xecho "$NODE_LABEL: Executing > $NODE_ACTION $NODE_ACTION_ARG"
$NODE_DRIVER_CMD --work-dir $WORKING_DIR --label $NODE_LABEL $NODE_ACTION $NODE_ACTION_ARG
