#!/bin/sh

#
# Unified node update payload.
# Works with the following custom images:
#     - ArchLinux 
#     - Debian 9.x 
#     - Debian 10.x
#     - Debian 11.x
#
# Note: string comparison in 'sh' is done with only one equal sign ('=').
#
# Kaleb
# 2022-08-11
#

LOG_FILE="nodenomicon_node_setup.log"
TOOL_LIST="bash curl rsync screen"

PATH_APK=$( command -v apk )
PATH_APTGET=$( command -v apt-get )

if [ "$PATH_APK" != "" ] ; then
	echo "# 'apk' package manager found at '$PATH_APK'" >> $LOG_FILE
	echo "# Updating sources..." >> $LOG_FILE
	$PATH_APK --no-progress update >> $LOG_FILE 2>&1
	$PATH_APK --no-progress add $TOOL_LIST >> $LOG_FILE 2>&1
else
	if [ "$PATH_APTGET" != "" ] ; then
		echo "# 'apt-get' package manager found at '$PATH_APTGET'" >> $LOG_FILE
		echo "# Updating sources..." >> $LOG_FILE
		$PATH_APTGET --quiet --yes update >> $LOG_FILE 2>&1
		$PATH_APTGET --quiet --yes install $TOOL_LIST >> $LOG_FILE 2>&1
	else
		echo "# ERROR: cannot find any compatible package manager." >> $LOG_FILE
		echo "ERROR: cannot find any compatible package manager."
		exit 1
	fi
fi

echo "# Checking for tools..." >> $LOG_FILE
FLAG_MISSING_TOOL="NO"
for t in $TOOL_LIST ; do 
	toolpath=$( command -v $t )
	if [ "$toolpath" = "" ] ; then
		FLAG_MISSING_TOOL="YES"
		echo "# WARNING: '$t' not found!" >> $LOG_FILE
	else
		echo "# INFO: '$t' found at $toolpath" >> $LOG_FILE
	fi
done

echo "# Checking for Nmap..." >> $LOG_FILE
NMAP_CMD=$( command -v nmap )
if [ "$NMAP_CMD" = "" ] ; then
	echo "# INFO: 'nmap' not found!" >> $LOG_FILE
	echo "# Installing OS default 'nmap' from repository..." >> $LOG_FILE
	if [ "$PATH_APK" != "" ] ; then
		$PATH_APK --no-progress add nmap >> $LOG_FILE 2>&1
	else
		$PATH_APTGET --quiet --yes install nmap >> $LOG_FILE 2>&1
	fi
	$NMAP_CMD --version >> $LOG_FILE
else
	echo "# INFO: 'nmap' found at $NMAP_CMD" >> $LOG_FILE
	$NMAP_CMD --version >> $LOG_FILE
fi

if [ "$FLAG_MISSING_TOOL" = "NO" ] ; then
	echo "# OK: setup process ended successfully." >> $LOG_FILE
	echo "OK: setup process ended successfully."
else
	echo "# ERROR: setup process ended with errors." >> $LOG_FILE
	echo "ERROR: setup process ended with errors."
	exit 1
fi
