#!/bin/bash

# ----- Defaults & Config -----------------------------------------------------

APP_ID="NodeManager Vultr Driver"
APP_VERSION="0.1.6 beta"
APP_BANNER="$APP_ID $APP_VERSION"
APP_AUTHOR="Dex0r & Kaleb @ OpenBASH"
APP_DATETIME="2022-08-11"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# ----- Needed tools
TOOL_LIST=(awk basename curl cut flock join jq mktemp nmap openssl rsync scp shuf sort ssh-keygen torify xargs) 
CURL_CMD=$( command -v curl )

# ----- Misc config
DRIVER_NAME="vultr"
CREATE_MAX_TRIES=10
DELETE_MAX_TRIES=10
STATUS_DELAY_TIMEOUT=30
SSH_DELAY_TIMEOUT=30
SSH_MAX_TRIES=12

# ----- Log prefix for tool
_XECHO_PREFIX="nm_vultr"


# ----- Functions & External scripts ------------------------------------------
if [ ! -f $SCRIPT_DIR/../libopenbash.inc ] ; then 
	echo "FATAL ERROR: OpenBASH function library not found." 
	exit 1
else 
	. $SCRIPT_DIR/../libopenbash.inc	
fi

function call_for_help
{
	xecho "Syntax:"
	xecho "  $0 -d <working_dir> -l <node_label> <action> [param_1] [param_2] [...] [param_N]"
	xecho ""
	xecho "Usage:"
	xecho "  $0 -d ../work/dir -t -l node-1337 create vultr.cfg"
	xecho "  $0 --work-dir ../work/dir --torify --node node-1337 create vultr.cfg"
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
	xecho "    snapshot             Get the node snapshot ID."
	xecho "    ip | ipv4            Get the node IPv4 address."
	xecho "    nodecount <provider> Get the created node count at provider account; need the provider .cfg file."
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
	API_KEY=$( get_param $NODE_DATA_FILE api_key '' )
	API_URL=$( get_param $NODE_DATA_FILE api_url 'https://api.vultr.com/v2' )
	API_USER_AGENT=$( get_param $NODE_DATA_FILE api_user_agent "$APP_BANNER" )	
	NODE_ID=$( get_param $NODE_DATA_FILE node_id '' )
	NODE_TYPE=$( get_param $NODE_DATA_FILE node_type '' )
	NODE_IMAGE=$( get_param $NODE_DATA_FILE node_image '' )
	NODE_SNAPSHOT=$( get_param $NODE_DATA_FILE node_snapshot '' )
	NODE_SSH_KEY=$( get_param $NODE_DATA_FILE node_ssh_key '' )
	NODE_REGION=$( get_param $NODE_DATA_FILE node_region '' )
	NODE_IPV4=$( get_param $NODE_DATA_FILE node_ipv4 '' )

	# check node basic params
	if [ "$NODE_DRIVER" == "" ]   ; then xecho "ERROR: undefined driver for this node data." ; exit 1 ; fi
	if [ "$NODE_DRIVER" != "$DRIVER_NAME" ] ; then xecho "ERROR: the node do not correspond to this driver ('$DRIVER_NAME' vs '$NODE_DRIVER')" ; exit 1 ; fi
	if [ "$API_KEY" == "" ]       ; then xecho "ERROR: api-key not found." ; exit 1 ; fi
	if [ "$NODE_ID" == "" ]       ; then xecho "ERROR: undefined node ID for this node data." ; exit 1 ; fi
	if [ "$NODE_TYPE" == "" ]     ; then xecho "WARNING: undefined node parameter 'node_type'." ; fi
	if [ "$NODE_IMAGE" == "" ] && [ "$NODE_SNAPSHOT" == "" ] ; then xecho "WARNING: both undefined node parameters: 'node_image' and 'node_snapshot'." ; fi
	if [ "$NODE_SSH_KEY" == "" ]  ; then xecho "WARNING: undefined node parameter 'node_ssh_key'." ; fi
	if [ "$NODE_REGION" == "" ]   ; then xecho "WARNING: undefined node parameter 'node_region'." ; fi
	if [ "$NODE_IPV4" == "" ]     ; then xecho "WARNING: undefined node parameter 'node_ipv4'." ; fi
}

function clear_known_hosts
{
	ssh-keygen -f "$HOME/.ssh/known_hosts" -R $NODE_IPV4 > /dev/null 2>&1
}

function gen_api_output
{
	local tmpf=$( mktemp -p "$WORKING_DIR" )
	local outf="$WORKING_DIR/node_${NODE_LABEL}_$( basename $tmpf ).out"
	mv $tmpf $outf
	echo "$outf"
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
ERROR_DIR="$WORKING_DIR/errors"
TORIFY_CURL="N"

FLAG_DONE_PARAMS=false
while [ "$1" != "" ] && [ "$FLAG_DONE_PARAMS" == false ] ; do
	case $1 in
		-l | --label)    shift; NODE_LABEL=$1 ;;
		-d | --work-dir) shift; WORKING_DIR=$1 ;;
		-t | --torify)   TORIFY_CURL="Y" ;;
		-h | --help )    call_for_help;	exit 1 ;;
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

if [ "$TORIFY_CURL" == "Y" ] ; then CURL_CMD="torify $CURL_CMD" ; fi

# update ERROR_DIR
ERROR_DIR="$WORKING_DIR/errors"
mkdir -p $ERROR_DIR

# ----- OpenBASH integration
NODE_GROUP_TAG=$( [ ! -z "$ID_APLICACION" ] && echo "$ID_APLICACION" || echo "$NODE_LABEL" )

# ----- Process start ---------------------------------------------------------

# ----- Parameters definitions
# Most of these are updated globally using read_node_data function
NODE_DRIVER=""
API_KEY=""
API_URL=""
API_USER_AGENT=""
MAX_NODE_COUNT=""
NODE_ID=""
NODE_TYPE=""
NODE_IMAGE=""
NODE_SNAPSHOT=""
NODE_SSH_KEY=""
NODE_REGION=""
NODE_IPV4=""

BOOT_SCRIPT_NAME="NodeNomicon-StartUpScript-v0.1"

NODE_DATA_FILE="$WORKING_DIR/node_$NODE_LABEL.data"

# Get & verify node data (only if action needs it)
NO_NODE_DATA_ACTIONS=("create" "nodecount")
[[ "$( containsElement $NODE_ACTION ${NO_NODE_DATA_ACTIONS[@]} )" == false ]] && read_node_data

# ----- Actions definitions -----------
function get_startup_script_id
{
	local api_endpoint="$API_URL/startup-scripts"
	local api_output=$( gen_api_output )
	local api_output_header="${api_output}.header"
	local http_result

	http_result=$( $CURL_CMD --location --silent --request GET --header "Content-Type: application/json" --header "Authorization: Bearer $API_KEY" --user-agent "$API_USER_AGENT" --output $api_output --dump-header $api_output_header --write-out '%{http_code}' "$api_endpoint" )
	
	if [ "$( echo $http_result | grep -P '^2[0-9]{2}$' )" != "" ] ; then 
		cat $api_output | jq --arg sname $BOOT_SCRIPT_NAME -c -r '.startup_scripts[] | select (.name == $sname) | .id'
	else
		cp $api_output $api_output_header $ERROR_DIR
		echo "" 
	fi

	if [ -f $api_output ] ; then rm $api_output $api_output_header ; fi
}

function upload_startup_script
{
	local api_endpoint="$API_URL/startup-scripts"
	local api_output=$( gen_api_output )
	local api_output_header="${api_output}.header"
	local http_result

	# Startup script in base64
	# Can get it with:
	#    startup_script_base64=$( base64 -w 0 ./src/nodenomicon/payloads/vultr_startup_preload_ssh_key.sh )
	local startup_script_base64="IyEvYmluL3NoCgojIE9wZW5CYXNoCiMgQWRkIGN1c3RvbSBzc2ggcHVibGljIGtleSB0byB2b2xhdGlsZSBub2Rlcy4KIyBVc2VkIGJlY2F1c2UgY2Fubm90IHNldCBzc2hrZXkgd2l0aCBBUEkgYWdhaW5zdCBzbmFwc2hvdCBjbG9uZXMuCiMgUnVucyBvbiAvZXRjL25ldHdvcmsvaWYtdXAuZCBhcyBzeW1saW5rLgojIAojIFBlcnNpc3QgaXQgd2l0aDoKIyAgY2htb2QgK3ggL3Jvb3QvYWRkX2N1c3RvbV9zc2hrZXkuc2gKIyAgY2QgL2V0Yy9uZXR3b3JrL2lmLXVwLmQvCiMgIGxuIC1zIC9yb290L2FkZF9jdXN0b21fc3Noa2V5LnNoIDAwMWFkZGN1c3RvbXNzaGtleQojCiMgS2FsZWIgLSAyMDIyLTA4LTExCgpjZCAvcm9vdAoKdXNlcl9zc2hfa2V5PSQoIGN1cmwgLXMgJ2h0dHA6Ly8xNjkuMjU0LjE2OS4yNTQvdXNlci1kYXRhL3VzZXItZGF0YScgKQoKaWYgWyAiJHVzZXJfc3NoX2tleSIgIT0gIiIgXSA7IHRoZW4gCglta2RpciAtcCAvcm9vdC8uc3NoCgljaG1vZCA2MDAgL3Jvb3QvLnNzaAoJZWNobyAiJHVzZXJfc3NoX2tleSIgPiAvcm9vdC8uc3NoL2F1dGhvcml6ZWRfa2V5cwoJY2htb2QgNzAwIC9yb290Ly5zc2gvYXV0aG9yaXplZF9rZXlzCgllY2hvICJbICQoIGRhdGUgLUlzICkgXSBBZGRlZCBzc2gga2V5IGZyb20gaW5zdGFuY2UgbWV0YWRhdGEiID4+IHN0YXJ0dXAubG9nCmVsc2UKCWVjaG8gIlsgJCggZGF0ZSAtSXMgKSBdIEVSUk9SOiBDYW5ub3QgYWRkIHNzaCBrZXkgZnJvbSBpbnN0YW5jZSBtZXRhZGF0YSIgPj4gc3RhcnR1cC5sb2cKZmk="
	
	http_result=$( $CURL_CMD --location --silent --request POST --header "Content-Type: application/json" --header "Authorization: Bearer $API_KEY" --user-agent "$API_USER_AGENT" --data '{"name":"'"$BOOT_SCRIPT_NAME"'","type":"boot","script":"'"$startup_script_base64"'"}' --output $api_output --dump-header $api_output_header --write-out '%{http_code}' "$api_endpoint" )
	
	if [ "$( echo $http_result | grep -P '^2[0-9]{2}$' )" != "" ] ; then 
		cat $api_output | jq --arg sname $BOOT_SCRIPT_NAME -c -r '.startup_script.id'
	else
		cp $api_output $api_output_header $ERROR_DIR
		echo "" 
	fi

	if [ -f $api_output ] ; then rm $api_output $api_output_header ; fi

}

function create_node
{
	# Do not overwrite node data, if exists.
	if [ -f $NODE_DATA_FILE ] ; then xecho "$NODE_LABEL: ERROR: $NODE_DATA_FILE already created." ; exit 1 ; fi

	# Find node config file
	local provider_cfg=$1

	if [ "$provider_cfg" == "" ] ; then xecho "$NODE_LABEL: ERROR: Must specify service provider."  ; exit 1 ; fi
	if [ ! -f $provider_cfg ]    ; then xecho "$NODE_LABEL: ERROR: $provider_cfg not found."        ; exit 1 ; fi

	# Update global vars from provider config
	API_KEY=$( get_param $provider_cfg api-token '' )
	API_URL=$( get_param $provider_cfg api-url 'https://api.vultr.com/v2' )
	API_USER_AGENT=$( get_param $provider_cfg user-agent "$APP_BANNER" )
	NODE_TYPE=$( get_param $provider_cfg type 'vc2-1c-1gb' )
	NODE_IMAGE=$( get_param $provider_cfg image '' )
	NODE_SNAPSHOT=$( get_param $provider_cfg snapshot '' )
	MAX_NODE_COUNT=$( get_param $provider_cfg max-node-count '20' )

	NODE_DRIVER=$( get_param $provider_cfg driver '' )
	if [ "$NODE_DRIVER" == "" ] ; then xecho "$NODE_LABEL: ERROR: undefined driver for this provider config." ; exit 1 ; fi

	# Define local vars
	local node_region=$( get_param $provider_cfg region 'atl,dfw,ewr,lax,mia,ord,sea,sjc' )
	local api_endpoint="$API_URL/instances"
	local node_ssh_passwd=$( secure_pass_gen )
	local node_selected_region=$( get_region $node_region )
	local api_output=$( gen_api_output )
	local api_output_header="${api_output}.header"
	local try_count=0
	local lock_file="/tmp/nm_create_$( echo $API_KEY | md5sum | cut -d' ' -f1 ).lock"
	local lock_fd=137
	local http_result error_output_file node_ssh_key node_status ssh_status node_count node_available_slots boot_script_id
	
	# fault if cannot get node region
	if [ "$( echo $node_selected_region | grep -P '^api_error_')" != "" ] ; then
		xecho "$NODE_LABEL: Cannot select node region. API ERROR: $node_selected_region"
		exit 1
	fi

	# generate ssh-key & password
	if [ -f $WORKING_DIR/node_$NODE_LABEL.key ] ; then rm $WORKING_DIR/node_$NODE_LABEL.key* ; fi
	ssh-keygen -t rsa -b 4096 -f $WORKING_DIR/node_$NODE_LABEL.key -q -N ""
	node_ssh_key=$( cat $WORKING_DIR/node_$NODE_LABEL.key.pub )

	# ----- CRITICAL SECTION START --------------------------------------------
	# Only one process at a time can check for node slots (to prevent parallelism race conditions and get accurate results)
	# One lock file per API_KEY 
	eval "exec $lock_fd>$lock_file"
	flock --exclusive "$lock_fd" || { xecho "$NODE_LABEL: ERROR: 'flock' failed (lock_file: '$lock_file', lock_fd: '$lock_fd'." ; exit 1 ; }
 
	# verify node account max nodes (there's room for this node?)
	xecho "$NODE_LABEL: Checking for available node slots at provider account..."
	node_count=$( get_node_count $provider_cfg )
	if [ "$( echo $node_count | grep -P '^[0-9]+$' )" == "" ] ; then 
		xecho "$NODE_LABEL: ERROR: Cannot get node count (returned '$node_count')."
		# release lock & exit
		flock --unlock "$lock_fd"
		exit 1
	fi
	
	let "node_available_slots = $MAX_NODE_COUNT - $node_count"
	if [ "$node_available_slots" -gt "0" ] ; then
		xecho "$NODE_LABEL: There's $node_available_slots slots available ($node_count already taken)."
		sshkey_base64=$( echo $node_ssh_key | base64 -w 0 )

		# set 'image' or 'snapshot'... 'image' takes precedence
		if [ "$NODE_IMAGE" != "" ] ; then 
			NODE_IMAGE_SNAPSHOT='"os_id":'"$NODE_IMAGE"
			
			# As part of "base distro" selection for Vultr, we must
			# prepare the node startup script (ssh key add on start)
			xecho "$NODE_LABEL: Checking for Vultr startup script..."
			boot_script_id=$( get_startup_script_id )
			if [ "$boot_script_id" == "" ] ; then
				xecho "$NODE_LABEL: Startup script not found on Vultr, uploading..."
				boot_script_id=$( upload_startup_script )
			fi

			if [ "$boot_script_id" != "" ] ; then
				xecho "$NODE_LABEL: Startup script found: $boot_script_id"
				NODE_SCRIPT_ID='"script_id":"'"$boot_script_id"'",'
			else
				xecho "$NODE_LABEL: WARNING: startup script not found again!"
				flock --unlock "$lock_fd"
				# Exit code 23 means that we cannot get the startup script to work
				exit 23
			fi
		else
			NODE_IMAGE_SNAPSHOT='"snapshot_id":"'"$NODE_SNAPSHOT"'"'
			NODE_SCRIPT_ID=""
		fi

		# create node
		xecho "$NODE_LABEL: Creating node..."
		http_result=$( $CURL_CMD --location --silent --request POST --header "Content-Type: application/json" --header "Authorization: Bearer $API_KEY" --user-agent "$API_USER_AGENT" --data '{"label":"'"$NODE_LABEL"'","region":"'"$node_selected_region"'","plan":"'"$NODE_TYPE"'",'"$NODE_IMAGE_SNAPSHOT"',"user_data":"'"$sshkey_base64"'",'"$NODE_SCRIPT_ID"'"backups":"disabled","enable_ipv6":false,"ddos_protection":false,"activation_email":false,"hostname":"'"$NODE_LABEL"'","tag":"App-'"$NODE_GROUP_TAG"'","enable_private_network":false}' --output $api_output --dump-header $api_output_header --write-out '%{http_code}' "$api_endpoint" )

	else
		xecho "$NODE_LABEL: WARNING: There's no more slots available. Current: $node_count nodes."
		flock --unlock "$lock_fd"
		# Exit code 17 means that there's no more slots available
		exit 17
	fi

	# release lock
	flock --unlock "$lock_fd"
	# ----- CRITICAL SECTION END ----------------------------------------------

	if [ "$( echo $http_result | grep -P '^2[0-9]{2}$' )" == "" ] ; then 
		xecho "$NODE_LABEL: API ERROR: http status = $http_result"
		cp $api_output $api_output_header $ERROR_DIR
		exit 1
	fi

	xecho "$NODE_LABEL: API HTTP Status: $http_result"
	
	# Verify, grab result & update globals
	if [ ! -f $api_output ] ; then 
		xecho "$NODE_LABEL: ERROR: cannot find output file: '$api_output'"
		exit 1
	fi
	
	#IMPORTANT NOTE: the IPv4 value is obtained after the instance has booted up (at creation, has 0.0.0.0 as IP)
	NODE_ID=$( cat $api_output | jq -r '.instance.id' )

	if [ "$( echo $NODE_ID | grep -P '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' )" == "" ] ; then
		error_output_file="$ERROR_DIR/${NODE_LABEL}_ERROR_OUT_$RANDOM.out"
		mv $api_output $error_output_file
		xecho "$NODE_LABEL: API ERROR: cannot get a valid node id (returned '$NODE_ID', full output at: '$error_output_file')."
		exit 1
	fi

	NODE_SSH_KEY=$node_ssh_key 

	# generate the node data file
	xecho "$NODE_LABEL: Generating node data file: $NODE_DATA_FILE"
	echo "# NodeData for $NODE_LABEL" >> $NODE_DATA_FILE
	echo "# Generated by $APP_BANNER @ $( log_ts )" >> $NODE_DATA_FILE
	echo "driver = $DRIVER_NAME" >> $NODE_DATA_FILE
	echo "api_key = $API_KEY" >> $NODE_DATA_FILE
	echo "api_url = $API_URL" >> $NODE_DATA_FILE
	echo "api_user_agent = $API_USER_AGENT" >> $NODE_DATA_FILE
	echo "node_type = $NODE_TYPE" >> $NODE_DATA_FILE
	echo "node_image = $NODE_IMAGE" >> $NODE_DATA_FILE
	echo "node_snapshot = $NODE_SNAPSHOT" >> $NODE_DATA_FILE
	echo "node_id = $NODE_ID" >> $NODE_DATA_FILE
	echo "node_ssh_key = $node_ssh_key" >> $NODE_DATA_FILE
	echo "node_region = $node_selected_region" >> $NODE_DATA_FILE
	# This is written after the instance has booted ---> echo "node_ipv4 = $NODE_IPV4" >> $NODE_DATA_FILE
	
	if [ -f $api_output ] ; then rm $api_output $api_output_header ; fi

	# dump some info
	xecho "$NODE_LABEL: node configuration:"
	xecho "$NODE_LABEL:   driver   = $DRIVER_NAME"
	xecho "$NODE_LABEL:   type     = $NODE_TYPE"
	xecho "$NODE_LABEL:   image    = $NODE_IMAGE"
	xecho "$NODE_LABEL:   snapshot = $NODE_SNAPSHOT"
	xecho "$NODE_LABEL:   id       = $NODE_ID"
	xecho "$NODE_LABEL:   region   = $node_selected_region"

	# wait for ready status
	node_status="$( get_node_status )"
	while [ "$node_status" != "active" ] && [ "$try_count" -le "$CREATE_MAX_TRIES" ] ; do
		let "try_count+=1"
		xecho "$NODE_LABEL: status: $node_status (waiting $STATUS_DELAY_TIMEOUT sec...)"
		node_status="$( get_node_status )"
		sleep $STATUS_DELAY_TIMEOUT
	done

	if [ "$node_status" != "active" ] ; then 
		xecho "$NODE_LABEL: Cannot create node. Deleting..." 
		delete_node
		exit 18
	fi

	# After booting, we can get the IPv4 for the instance
	NODE_IPV4=$( get_node_IPv4 )
	echo "node_ipv4 = $NODE_IPV4" >> $NODE_DATA_FILE
	xecho "$NODE_LABEL:   ipv4   = $NODE_IPV4"

	xecho "$NODE_LABEL: node is running."
	
	xecho "$NODE_LABEL: Checking for ssh access..."

	ssh_status=""
	try_count=0
	while [ "$ssh_status" != "open" ] && [ "$try_count" -le "$SSH_MAX_TRIES" ] ; do
		ssh_status="$( nmap -Pn -p 22 $NODE_IPV4 | grep '22/tcp' | cut -d' ' -f2 )"
		if [ "$ssh_status" == "open" ] ; then
			# just in case, wait for node custom startup script (network if-up.d script)
			xecho "$NODE_LABEL: ssh service is almost ready. Waiting 10 secs..."
			sleep 10
			xecho "$NODE_LABEL: ssh service is ready!"
		else
			xecho "$NODE_LABEL: ssh service is not ready... (waiting $SSH_DELAY_TIMEOUT sec...)"
			let "try_count+=1"
			sleep $SSH_DELAY_TIMEOUT
		fi
	done

	if [ "$try_count" -gt "$SSH_MAX_TRIES" ] ; then
		xecho "$NODE_LABEL: Cannot access node via ssh. Deleting..."
		delete_node
		exit 19
	else
		xecho "$NODE_LABEL: node is ready to rock!"
	fi
}

function delete_node
{
	local api_endpoint="$API_URL/instances/$NODE_ID"
	local api_output api_output_header http_result
	local try_count=0

	xecho "$NODE_LABEL: Deleting node..."

	while [ "$( echo $http_result | grep -P '^2[0-9]{2}$' )" == "" ] && [ "$try_count" -le "$DELETE_MAX_TRIES" ] ; do
		let "try_count+=1"
		api_output=$( gen_api_output )
		api_output_header="${api_output}.header"
		http_result=$( $CURL_CMD --location --silent --request DELETE --header "Authorization: Bearer $API_KEY" --user-agent "$API_USER_AGENT" --output $api_output --dump-header $api_output_header --write-out '%{http_code}' "$api_endpoint" )

		if [ "$( echo $http_result | grep -P '^2[0-9]{2}$' )" != "" ] ; then 
			xecho "$NODE_LABEL: node no longer exists."
		else
			xecho "$NODE_LABEL: node is still alive: api_error_$http_result. Retrying...  (waiting $STATUS_DELAY_TIMEOUT sec...)" 
			cp $api_output $api_output_header $ERROR_DIR
			sleep $STATUS_DELAY_TIMEOUT
		fi
	
		if [ -f $api_output ] ; then rm $api_output $api_output_header ; fi
	done

	xecho "$NODE_LABEL: removing node data..."
	for f in $( find $WORKING_DIR -maxdepth 1 -name "node_$NODE_LABEL.*" -type f ) ; do rm $f ; done
}

function get_node_status
{
	local api_endpoint="$API_URL/instances/$NODE_ID"
	local api_output=$( gen_api_output )
	local api_output_header="${api_output}.header"
	local http_result

	http_result=$( $CURL_CMD --location --silent --request GET --header "Content-Type: application/json" --header "Authorization: Bearer $API_KEY" --user-agent "$API_USER_AGENT" --output $api_output --dump-header $api_output_header --write-out '%{http_code}' "$api_endpoint" )
	
	if [ "$( echo $http_result | grep -P '^2[0-9]{2}$' )" != "" ] ; then 
		cat $api_output | jq -r '.instance.status'
	else
		cp $api_output $api_output_header $ERROR_DIR
		echo "api_error_$http_result" 
	fi

	if [ -f $api_output ] ; then rm $api_output $api_output_header ; fi
}

function get_node_IPv4
{
	local api_endpoint="$API_URL/instances/$NODE_ID"
	local api_output=$( gen_api_output )
	local api_output_header="${api_output}.header"
	local http_result 
	# grab node params (use local var to avoid messing with global NODE_IPV4)
	local node_ip=$( get_param $NODE_DATA_FILE node_ipv4 'null' )

	# grab data from node data file; if not present, use the API
	if [ "$node_ip" != "null" ] ; then
		echo $node_ip
	else
		http_result=$( $CURL_CMD --location --silent --request GET --header "Content-Type: application/json" --header "Authorization: Bearer $API_KEY" --user-agent "$API_USER_AGENT" --output $api_output --dump-header $api_output_header --write-out '%{http_code}' "$api_endpoint" )

		if [ "$( echo $http_result | grep -P '^2[0-9]{2}$' )" != "" ] ; then 
			cat $api_output | jq -r '.instance.main_ip'
		else
			cp $api_output $api_output_header $ERROR_DIR
			# on API error, null IP
			echo "null" 
		fi

		if [ -f $api_output ] ; then rm $api_output $api_output_header ; fi
	fi
}

function get_region
{
 	local node_region=$1
	local api_endpoint="$API_URL/plans"
 	local api_output=$( gen_api_output )
	local api_output_header="${api_output}.header"
 	local http_result

	if [ "$node_region" == "auto" ] ; then
		# Get all available regions for an specific node_type (plan)
		http_result=$( $CURL_CMD --location --silent --request GET --header "Content-Type: application/json" --header "Authorization: Bearer $API_KEY" --user-agent "$API_USER_AGENT" --output $api_output --dump-header $api_output_header --write-out '%{http_code}' "$api_endpoint" )

		if [ "$( echo $http_result | grep -P '^2[0-9]{2}$' )" != "" ] ; then 
			cat $api_output | jq --arg ntype $NODE_TYPE -c -r '.plans[] | select (.id == $ntype) | .locations[]' | shuf | head -n 1 
		else
			cp $api_output $api_output_header $ERROR_DIR
			echo "api_error_$http_result" 
		fi
	
		if [ -f $api_output ] ; then rm $api_output $api_output_header ; fi
	else
		# Convert comma separated values into a list
		echo $node_region | tr ',' "\n" | shuf | head -n 1
	fi
}

function get_node_count
{
	# Find node config file
	local provider_cfg=$1

	if [ "$provider_cfg" == "" ] ; then xecho "$NODE_LABEL: ERROR: Must specify service provider."  ; exit 1 ; fi
	if [ ! -f $provider_cfg ]    ; then xecho "$NODE_LABEL: ERROR: $provider_cfg not found."        ; exit 1 ; fi

	# Update global vars from provider config
	API_KEY=$( get_param $provider_cfg api-token '' )
	API_URL=$( get_param $provider_cfg api-url 'https://api.vultr.com/v2' )
	API_USER_AGENT=$( get_param $provider_cfg user-agent "$APP_BANNER" )
	NODE_DRIVER=$( get_param $provider_cfg driver '' )

	if [ "$NODE_DRIVER" == "" ] ; then xecho "$NODE_LABEL: ERROR: undefined driver for this provider config." ; exit 1 ; fi

	# get data
	local api_endpoint="$API_URL/instances?per_page=1"
 	local api_output=$( gen_api_output )
 	local api_output_header="${api_output}.header"

	# Get all droplets, account wide. Get the first page (to reduce result size), then get the 'results' data from pagination (the node count).
	local http_result=$( $CURL_CMD --location --silent --request GET --header "Content-Type: application/json" --header "Authorization: Bearer $API_KEY" --user-agent "$API_USER_AGENT" --output $api_output --dump-header $api_output_header --write-out '%{http_code}' "$api_endpoint" )

	if [ "$( echo $http_result | grep -P '^2[0-9]{2}$' )" != "" ] ; then 
		cat $api_output | jq -r '.meta.total'
	else
		cp $api_output $api_output_header $ERROR_DIR
		echo "api_error_$http_result" 
	fi
	
	if [ -f $api_output ] ; then rm $api_output $api_output_header ; fi
}

function ssh_cmd
{
	# Update node IP, just in case...
	NODE_IPV4=$( get_node_IPv4 )

	if [ "$NODE_IPV4" == "null" ] ; then xecho "$NODE_LABEL: Cannot obtain IPv4 for node." ; return 1 ; fi

	clear_known_hosts
	if [ "${NODE_ACTION_ARGCOUNT}" == "0" ] ; then
		xecho "$NODE_LABEL: Opening interactive shell..."
		ssh -q -o StrictHostKeyChecking=no -i $WORKING_DIR/node_$NODE_LABEL.key root@$NODE_IPV4
	else
		ssh -q -o StrictHostKeyChecking=no -i $WORKING_DIR/node_$NODE_LABEL.key root@$NODE_IPV4 $NODE_ACTION_ARG
	fi
}

function get_node_files
{
	# Update node IP, just in case...
	NODE_IPV4=$( get_node_IPv4 )
	local param_source="$1"
	local param_dest="$2"

	if [ "$param_dest" == "" ] ; then param_dest="." ; fi

	if [ "$NODE_IPV4" == "null" ] ; then xecho "$NODE_LABEL: Cannot obtain IPv4 for node." ; return 1 ; fi

	clear_known_hosts
	if [ "${NODE_ACTION_ARGCOUNT}" == "0" ] ; then
		xecho "$NODE_LABEL: GET: Missing arguments. Need to specify at least the source files/path."
	else
		#scp -r -p -o StrictHostKeyChecking=no -i $WORKING_DIR/node_$NODE_LABEL.key root@$NODE_IPV4:$param_source $param_dest
		rsync --compress --recursive --archive --partial --progress \
			-e "ssh -q -o StrictHostKeyChecking=no -i $WORKING_DIR/node_$NODE_LABEL.key" \
			root@$NODE_IPV4:$param_source $param_dest
	fi
}

function put_node_files
{
	# Update node IP, just in case...
	NODE_IPV4=$( get_node_IPv4 )
	local param_source="$1"
	local param_dest="$2"

	if [ "$param_dest" == "" ] ; then param_dest="/tmp" ; fi

	if [ "$NODE_IPV4" == "null" ] ; then xecho "$NODE_LABEL: Cannot obtain IPv4 for node." ; return 1 ; fi

	clear_known_hosts
	if [ "${NODE_ACTION_ARGCOUNT}" == "0" ] ; then
		xecho "$NODE_LABEL: PUT: Missing arguments. Need to specify at least the source files/path."
	else
		#scp -r -p -o StrictHostKeyChecking=no -i $WORKING_DIR/node_$NODE_LABEL.key $param_source root@$NODE_IPV4:$param_dest
		rsync --compress --recursive --archive --partial --progress \
			-e "ssh -q -o StrictHostKeyChecking=no -i $WORKING_DIR/node_$NODE_LABEL.key" \
			$param_source root@$NODE_IPV4:$param_dest
	fi
}

function scp_download
{
	# Update node IP, just in case...
	NODE_IPV4=$( get_node_IPv4 )
	local param_source="$1"
	local param_dest="$2"

	if [ "$param_dest" == "" ] ; then param_dest="." ; fi

	if [ "$NODE_IPV4" == "null" ] ; then xecho "$NODE_LABEL: Cannot obtain IPv4 for node." ; return 1 ; fi

	clear_known_hosts
	if [ "${NODE_ACTION_ARGCOUNT}" == "0" ] ; then
		xecho "$NODE_LABEL: GET: Missing arguments. Need to specify at least the source files/path."
	else
		scp -r -p -o StrictHostKeyChecking=no -i $WORKING_DIR/node_$NODE_LABEL.key root@$NODE_IPV4:$param_source $param_dest
	fi
}

function scp_upload
{
	# Update node IP, just in case...
	NODE_IPV4=$( get_node_IPv4 )
	local param_source="$1"
	local param_dest="$2"

	if [ "$param_dest" == "" ] ; then param_dest="/tmp" ; fi

	if [ "$NODE_IPV4" == "null" ] ; then xecho "$NODE_LABEL: Cannot obtain IPv4 for node." ; return 1 ; fi

	clear_known_hosts
	if [ "${NODE_ACTION_ARGCOUNT}" == "0" ] ; then
		xecho "$NODE_LABEL: PUT: Missing arguments. Need to specify at least the source files/path."
	else
		scp -r -p -o StrictHostKeyChecking=no -i $WORKING_DIR/node_$NODE_LABEL.key $param_source root@$NODE_IPV4:$param_dest
	fi
}

# ----- Action execution --------------
case $NODE_ACTION in
	'driver')           xecho "$NODE_LABEL: driver: $NODE_DRIVER" ;;
	'id')               xecho "$NODE_LABEL: id: $NODE_ID" ;;
	'type')             xecho "$NODE_LABEL: type: $NODE_TYPE" ;;
	'image')            xecho "$NODE_LABEL: image: $NODE_IMAGE" ;;
	'snapshot')         xecho "$NODE_LABEL: snapshot: $NODE_SNAPSHOT" ;;
	'region')           xecho "$NODE_LABEL: region: $NODE_REGION" ;;
	'ip' | 'ipv4')      xecho "$NODE_LABEL: IPv4: $( get_node_IPv4 )" ;;
	'status')           xecho "$NODE_LABEL: status: $( get_node_status )" ;;
	'nodecount')        get_node_count $NODE_ACTION_ARG ;;
	'create')           create_node $NODE_ACTION_ARG ;;
	'delete')           delete_node ;;
	'ssh' | 'cmd')      ssh_cmd ;;
	'get' | 'download') get_node_files $NODE_ACTION_ARG ;;
	'put' | 'upload')   put_node_files $NODE_ACTION_ARG ;;
	'scpget')           scp_download $NODE_ACTION_ARG ;;
	'scpput')           scp_upload $NODE_ACTION_ARG ;;
	* ) 			
		xecho "$NODE_LABEL: WARNING: undefined action '$NODE_ACTION'"
		exit 1
esac

# Clear temp data
for f in $( find $WORKING_DIR -maxdepth 1 -name 'node_'"$NODE_LABEL"'*.out' -type f ) ; do rm $f ; done
for f in $( find $WORKING_DIR -maxdepth 1 -name 'node_'"$NODE_LABEL"'*.out.header' -type f ) ; do rm $f ; done
exit 0