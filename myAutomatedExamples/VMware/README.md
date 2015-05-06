
This directory contains scripts I created to automate VMware ESXi server tasks.
These are examples only and require additional environment setup and scripts to actually execute.


OVERVIEW:
	This file contains instructions for importing and exporting OVF files to/from 
	the ESXI5.5 VMware. The following is a quick overview of the steps:


SETUP YOUR ENVIRONMENT:
  Enable the ESXi SSH and remote SSH capability:
	- Visit: http://kb.vmware.com/selfservice/microsites/search.do?language=en_US&cmd=displayKC&externalId=2004746

  Setup passwordless access to the ESXi:
	- Visit: http://kb.vmware.com/selfservice/microsites/search.do?language=en_US&cmd=displayKC&externalId=1002866

  Required files (/home/sophia/trunk/vmware):
	- The Application package file: app1_<version>_<arch>.deb
	- The Application package md5sum file: app1_<version>_<arch>.txt
	- The Application license file: <anyname>.lic
	- The existing OVF file: <OVF directory name>/<OVF name>.mf, <OVF name>.ovf, & <OVF name>.vmdk files
	 
PROCEDURE:

To IMPORT an OVF file...
========================

  On the Development Server:
	1) Setup your environment, required files, etc. in the /home/sophia/trunk/vmware directory.
	2) cd /home/sophia/trunk/vmware
	3) Execute createOvfImage.sh -import
		-  sanityChecks
		-  Installs any required Ubuntu packages
		-  Deploys and starts up the demo OVF file
		-  Retrieves the Demo IP address
		-  Installs/upgrades the VMware tools on the demo VM
		-  Copies scripts, .lic, & sophia install files to demo VM

What to do next when creating a VM OVF image...
===============================================

  On the Demo VM:
	1) cd ~/install
	2) Execute: '~/install/installApp1.sh' to remove/install App1 & license 
	3) Manually, start the App1 application and verify operation
	4) When done, execute: '~/install/cleanupExit.sh' to shutdown Application, cleanup & shutdown Ubuntu

To EXPORT an OVF file...
========================

  On the Development Server:
	1) Execute: 'createOvfImage.sh -export' to create the new OVF image

If manually setting up VMware virtual OS...
===========================================

  If manually installing a fresh copy of Ubuntu (in VM), you can skip the IMPORT step and EXPORT the OVF
  once you completed the installation of Ubuntu, Application, and configuration:

	1) Manually install a new Ubuntu OS (either 32 or 64 bit) without installing any Ubuntu updates
	2) On new VM, mkdir ~/install, cd ~/install
	3) Copy install_sophia_deps.sh, newPackages to ~/install on new VM
	4) On new VM, execute ./install_sophia_deps.sh -c, this will update/upgrade & load Application dependent packages
	   and create the latest sophia_dep_pkgs_<arch> package from customer delevery
	5) On new VM and do the following:
		- Manually copy scripts from trunk/vmware to ~/install on VM 
		- Execute: cd ~/install
		- Execute: installApp1.sh
		- Verify the demo software
		- Execute: cleanupExit.sh
	6) On the Development Server, do the EXPORT step above.

