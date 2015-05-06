
This directory contains the files necessary to customize a
standard released Ubuntu desktop ISO file. Executing the 
script produces a new customized ISO file that includes
all of the packages defined in the "newPackages" file. Other
customizations can be done and are documented in the reference
below. 

REFERENCE:

  https://help.ubuntu.com/community/LiveCDCustomization

ASSUMPTIONS:

- This custom package picks up the Application .deb file from the
  ../installer directory and includes it under /home/install
  when the ISO file is installed. So it is assumed the application
  build has been done and the application .deb package created. 

- It is assumed you have at least 4GB of free disk space to 
  run these scripts. The script will check this.

- It is assumed you have sudo priviledges and that you 
  execute this script as non-sudo. The script will check.

- It is assumed you have Internet access to be able to download
  all of the additional packages and updates. The script will
  check.

- All of the files, including the initial .ISO file, is located
  in this ./liveCDCustomization directory. 

TESTING:

- 08/26/2014, this script has been tested to successfully 
  customize a ubuntu-12.04.4-desktop-amd64.iso image.

PROCEDURE:

1)  Change directory to /home/app1/liveCDCustomization

2)  Make sure customizeISOImage.sh is executable 
    (i.e. chmod 775 customizeISOImage.sh).

3)  Make sure the app1 build is done and the packaging step 
    completed. (i.e. ../installer/app1.*.deb file exists)

4)  Copy the ubuntu-12.04.4-desktop-amd64.iso file into the 
    /home/app1/liveCDCustomization directory.

5)  Execute: customizeISOImage.sh

    NOTES:

    The script takes approximately 10 minutes to complete depending
    upon your internet and computer speed. 

    Upon a successful completion, all resources are cleaned up and
    the new ISO image, md5sum .txt file, listing of included Ubuntu
    packages before and after, and log files (*.out) are written to
    the ./liveCDCustomization directory.

    The script verifies successful execution of all its commands and
    will immediately exit upon error leaving mounted filesystems 
    behind. This is so you can debug the issues as needed.
    EXECUTE: "customizeISOImage.sh -cleanup" to cleanup the resources
    left behind once you are done debugging. IF YOU FAIL TO CLEANUP 
    MOUNTED MOUNT POINTS MAY CAUSE YOUR UBUNTU TO BECOME UNSTABLE.

FILES:

- customizeISOImage.sh: This is the main script that gets executed to
                        start the process of customizing the ISO image.

- chrootISOScript.sh: The customizeISOImage.sh script unpacks the initial
                      ISO image and sets up a mini Ubuntu filesystem. The
                      script then does a chroot and passes control to the
                      chrootISOScript.sh script to do all of the ISO 
                      customizations. Once done, the the control is passed
                      back to the main script to complete all of the tasks.

- newPackages: This file contains all of the new packages added to the
               ISO image. To add an additional package, just add it to this
               file.

*** files produced via script execution ***

- customizeISOImage.sh.out: The detailed execution on customizeISOImage.sh
                            script.

- chrootISOScript.sh.out: The detailed execution of the chrootISOScript.sh
                          script.

- install-pkgs.*: This files contain a snapshot of the packages before and
                  and after the customization.


                      

    
