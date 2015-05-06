#!/bin/bash

#
# chrootISOScript.sh
#
# The customizeISOImage.sh works up to the point of chroot command
# in the prepareAndChroot function. Once the chroot is executed,
# we want this script to run and do all of the tasks inside the
# chroot filesystem. 
#
# Therefore, this script must do all of the customizations for
# the new ISO image as described in the reference below.
#
# Additional files required:
#
# chrootISOScript.sh - This is the script that runs as part of 
#                      chroot to configure the new root. This
#                      script calls chrootISOScript.sh. This
#                      script expects to find chrootISOScript.sh
#                      in the same directory as this script.
#
# newPackages - This text file is a list of Ubuntu packages to
#               load when customizing the ISO image.
#
# Reference: 
#
# https://help.ubuntu.com/community/LiveCDCustomization
#
 
# Name of original and new Ubuntu Desktop ISO image files.
typeset ORIGDESKTOPISO=ubuntu-12.04.5-desktop-amd64.iso
typeset NEWDESKTOPISO=ubuntu-12.04.5-desktop-amd64-app1-custom.iso

# Other script variables
typeset CMD=$(basename $0)
typeset DIR=$(dirname $0)
[[ $DIR == "." ]] && DIR=$PWD
typeset LOG=$DIR/${CMD}.out
typeset WORKINGDIR=/tmp/livecdtmp
typeset ORIGISOIMAGE=${DIR}/${ORIGDESKTOPISO}
typeset NEWISOIMAGE=${DIR}/${NEWDESKTOPISO}
typeset NEWPACKAGES=/newPackages
typeset DEBUG=""
typeset -i RC=0

############
# Functions
############

# Usage function
# NOTE: The code below ignores all tabs when displaying on terminal (i.e. <<-EOF). 
#       So be careful when editing and adding spaces verses tabs.
function usage {
	cat <<-EOF

		Usage: ${CMD} [-v]

		where:
		    -v          verbose output 

	EOF
}

#
# This function logs output to $LOG
# arg1: string to append to logfile
function logit {
	typeset date=$(date +'%Y%m%d%H%M%S:')
	echo "${date} $*" >> $LOG
}

#
# Execute a system command and check the return code. All command
# stdout/stderr is logged and the stdout is echoed back to the client
# when the  -stderr option is used.
# arg1: [optional] -stdout  # echo stdout to terminal
# arg2: and the rest of the line, the system command and arguments
# 
function execCmd {
	typeset arg=$1
	typeset flag="FALSE"
	if [[ ${arg} == "-stdout" ]]; then
		shift
		flag="TRUE"
	fi
	typeset cmd=$*
	typeset rc=0
	typeset stdout=/tmp/stdout$$
	typeset errout=/tmp/errout$$

	# Execute the command
	${cmd} 1> ${stdout} 2> ${errout}
	rc=$?

	# Always log command and output
	logit "CMD: ${cmd} (rc=$rc)"
	cat ${stdout} >> $LOG
	cat ${errout} >> $LOG

	# Only show stdout if requested
	if [[ ${flag} == "TRUE" ]]; then
		cat ${stdout}
	fi

	# If command fails, display back to user.
	if (( rc > 0 )); then
		echo "CMD: ${cmd} (rc=$rc)"
		cat ${errout}
	fi
	rm -f ${errout} ${stdout}
	return ${rc}
}

# This function adds pre-requisit Ubuntu tools/packages needed to perform the 
# actions in this script execution.
function installNewPackages {
	echo -e "\ninstallNewPackages: Adding new packages needed for app1"
	execCmd sudo apt-get -y update || cleanupExit 1
	execCmd sudo apt-get -y upgrade || cleanupExit 1
	# Remove any comments from the file and install the packages
	grep -v '^$\|^\s*\#' ${NEWPACKAGES} | while read line; do
		if $(echo $line | grep "debconf-set-selections" > /dev/null); then
			eval $line || cleanupExit 1
		else
			execCmd sudo apt-get -y install ${line} || cleanupExit 1
		fi
	done

	# Save the app1 package in /home/install
	execCmd mkdir -p /home/install || cleanupExit 1
	execCmd chmod 777 /home/install || cleanupExit 1
}

# This function performs the pre-customization work needed.
function preCustomization {
	${DEBUG}
	typeset rc=0
	echo -e "\npreCustomization: Performing pre-customization work..."

	# Mount file systems
	execCmd /bin/mount -t proc none /proc || cleanupExit 1
	execCmd /bin/mount -t sysfs none /sys || cleanupExit 1
	execCmd /bin/mount -t devpts none /dev/pts || cleanupExit 1

	# Setup some environment variables
	export HOME=/root
	export LC_ALL=C

	# Setup things for apt-get
	execCmd -stdout dbus-uuidgen > /var/lib/dbus/machine-id
	[[ -f /var/lib/dbus/machine-id ]] || {
		echo -e "\nERROR: failed to create /var/lib/dbus/machine-id"
		(( rc += 1 ))
	}
	execCmd dpkg-divert --local --rename --add /sbin/initctl || (( rc += 1 ))
	execCmd ln -s /bin/true /sbin/initctl || (( rc += 1 ))

	# Check for Internet access
	ping -c1 www.google.com > /dev/null || {
		echo -e "\nERROR: cannot access www.google.com or the Internet"
		(( rc += 1 ))
	}

	# Verify the newPackages file is available
	[[ -f ${NEWPACKAGES} ]] || {
		echo -e "\nERROR: unable to open ${NEWPACKAGES}"
		(( rc == 1 ))
	}
	
	# Check for any errors.
	if (( rc > 0 )); then
		echo "Found ${rc} errors, exiting"
		exit #{rc}
	fi
}

function getInstalledPackages {
	dpkg-query -W --showformat='${Installed-Size}\t${Package}\n' | sort -nr
}

# This function cleans up the WORKINGDIR.
#   - Check for mounted filesystems and unmount
#   - Remove any files in this directory
#   - Remove the directory
function cleanup {
	${DEBUG}
	echo "*** Cleaning up the chroot environment... "

	# Cleanup temporary files
	execCmd apt-get clean || cleanupExit 1
	execCmd rm -rf /tmp/* ~/bash_history || cleanupExit 1

	# Restore /etc/hosts and /etc/resolv.conf
	execCmd > /etc/hosts || cleanupExit 1
	execCmd > /etc/resolv.conf || cleanupExit 1

	# Remove machine-id
	execCmd rm -f /var/lib/dbus/machine-id || cleanupExit 1
	execCmd rm -f /sbin/initctl || cleanupExit 1
	execCmd dpkg-divert --rename --remove /sbin/initctl || cleanupExit 1

	# Unmount filesystems
	execCmd umount /proc || umount -lf /proc
	execCmd umount /sys
	execCmd umount /dev/pts

	return 0
}

# This function is called to cleanup and system resources before 
# exiting.
# argument: exit value
function cleanupExit {
	${DEBUG}
	typeset -i exitValue=$1
	[[ -n ${exitValue} ]] || {
		echo -e "\nINTERNAL ERROR: no exitValue proided"
		exit 99
	}
	cleanup
	logit "EXIT_VALUE=${exitValue}"
	exit ${exitValue}
}

#######
# main
#######

#
# Process the options
#
for opt in $*; do
	case ${opt} in
	"-v")		# Verbose
		DEBUG="set -x"
		;;
	*)		# Unsure what this option is
		echo -e "\nERROR: unknown option: ${opt}"
		usage
		exit 1
		;;
	esac
done
${DEBUG}

# This function performs the pre-customization work needed.
preCustomization

# Install new packages needed for app1 and taking before and after
# snapshot of the packages.
getInstalledPackages > /install-pkgs.before
installNewPackages
getInstalledPackages > /install-pkgs.after

cleanupExit 0
