#!/bin/sh

# OpenBash
# Add custom ssh public key to volatile nodes.
# Used because cannot set sshkey with API against snapshot clones.
# Runs on /etc/network/if-up.d as symlink.
# 
# Persist it with:
#  chmod +x /root/add_custom_sshkey.sh
#  cd /etc/network/if-up.d/
#  ln -s /root/add_custom_sshkey.sh 001addcustomsshkey
#
# Kaleb - 2022-08-11

cd /root

user_ssh_key=$( curl -s 'http://169.254.169.254/user-data/user-data' )

if [ "$user_ssh_key" != "" ] ; then 
	mkdir -p /root/.ssh
	chmod 600 /root/.ssh
	echo "$user_ssh_key" > /root/.ssh/authorized_keys
	chmod 700 /root/.ssh/authorized_keys
	echo "[ $( date -Is ) ] Added ssh key from instance metadata" >> startup.log
else
	echo "[ $( date -Is ) ] ERROR: Cannot add ssh key from instance metadata" >> startup.log
fi