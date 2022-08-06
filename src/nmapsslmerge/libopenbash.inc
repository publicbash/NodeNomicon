# -----------------------------------------------------------------------------
# OpenBASH functions
#  
# kaleb
# 2022-08-06
# -----------------------------------------------------------------------------

#
# ---- Initialization ---------------------------------------------------------
# 

TMP_LOG=$( mktemp )


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

