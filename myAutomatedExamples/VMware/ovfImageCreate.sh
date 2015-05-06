#!/bin/bash

#
# ovfImageCreate
#
#
# This script exports VMware ESXi virtual machine image and converts 
# it into an OVF file or imports an existing OVF file and creates a new
# virtual machine. The OVF files can be played using VMware player on Windows or 
# Linux OS You must take into consideration the size of the virtual machine and verify
# the OVF file will fit into the filesystem. 
#
# This script uses associated arrays to store your environment variables and 
# are retrive and saved during the script execution so you do not need to enter 
# them with each execution. 
#
# See the usage function for script execution details.
#

typeset CMD=$(basename $0)
typeset DIR=$(dirname $0)
[[ $DIR = "." ]] && DIR=$PWD

# Config file that remembers previous entries
typeset MYENV=$DIR/.ovfImageCreate_env
typeset IMPORTDONE=$DIR/.ovfImageCreate.importdone

# VMware credentials
declare -A myEnv		# Associative array holding environment name-value pairs
declare -A vm			# Associative array holding VM name-index pairs
typeset mySavedKeys="VMware_IP VMware_User VMware_Password VMware_VM_Import_OVF_Filename VMware_VM_Export_OVF_Filename Guest_User Guest_Password Guest_IP"

# Other script variables
typeset LOG=${DIR}/${CMD}.out
typeset WORKINGDIR=/tmp/livecdtmp
typeset DEBUG=""
typeset -i ACCEPTDEFAULTPROMPTS=1	# If true, accept all default prompts
typeset -i SKIPDELETEIMPORT=1		# If true, skip delete/import of VM
typeset -i IMPORTOVFFILE=1		# If true, import the OVF file
typeset -i EXPORTOVFFILE=1		# If true, export the OVF file
typeset SSH="/usr/bin/ssh -oStrictHostKeyChecking=no "
typeset GUESTIP=""			# IP address of VM

# Files to copy
typeset SOPHIADEBFILE=""
typeset SOPHIATXTFILE=""
typeset SOPHIALICENSEFILE=""

############
# Functions
############

# Usage function
# NOTE: The code below ignores all tabs when displaying on terminal (i.e. <<-EOF). 
#       So be careful when editing and adding spaces verses tabs.
function usage {
	cat <<-EOF

		Usage: ${CMD} [-v] [-y] [-skip]	<-import or -export>

		where:
		    -v          verbose output 
		    -y          accept all of the default script prompts
		    -skip	skip delete and import of VM (test use)
		    -import	import the OVF file and create a new VM
		    -export	export the VM and create the OVF file

	EOF
}

#
# This function logs output to $LOG
# arg1: [optional] -stdout  # echo stdout to terminal
# arg2: snd the rest of the line append to logfile
function logit {
	if [[ ${1} == "-stdout" ]]; then
		shift
		echo $*
	fi
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
	typeset stdoutFlag="FALSE"
	typeset silentFlag="FALSE"
	if [[ ${arg} == "-stdout" ]]; then
		shift
		stdoutFlag="TRUE"
	elif [[ ${arg} == "-silent" ]]; then
		shift
		silentFlag="TRUE"
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
	if [[ ${stdoutFlag} == "TRUE" ]]; then
		cat ${stdout}
	fi

	# If command fails, display back to user.
	if (( rc > 0 )) && [[ ${silentFlag} == "FALSE" ]]; then
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
	echo "  Checking user has root access"
	id | grep "uid=0(root)" > /dev/null && {
		echo -e "\nERROR: It is assumed you have 'sudo' privileges and you will be "
		echo "       prompted to enter your password as necessary. So, please "
		echo "       execute this script as a non-root user."
		(( rc += 1 ))
	}

	# Make sure all environment variables are defined
	echo "  Checking environment variables are setup"
	for k in $mySavedKeys; do
		[[ -n ${myEnv[$k]} ]] || {
			echo "  ERROR: $k is not defined"
			(( rc += 1 ))
		}
	done

	# Make sure the script can access the VMware Server via SSH public key authentication
	echo "  Attempting to access the VMware Esxi console via SSH with public key authentication"
	execCmd $SSH ${myEnv[VMware_User]}@${myEnv[VMware_IP]} pwd || {
		cat <<-EOF

		    Unable to connect to '${myEnv[VMware_IP]}' with user '${myEnv[VMware_User]}'.
		    1) Make sure the VMware user and IP is correct.
		    2) Make sure the VMware shell access is enabled:
		       See http://kb.vmware.com/selfservice/microsites/search.do?language=en_US&cmd=displayKC&externalId=2004746
		    3) Make sure the SSH public key authentication is setup:
		       See http://blogs.vmware.com/vsphere/2012/07/enabling-password-free-ssh-access-on-esxi-50.html

		EOF
		(( rc += 1 ))
	}

	# Make sure the application package files exists
	echo "  Checking for the application package files in ${DIR} directory."
	SOPHIADEBFILE=$(ls ${DIR}/app1_*.deb)
	[[ -f ${SOPHIADEBFILE} ]] || {
		echo -e "    ERROR: unable to open ${DIR}/app1_*.deb file"
		(( rc += 1 ))
	}
	SOPHIATXTFILE=$(ls ${DIR}/app1_*.txt)
	[[ -f ${SOPHIATXTFILE} ]] || {
		echo -e "    ERROR: unable to open ${DIR}/app1_*.txt files"
		(( rc += 1 ))
	}

	# Make sure the app1 license file exists
	echo "  Checking for the application license file in ${DIR} directory."
	SOPHIALICENSEFILE=$(ls ${DIR}/*.lic)
	[[ -f ${SOPHIALICENSEFILE} ]] || {
		echo -e "    ERROR: unable to open application license ${DIR}/*.lic file"
		(( rc += 1 ))
	}

	# Make sure the current OVF package exists
	echo "  Checking for the current OVF package in ${DIR} directory."
	execCmd -silent ls -d ${DIR}/${myEnv[VMware_VM_Import_OVF_Filename]} || {
		echo -e "    ERROR: unable to open the current OVF ${DIR}/${myEnv[VMware_VM_Import_OVF_Filename]} directory"
		(( rc += 1 ))
	}
	execCmd -silent ls ${DIR}/${myEnv[VMware_VM_Import_OVF_Filename]}/*.vmdk || {
		echo -e "    ERROR: unable to open the current OVF ${DIR}/${myEnv[VMware_VM_Import_OVF_Filename]}/*.vmdk file"
		(( rc += 1 ))
	}

	# Make sure the ovftool is installed
	echo "  Checking if the ovftool package is installed."
	execCmd -silent /usr/bin/ovftool --version || {
		echo -e "    ERROR: The ovftool does not seem to be installed."
		echo -e "    See https://www.vmware.com/support/developer/ovf/ovf400/ovftool-400-userguide.pdf"
		(( rc += 1 ))
	}

	# Check for any errors.
	if (( rc > 0 )); then
		echo "Found ${rc} errors, exiting"
		exit ${rc}
	fi
}

# This function adds pre-requisit Ubuntu tools/packages needed to perform the 
# actions in this script execution.
function installPreRequisites {
	${DEBUG}
	echo -e "\nInstallPreRequisites: Adding/updating Ubuntu packages needed for this script..."
	typeset pkgsToAdd=""
	for pkg in ${pkgsToAdd}; do
		echo "installing: $pkg"
		execCmd sudo apt-get -y install ${pkg} || {
			echo "ERROR: installPreRequisites: failed to add Ubuntu package: ${pkg}, exiting"
			cleanupExit 1
		}
	done
	return 0
}

# Show the Environment file and prompt the user to change or accept
function editEnv {
	${DEBUG}
	echo -e "\nAccept the default or enter new values (enter=accept default, type in new value to change, q=quit):"
	for k in $mySavedKeys; do
		echo -e "  Enter the ${k} [default=${myEnv[$k]}]: \c"
		read ANS
		[[ ${ANS} == "q" ]] && exit 1
		[[ ${ANS} == "" ]] && continue
		myEnv[$k]=${ANS}
	done
	return 0	
}

# Write the $MYENV file to save the entries
function saveEnv {
	${DEBUG}
	rm -f $MYENV
	for k in "${!myEnv[@]}"; do
		echo $k=${myEnv[$k]} >> $MYENV
	done
	logit "Saved the environment values"
	return 0
}

# Read in environment file if exists
function readEnv {
	${DEBUG}
	typeset -i count=0
	typeset key=""
	typeset value=""
	[[ -f $MYENV ]] && {
		# Read the environment entries into the array
		logit "Reading the environment file $MYENV"
		while read line; do
			saveIFS=$IFS
			IFS="="
			set -- $line
			key=$1
			value=$2
			count=${#*}
			IFS=$saveIFS
			logit "$MYENV: size: ${#*}  key: $key  value: $value"
			if (( count == 2 )); then
				myEnv[$key]="$value"
			elif (( count == 1 )); then
				myEnv[$key]=""
			else
				echo -e "\nERROR: $MYENV: bad line: $line"
				exit 1
			fi
		done < $MYENV
	}

	# Setup the Guest Environment variables by default
	[[ -n ${myEnv[Guest_User]} ]] ||  myEnv[Guest_User]="app1"
	[[ -n ${myEnv[Guest_Password]} ]] || myEnv[Guest_Password]="password"
	[[ -n ${myEnv[Guest_IP]} ]] || myEnv[Guest_IP]="0.0.0.0"
	return 0
}

# Retrieve a list of VM's and save the name and index
function getListOfVm {
	${DEBUG}
	typeset tmpfile=/tmp/getListOfVm$$
	typeset -i count=0
	typeset key=""
	typeset value=""

	# Zero the vm array
	for k in "${!vm[@]}"; do
		unset vm["$k"]
	done

	# Get the list of VM's
	execCmd -stdout $SSH ${myEnv[VMware_User]}@${myEnv[VMware_IP]} vim-cmd vmsvc/getallvms > ${tmpfile} || {
		echo -e "\nERROR: $SSH ${myEnv[VMware_User]}@${myEnv[VMware_IP]} vim-cmd vmsvc/getallvms FAILED"
		return 1
	}
	while read line; do
		# $line sample output:
		#
		# Vmid   Name                                    File                       Guest OS      Version   Annotation
		# 10     test1                   [datastore1] test1/test1.vmx             ubuntu64Guest   vmx-08

		# Remove header from VM list
		echo $line | grep "^Vmid" > /dev/null && continue

		# key: VM name (2nd column) 
		#   cut:            removes "[datastore..." and rest of line
		#   first sed arg:  removes ^one or more numbers and saves second column
		#   second sed arg: removes any spaces at the end of second column
		key=$(echo $line | cut -d'[' -f1 | sed -e 's/^[0-9]*[ ]*\(.*$\)/\1/' -e 's/[ ]*$//')

		# value: VM index (1st column) 
		#   cut:  removes first space and rest of line leaving just the index
		value=$(echo $line | cut -d' ' -f1)
		logit "getListOfVm: key=$key  value=$value"

		# Save name/index in associative array
		vm["$key"]="$value"
	done < ${tmpfile}
	rm -f ${tmpfile}
	return 0
}

# Rename the OVF file
function renameOVF {
	${DEBUG}
	typeset importName=${myEnv[VMware_VM_Import_OVF_Filename]}
	typeset exportName=${myEnv[VMware_VM_Export_OVF_Filename]}

	# If the names are the same do nothing
	[[ ${importName} == ${exportName} ]] && return 0

	logit -stdout "Renaming the OVF file: ${importName} => ${exportName}"

	if [[ -d $DIR/${exportName} ]]; then
		execCmd rm -f $DIR/${exportName}/${exportName}*
	else
		execCmd mkdir -p $DIR/${exportName}
	fi
	cd $DIR/${exportName}
	execCmd /usr/bin/ovftool $DIR/${importName}/${importName}.ovf ${exportName}.ovf || return 1
	cd $DIR

	return 0
}

# Delete a Virtual Machine if exists
# arg1: VM name
function deleteVM {
	${DEBUG}
	typeset guestInfo=/tmp/importOVF$$
	typeset vmName="$1"

	logit "deleteVM: Deleting VM: $vmName if exists"
	# Get a list of the current VM's
	logit "importOVF: Retrieving inventory of VM's"
	getListOfVm || return 1

	# If a current VM list contains $vmName, then delete it so we can reload it
	# Delete the VM
	[[ -n ${vm[${vmName}]} ]] && {
		(( ACCEPTDEFAULTPROMPTS == 0 )) || {
			while :; do
				echo -e "\nDelete VM: ${vmName}? (y/n, q=quit):"
				read ANS
				case $ANS in
					y|Y) 	break;;
					q|Q)	exit 0;;
					n|N)	return 99;;
					*)	echo -e "\nUnknown response: $ANS";;
				esac
			done
		}
		echo "  Removing existing $vmName VM"
		logit "importOVF: VM=${vmName} exists, deleting it"
		# Power off the VM if up
		state=$(execCmd -stdout $SSH ${myEnv[VMware_User]}@${myEnv[VMware_IP]} vim-cmd vmsvc/power.getstate ${vm[${vmName}]}) || return 1
		echo $state | grep "Powered on" > /dev/null && {
			execCmd $SSH ${myEnv[VMware_User]}@${myEnv[VMware_IP]} vim-cmd vmsvc/power.off ${vm[${vmName}]} || return 1
		}
		# Delete the VM
		execCmd $SSH ${myEnv[VMware_User]}@${myEnv[VMware_IP]} vim-cmd vmsvc/destroy ${vm[${vmName}]} || return 1
	}
	return 0
}

# Power Off the VM if it is not already off.
# arg1: VMID of VM to power Off.
function powerOffVm {
	typeset vmid=$1
	typeset state=""

	[[ -n ${vmid} ]] || {
		logit -stdout "ERROR: powerOffVm: no VMID provided"
		return 1
	}
	
	echo "  Checking $vmName VM power state"
	# Power off the VM if up
	state=$(execCmd -stdout $SSH ${myEnv[VMware_User]}@${myEnv[VMware_IP]} vim-cmd vmsvc/power.getstate ${vmid}) || return 1
	echo $state | grep "Powered on" > /dev/null && {
		logit -stdout "  powerOffVm: power down VM=${vmName}"
		execCmd $SSH ${myEnv[VMware_User]}@${myEnv[VMware_IP]} vim-cmd vmsvc/power.off ${vmid} || return 1
	}
	return 0
}

# Power On the VM if it is not already off.
# arg1: VMID of VM to power On
function powerOnVm {
	typeset vmid=$1
	typeset state=""

	[[ -n ${vmid} ]] || {
		logit -stdout "ERROR: powerOnVm: no VMID provided"
		return 1
	}
	
	echo "  Checking $vmName VM power state"
	# Power on the VM if down
	state=$(execCmd -stdout $SSH ${myEnv[VMware_User]}@${myEnv[VMware_IP]} vim-cmd vmsvc/power.getstate ${vmid}) || return 1
	echo $state | grep "Powered off" > /dev/null && {
		logit -stdout "  powerOnVm: power on VM=${vmName}"
		execCmd $SSH ${myEnv[VMware_User]}@${myEnv[VMware_IP]} vim-cmd vmsvc/power.on ${vmid} || return 1
		# Allow time for the OS to come up
		sleep 30
	}
	return 0
}

# Upgrade the VMware tools
function upgradeVMwareTools {
	typeset vmName=""
	vmName=${myEnv[VMware_VM_Export_OVF_Filename]}
	echo "  Upgrade the guest $vmName VMware tools"
	execCmd $SSH ${myEnv[VMware_User]}@${myEnv[VMware_IP]} vim-cmd vmsvc/tools.upgrade ${vm[${vmName}]} || return 1
	return 0
}

# Import the OVF file as a Virtual machine
function importOVF {
	${DEBUG}
	typeset guestInfo=/tmp/importOVF$$
	typeset vmName=""

	logit -stdout "Importing OVF file"
	# Get a list of the current VM's
	logit "importOVF: Retrieving inventory of VM's"
	getListOfVm || return 1

	# If a current VM list contains $vmName, then delete it so we can reload it
	# unless $SKIPDELETEIMPORT is true.
	vmName=${myEnv[VMware_VM_Export_OVF_Filename]}
	(( SKIPDELETEIMPORT == 0 )) || {
		# Delete the VM
		[[ -n ${vm[${vmName}]} ]] && deleteVM "${vmName}"
 
		# Import the OVF
		echo "  Importing $vmName OVF file (Takes a few minutes... See VMware client for Deploy status)"
		execCmd /usr/bin/ovftool ${vmName}/${vmName}.ovf vi://${myEnv[VMware_User]}:${myEnv[VMware_Password]}@${myEnv[VMware_IP]}
		sleep 2
	
		# Get the new list of the current VM's
		logit "importOVF: Retrieving the new inventory of VM's"
		getListOfVm || return 1
	}

	# Power up VM
	powerOnVm ${vm[${vmName}]} || return 1

	# Get the Guest IP address
	echo "  Retrieve the guest $vmName VM IP"
	execCmd -stdout $SSH ${myEnv[VMware_User]}@${myEnv[VMware_IP]} vim-cmd vmsvc/get.guest ${vm[${vmName}]} > ${guestInfo} || return 1
	GUESTIP=$(cat ${guestInfo} | grep -m 1 "ipAddress = \"" | cut -d'"' -f2)
	logit -stdout "GUESTIP=${GUESTIP}"	
	myEnv[Guest_IP]="${GUESTIP}"
	
	# Upgrade the VMware tools
	upgradeVMwareTools || return 1

	rm -f ${guestInfo}
	return 0
}

# Update ovf file and turn on 3D support
function enable3DSupport {
	${DEBUG}
	typeset vmName=${myEnv[VMware_VM_Export_OVF_Filename]}
	ovfFile="${DIR}/${vmName}/${vmName}.ovf"
	mfFile="${DIR}/${vmName}/${vmName}.mf"
	echo "  Edit the .ovf file to enable 3D support"
	
	[[ -f ${ovfFile} ]] || {
		echo -e "\nERROR: unable to open ${ovfFile}"
		return 1
	}

	[[ -f ${mfFile} ]] || {
		echo -e "\nERROR: unable to open ${mfFile}"
		return 1
	}

	# Modify the .ovf file
	# Change this line from: <vmw:Config ovf:required="false" vmw:key="enable3DSupport" vmw:value="false"/>
	# To:                    <vmw:Config ovf:required="false" vmw:key="enable3DSupport" vmw:value="true"/>
	logit "enable3DSupport: enabling 3D support"
	sed -i -e 's@\("enable3DSupport" vmw:value=\)"false"@\1"true"@' ${ovfFile} || {
		echo -e "\nsed -i -e 's@\("enable3DSupport" vmw:value=\)"false"@\1"true"@' ${ovfFile} FAILED"
		return 1
	}
	
	# Now update the SHA-1 sum in the .mf file
	newSHA1=$(sha1sum ${ovfFile} | cut -d' ' -f1)
	sed -i -e "s/\(SHA1($(basename ${ovfFile}))= \).*$/\1${newSHA1}/" ${mfFile} || {
		echo -e "\nsed -i -e \"s/\(SHA1(${ovfFile})= \).*$/\1${newSHA1}/\" ${mfFile} FAILED"
		return 1
	}		
	return 0
}

# Export the Virtual Machine to a OVF file
function exportOVF {
	${DEBUG}
	typeset guestInfo=/tmp/importOVF$$
	typeset importName=""
	typeset exportName=""
	typeset vmName=${myEnv[VMware_VM_Export_OVF_Filename]}
	echo -e "\nExporting OVF file"

	# Get a list of the current VM's
	logit "exportOVF: Retrieving inventory of VM's"
	getListOfVm || return 1

	# Make sure the VM is powered on
#	powerOnVm ${vm[${vmName}]} || return 1

	# Install the VMware Tools
#	upgradeVMwareTools || return 1

	# Make sure the VM is shut down
	powerOffVm ${vm[${vmName}]} || return 1
	
	# Export the OVF
	echo "  Exporting $vmName OVF file (Takes a few minutes... See VMware client for Deploy status)"

	# Make sure the directory exists
	mkdir -p ${DIR}/${vmName}
	cd ${DIR}/${vmName}/
	execCmd rm -f ${vmName}* || return 1
	execCmd /usr/bin/ovftool vi://${myEnv[VMware_User]}:${myEnv[VMware_Password]}@${myEnv[VMware_IP]}/${vmName} ${vmName}.ovf || {
		return 1
	}
	return 0
}

# Copy the files to the demo VM
function copyFiles {
	${DEBUG}

	cat <<-END

	Copy Files to Demo VM:

	This next step is to copy a handful of files to the DEMO VM server. If
	the Public Key Authenication is setup where the public key from this 
	server (~/.ssh/id_rsa.pub) is copied to ~/.ssh/authorized_keys file on 
	the Demo VM, the files will be copied whithout any prompts. 
	Otherwise, you may be prompted to enter the user's password. 

	END

	FILES="${SOPHIADEBFILE} 
		${SOPHIATXTFILE}
		${SOPHIALICENSEFILE}
		${DIR}/cleanupExit.sh
		${DIR}/installApp1.sh"

	echo "  Copy files to the guest VM"

	# Make or clean install directory
	[[ -d ${DIR}/install ]] && rm -fr ${DIR}/install/* || mkdir -p ${DIR}/install

	# Put the files to be copied tn the install directory
	for i in ${FILES}; do
		cp -p $i ${DIR}/install/
	done

	# Copy all files in the install directory to the Demo VM
	scp ${DIR}/install/* ${myEnv[Guest_User]}@${myEnv[Guest_IP]}:./install/ || {
		logit -stdout "ERROR: scp $i ${myEnv[Guest_User]}@${myEnv[Guest_IP]}:./install/ FAILED"
		return 1
	}
	rm -fr ${DIR}/install
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

	echo -e "\nScript details can be found in $DIR directory *.out files"
	
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
	"-y")		# Accept default prompts
		ACCEPTDEFAULTPROMPTS=0
		;;
	"-skip")	# Skip Delete & import VM
		SKIPDELETEIMPORT=0
		;;
	"-import")	# Skip Delete & import VM
		IMPORTOVFFILE=0
		;;
	"-export")	# Skip Delete & import VM
		rm -f ${IMPORTDONE}
		EXPORTOVFFILE=0
		;;
	*)		# Unsure what this option is
		echo -e "\nERROR: unknown option: ${opt}"
		usage
		exit 1
		;;
	esac
done
${DEBUG}
[[ -f ${IMPORTDONE} ]] && {
	echo -e "\nThe OVF import has already been executed. Did you really mean '$CMD -export'?"
	echo "If you really want to continue, execute: rm -f ${IMPORTDONE} & reexecute this command."
	exit 2
}

# Clear the logfile
> $LOG
logit "START ${CMD}"

# Read in environment file if exists.
readEnv

# Give the user the opportunity to change the environment values if not using -a option.
(( ACCEPTDEFAULTPROMPTS == 0 )) || editEnv

if (( EXPORTOVFFILE == 0 )); then
	# Export the OVF file
	exportOVF || cleanupExit 1

	# Enable 3D support
	enable3DSupport || cleanupExit 1

elif (( IMPORTOVFFILE == 0 )); then
	# Verify the necessary items are in place for a successful script execution.
	sanityChecks

	# Install Ubuntu required packages
	installPreRequisites || cleanupExit 1

	# Create a new OVF with the correct name
	renameOVF || cleanupExit 1

	# Import the OVF file
	importOVF || cleanupExit 1

	# Copy install and cleanup files to the VM
	copyFiles || cleanupExit 1

	# Import completed
	touch > ${IMPORTDONE}
else
	echo -e "\nplease either select import or export."
	usage

	# Save the current environment values for next execution.
	saveEnv

	cleanupExit 1
fi

# Save the current environment values for next execution.
saveEnv

cleanupExit 0

