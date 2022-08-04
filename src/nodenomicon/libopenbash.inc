# -----------------------------------------------------------------------------
# OpenBASH functions
#  
# kaleb
# 2022-08-04
# -----------------------------------------------------------------------------

#
# ---- Initialization ---------------------------------------------------------
# 

TMP_LOG=$( tempfile )


#
# ---- Functions definitions --------------------------------------------------
#

#
# Generates a log time header
# 
function log_ts
{
	echo "$( date "+%Y%m%d.%H%M%S" )"
}

#
# Generates an output to stdout and logs it into $TMP_LOG
#
function xecho () 
{
	if [ ! -z "$_XECHO_PREFIX" ] ; then
		echo -e "#$( log_ts ); ${_XECHO_PREFIX}: $1" 2>&1 | tee --append $TMP_LOG
	else
		echo -e "#$( log_ts ); $1" 2>&1 | tee --append $TMP_LOG
	fi
}

#
# Count lines from a file. Returns 0 if file not found.
# 	$1: file to be counted
# 	
function count_lines
{
	if [ -f $1 ] ; then echo "$( wc -l $1 | cut -d' ' -f1 )" ; else echo "0" ; fi
}

#
# Returns the minimum number from a list of numbers.
# 	$1 ... $N: Number list separated by spaces.
function min () 
{
	local min number

	min="$1"

	for number in "${@:2}"; do
		if ((number < min)); then
			min="$number"
		fi
	done

	printf '%d\n' "$min"
}

#
# Deletes a list of files and dumps message to stdout.
# 	$1 ... $N: File list separated by spaces.
#
function free_resources ()
{
	local file

	xecho "Freeing resources..."
	for file in "${@:1}" ; do
		if [ "$file" != "" ] && [ -f $file ] ; then rm $file ; fi	
	done
	xecho "...done!"
}

#
# Prints an app header, log compatible.
#	$1: Application Banner
#	$2: Author
#	$3: Date time
function header 
{
	xecho "--------------------------------------------------------------------------------"
	xecho " $1"
	xecho "--------------------------------------------------------------------------------"
	xecho " $2"
	xecho " $3"
	xecho "--------------------------------------------------------------------------------"
	xecho ""
}

#
# Gets a parameter value from .cfg file.
#    $1: .cfg file
#    $2: parameter name
#    $3: default parameter (if file not found or empty value)
function get_param
{
	local cfg_file param default_value
	cfg_file=$1
	param="^\s*$2\s*=\s*"
	default_value=$3

	if [ -f $cfg_file ] ; then
		retvalue=$( grep -P '^\s*[^#;]+' $cfg_file | sed -r '/^\s*$/d' | grep -P $param | sed -r "s/$param//g" )
		if [ "$retvalue" != "" ] ; then 
			echo $retvalue
		else
			echo $default_value
		fi
	else
		echo $default_value
	fi
}

#
# Generates a secure password using openssl
function secure_pass_gen
{
	echo $( openssl rand -hex 50 )
}

#
# Returns if an element is contained in an array.
#   $1: needle; the element to be searched
#   $2: haysack; the array
# Example:
#   array=("one" "two" "three" "four")
#   res=$(containsElement "two" "${array[@]}")
#   echo $res
function containsElement () 
{
	local e match="$1"
	shift
	for e; do 
		if [[ "$e" == "$match" ]] ; then 
			echo true
			return 0 
		fi
	done
	echo false
	return 1
}

#
# Creates an empty queue file.
#   $1: queuefile; the file to be created (with full path)
#   $2: node_prefix; the node name prefix to be used for node list
#   $3: node_count; number of nodes to be pre-added to the queue
#   $4: start_at; timestamp for the whole queue file
# Example:
#   createQueueFile queue.json node-3cee0eebcb9d2f5e- 20 2021-01-19T11:36:07-03:00
function createQueueFile () 
{
	local queuefile="$1"
	local node_prefix="$2"
	local node_count="$3"
	local start_at="$4"

	local node_list=""
	[[ "$start_at" == "" ]] && start_at=$( date -Is )

	for node_index in $( seq -f "%05g" 1 $node_count ) ; do
		node_list="$node_list{\"label\":\"${node_prefix}-${node_index}\",\"status\":\"waiting\",\"ipv4\":\"?\",\"region\":\"?\",\"timestamp\":\"$start_at\"},"
	done

	node_list=$( echo $node_list | sed -r 's/,$//g' )

	echo '{"started_at":"'"$start_at"'","queue":['"$node_list"']}' > $queuefile
}

