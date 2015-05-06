#!/bin/bash

#
# customizeISOImage.sh
#
# This is a script to take the basic Ubuntu Desktop distribution
# ISO image, disassemble it, add customizations, and reassemble
# it into a new ISO image. The new ISO image can be distributed 
# to customers to depoly the app1 software product in a
# non-Internet environment.
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
# 
# 
# Reference: 
#
# This script automates parts of the instructions found on the
# website below in a quick reproduceable mannor to depoly
# new product modifications.
#
# https://help.ubuntu.com/community/LiveCDCustomization
#

# Get the system architecture
typeset ARCH=""
if [[ $(uname -m) == "x86_64" ]]; then
	ARCH=amd64
elif [[ $(uname -m) == "i686" ]]; then
	ARCH=i386
fi

# Name of original and new Ubuntu Desktop ISO image files.
typeset ORIGDESKTOPISO=ubuntu-12.04.5-desktop-${ARCH}.iso
typeset NEWDESKTOPISO=ubuntu-12.04.5-desktop-${ARCH}-app1-custom.iso
typeset NEWDESKTOPTXT=ubuntu-12.04.5-desktop-${ARCH}-app1-custom.txt

# Other script variables
typeset CMD=$(basename $0)
typeset LIVECDCUSTOMIZATION=$(dirname $0)
[[ ${LIVECDCUSTOMIZATION} == "." ]] && LIVECDCUSTOMIZATION=$PWD
typeset BASEDIR=${LIVECDCUSTOMIZATION}/../..
typeset LOG=${LIVECDCUSTOMIZATION}/${CMD}.out
typeset WORKINGDIR=/tmp/livecdtmp
typeset ORIGISOIMAGE=${LIVECDCUSTOMIZATION}/${ORIGDESKTOPISO}
typeset NEWISOIMAGE=${LIVECDCUSTOMIZATION}/${NEWDESKTOPISO}
typeset NEWPACKAGES=${LIVECDCUSTOMIZATION}/newPackages
typeset DEBUG=""

############
# Functions
############

# Usage function
# NOTE: The code below ignores all tabs when displaying on terminal (i.e. <<-EOF). 
#       So be careful when editing and adding spaces verses tabs.
function usage {
	cat <<-EOF

		Usage: ${CMD} [-v] [-cleanup]	

		where:
		    -v          verbose output 
		    -cleanup	Just cleanup resources and exit

	EOF
}

#
# This function logs output to $LOG
# arg1: string to append to logfile
function logit {
	typeset date=$(date +'%m/%d/%Y %H:%M:%S')
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

#
# Verify the necessary items are in place for a successful
# script execution.
#
function sanityChecks {
	${DEBUG}
	typeset rc=0
	echo -e "\nsanityChecks: Performing environmental sanity checks..."

	# Check if the user executed this script as "sudo".
	id | grep "uid=0(root)" > /dev/null && {
		echo -e "\nERROR: It is assumed you have 'sudo' privileges and you will be "
		echo "       prompted to enter your password as necessary. So, please "
		echo "       execute this script as a non-root user."
		(( rc += 1 ))
	}

	# Check the architecture
	[[ -n ${ARCH} ]] || {
		echo -e "\nERROR: unable to determine the system architecture"
		(( rc += 1 ))
	}

	# Check for Internet access
	ping -c1 www.google.com > /dev/null || {
		echo -e "\nERROR: cannot access www.google.com or the Internet"
		(( rc += 1 ))
	}

	# Is original Desktop ISO file exists
	[[ -f ${ORIGISOIMAGE} ]] || {
		echo -e "\nERROR: cannot open ${ORIGISOIMAGE}"
		(( rc += 1 ))
	}

	# Is NEWPACKAGES file exists
	[[ -f ${NEWPACKAGES} ]] || {
		echo -e "\nERROR: cannot open ${NEWPACKAGES}"
		(( rc += 1 ))
	}

	# Remove the new ISO image file if exists from a previous
	# script execution so we will not run out of space.
	execCmd rm -f ${NEWISOIMAGE} ${LIVECDCUSTOMIZATION}/${NEWDESKTOPTXT} || cleanupExit 1

	# Create WORKINGDIR or handle case if WORKINGDIR already exists 
	# from a past execution.
	if [[ -d ${WORKINGDIR} ]]; then
		# Cleanup WORKINGDIR
		cleanupWorkingDir
	fi

	# Create WORKINGDIR
	execCmd mkdir -p ${WORKINGDIR} || cleanupExit 1

	# Make sure there is enough available space to execute this script.
	# Note: I used a one-time while loop because read would not work
	#       by itself. I am not sure why this is. I believe this worked
	#       in ksh.
	typeset -i spaceReq=4000000   # 4G
	typeset -i avail=0
	df ${WORKINGDIR} | tail -1 | while read fs size used avail usedP rest
	do	
		(( avail > spaceReq )) || {
			echo -e "\nERROR: There is not enough filesystem space available in the"
			echo "       ${WORKINGDIR} filesystem to perform this operation. This"
			echo -e "       requires a minimun of 4G available space.\n"
			df -h ${WORKINGDIR}
			(( rc += 1 ))
		}
	done
	
	# Check for any errors.
	if (( rc > 0 )); then
		echo "Found ${rc} errors, exiting"
		exit #{rc}
	fi
}

# This function adds pre-requisit Ubuntu tools/packages needed to perform the 
# actions in this script execution.
function installPreRequisites {
	echo -e "\ninstallPreRequisites: Adding/updating Ubuntu packages needed for this script..."
	typeset pkgsToAdd="squashfs-tools
			genisoimage"
	for pkg in ${pkgsToAdd}; do
		echo "installing: $pkg"
		execCmd sudo apt-get -y install ${pkg} || {
			echo "ERROR: installPreRequisites: failed to add Ubuntu package: ${pkg}, exiting"
			cleanupExit 1
		}
	done
}

# This method extracts the ISO contents and desktop system
function extractISOContents {

	echo -e "\nextractISOContents: extracting the files from the ISO image..."

	# Change to the working directory
	execCmd cd ${WORKINGDIR} || cleanupExit 1

	# Mount the original ISO image file so we can access the contents
	execCmd mkdir mnt || cleanupExit 1
	execCmd sudo mount -o loop ${ORIGISOIMAGE} mnt || cleanupExit 1

	# Copy the ISO contents except the casper squash filesystem into the working directory
	execCmd mkdir extract-cd || cleanupExit 1
	execCmd sudo rsync --exclude=/casper/filesystem.squashfs -a mnt/ extract-cd || cleanupExit 1

	# Copy the casper squash filesystem into the working directory
	execCmd sudo unsquashfs mnt/casper/filesystem.squashfs || cleanupExit 1
	execCmd sudo mv squashfs-root edit || cleanupExit 1
	
	return 0
}

# Prepare For chroot
# Script assumes we are still in ${WORKINGDIR}
function prepareForChroot {

	echo -e "\nprepareAndChroot: chroot and customize new root..."

	# Copy in a valid /etc/hosts and /etc/resolv.conf to the ISO root
	# so we will have Internet access.
	execCmd sudo ls -lL edit/etc/resolv.conf edit/etc/hosts || cleanupExit 1
	execCmd sudo cp /etc/hosts edit/etc/ || cleanupExit 1
	execCmd sudo cp /etc/resolv.conf edit/etc/ || cleanupExit 1
	execCmd sudo ls -L edit/etc/resolv.conf || cleanupExit 1
	execCmd sudo ls -lL edit/etc/resolv.conf edit/etc/hosts || cleanupExit 1

	execCmd sudo mount --bind /dev/ edit/dev || cleanupExit 1
	execCmd sudo cp $LIVECDCUSTOMIZATION/chrootISOScript.sh ${WORKINGDIR}/edit || cleanupExit 1
	execCmd sudo chmod 755 ${WORKINGDIR}/edit/chrootISOScript.sh || cleanupExit 1

	# Copy files into the chroot directory
	execCmd sudo cp ${NEWPACKAGES} ${WORKINGDIR}/edit || cleanupExit 1
	
	# update the sources.list in the chroot directory
	execCmd sudo cp -p ${WORKINGDIR}/edit/etc/apt/sources.list ${WORKINGDIR}/edit/etc/apt/sources.list.bak || cleanupExit 1
	execCmd sudo cp -p /etc/apt/sources.list ${WORKINGDIR}/edit/etc/apt/sources.list || cleanupExit 1
	
	return 0
}

# Perform the chroot
# Script assumes we are still in ${WORKINGDIR}
function executeChroot {
	logit "START sudo chroot edit /chrootISOScript.sh"
	sudo chroot edit /chrootISOScript.sh
	
	# Save the log files from the /chrootISOScript.sh script
	execCmd cp /tmp/livecdtmp/edit/chrootISOScript.sh.out $LIVECDCUSTOMIZATION || cleanupExit 1
	execCmd cp /tmp/livecdtmp/edit/install-pkgs.* $LIVECDCUSTOMIZATION || cleanupExit 1

	# Check the return code of the /chrootISOScript.sh script
	tail -5 ${LIVECDCUSTOMIZATION}/chrootISOScript.sh.out | grep "EXIT_VALUE=0" > /dev/null || {
		echo "ERROR: executeChroot: chrootISOScript.sh returned with a error. see ${LIVECDCUSTOMIZATION}/chrootISOScript.sh.out."
                cleanupExit 1
	}
	logit "COMPLETED sudo chroot edit /chrootISOScript.sh"

	# Cleanup the chroot directory
	execCmd sudo rm -f /tmp/livecdtmp/edit/chrootISOScript.sh.out /tmp/livecdtmp/edit/install-pkgs.* || cleanupExit 1

	# restore the sources.list
	execCmd sudo cp -p ${WORKINGDIR}/edit/etc/apt/sources.list.bak ${WORKINGDIR}/edit/etc/apt/sources.list || cleanupExit 1

	return 0
}

# Prepare and write the new ISO file
# Script assumes we are still in ${WORKINGDIR}
function writeTheNewISO {

	echo -e "\nwriteTheNewISO: generate the new ISO image..."

	# Regenerate the manifest
	execCmd sudo chmod +w extract-cd/casper/filesystem.manifest || cleanupExit 1
	sudo chroot edit dpkg-query -W --showformat='${Package} ${Version}\n' > /tmp/filesystem.manifest
	execCmd sudo mv /tmp/filesystem.manifest extract-cd/casper/filesystem.manifest || cleanupExit 1
	execCmd sudo cp extract-cd/casper/filesystem.manifest extract-cd/casper/filesystem.manifest-desktop || cleanupExit 1
	execCmd sudo sed -i '/ubiquity/d' extract-cd/casper/filesystem.manifest-desktop || cleanupExit 1
	execCmd sudo sed -i '/casper/d' extract-cd/casper/filesystem.manifest-desktop || cleanupExit 1

	# Compress filesystem
	# This step takes a few minutes to run
	execCmd sudo rm -f extract-cd/casper/filesystem.squashfs || cleanupExit 1
	execCmd sudo mksquashfs edit extract-cd/casper/filesystem.squashfs -comp xz -e edit/boot || cleanupExit 1

	# Update the filesystem.size file, which is needed by the installer
	sudo du -sx --block-size=1 edit | cut -f1 > /tmp/filesystem.size
	execCmd sudo mv /tmp/filesystem.size extract-cd/casper/filesystem.size || cleanupExit 1

	execCmd cd extract-cd || cleanupExit 1
	execCmd sudo rm -f md5sum.txt || cleanupExit 1
	find -type f -print0 | sudo xargs -0 md5sum | grep -v isolinux/boot.cat | sudo tee md5sum.txt > /dev/null

	# Create the image file
	execCmd sudo mkisofs -D -r -V "$IMAGE_NAME" -cache-inodes -J -l -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o ${NEWISOIMAGE} . || cleanupExit 1

	# Calculate the md5sum and write it to a file
	execCmd cd  ${LIVECDCUSTOMIZATION} || cleanupExit 1
	execCmd -stdout md5sum ${NEWDESKTOPISO} > ${NEWDESKTOPTXT}

	return 0
}

# This function cleans up the WORKINGDIR.
#   - Check for mounted filesystems and unmount
#   - Remove any files in this directory
#   - Remove the directory
function cleanupWorkingDir {
	${DEBUG}
	echo "cleanupWorkingDir: Cleaning up ${WORKINGDIR}"

	# Make sure the chroot mounted FS are unmounted
	typeset mountpoints="/proc /sys /dev/pts"
	for mp in ${mountpoints}
	do
		if [[ -d ${WORKINGDIR}/edit ]]; then
			sudo chroot ${WORKINGDIR}/edit umount $mp > /dev/null 2>&1
		fi
	done
	
	# Make sure the ISO mounted FS is unmounted
	mountpoints="${WORKINGDIR}/edit/dev ${WORKINGDIR}/mnt"
	for mp in ${mountpoints}
	do
		sudo umount $mp > /dev/null 2>&1
	done

	# Remove the working directory
	execCmd sudo rm -fr ${WORKINGDIR}

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
	
	case ${exitValue} in
	0)
		# Remove all used resources and exit

		# Remove WORKINGDIR
		cleanupWorkingDir
		;;
	*)
		# Keep resources open for debugging and just exit

		;;
	esac
	if (( exitValue == 0 )); then
		echo -e "\nSUCCESS!"
	else
		echo -e "\nFAILED! - see log files for details!"
	fi

	echo -e "\nScript details can be found in $LIVECDCUSTOMIZATION directory *.out files"
	
	logit "COMPLETED ${CMD} (rc=${exitValue})"
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
	"-cleanup")	# Just cleanup and exit
		logit "START: ${CMD} -cleanup"
		cleanupExit 0
		;;
	*)		# Unsure what this option is
		echo -e "\nERROR: unknown option: ${opt}"
		usage
		exit 1
		;;
	esac
done
${DEBUG}
# Clear the logfile
echo "START ${CMD}" > $LOG

# Verify the necessary items are in place for a successful script execution.
sanityChecks

# Install any pre-requisit tools needed for this process.
installPreRequisites

# Extract the original ISO file contents into a working directory.
extractISOContents

# Prepare and Chroot.
prepareForChroot

# Execute chroot to perform updates
executeChroot

# Write the ISO file
writeTheNewISO

cleanupExit 0
