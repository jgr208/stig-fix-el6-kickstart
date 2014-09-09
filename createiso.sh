#!/bin/bash
###############################################################################
# STIG FIX DVD CREATOR
#
# This script was written by Frank Caviggia, Red Hat Consulting
# Last update was 21 January 2014
# This script is NOT SUPPORTED by Red Hat Global Support Services.
# Please contact Josh Waldman for more information.
#
# Author: Frank Caviggia (fcaviggi@redhat.com)
# Copyright: Red Hat, (c) 2013
# Version: 1.2.0
# License: GPLv2
# Description: Kickstart Installation of RHEL 6 with DISA STIG
###############################################################################

# for debugging
set -x

# GLOBAL VARIABLES
readonly DIR=$(pwd)
readonly CLASSIFICATION_BANNER_FILE_NAME=classification-banner.py

cleanup () {
    umount /rhel
    rm -rf /rhel
}

# USAGE STATEMENT
usage() {
cat << EOF
usage: $0 -b <classification-banner path> -r <stig-fix.rpm> -i rhel-server-6.5-x86_64-dvd.iso

  -b    path to classification-banner.py
  -r    path to the stig-fix rpm
  -i    path to the THEL 6.4+ iso file

DISA STIG Installer Kickstart RHEL 6.4+

Customizes a RHEL 6.4+ x86_64 Server or Workstation DVD to install
with the following hardening:

  - DISA STIG for Red Hat Enterprise Linux
  - DISA STIG for Firefox (User/Developer Workstation)
  - Classification Banner (Graphical Desktop)

EOF
}

main () {
    local OPTIND
    local OPTION

    while getopts ":b:hi:r:" OPTION; do
        case $OPTION in
            b)
                # banner
                classification_banner_path=${OPTARG}
                ;;
            h)
                usage
                exit 0
                ;;
            i)
                # RHEL ISO
                rhel_iso=${OPTARG}
                ;;
            r)
                # STIG FIX RPM
                stig_fix_rpm=${OPTARG}
                ;;
            ?)
                echo "ERROR: Invalid Option Provided!"
                echo
                usage
                exit 1
                ;;
        esac
    done

    # check that the arguments were passwd
    if [[ -z "$classification_banner_path" ]]; then
        echo "Please specify the path to the classification banner."
        usage
        exit 1
    fi

    if [[ -z "$rhel_iso" ]]; then
        echo "Please specify the path to the RHEL ISO."
        usage
        exit 1
    fi

    if [[ -z "$stig_fix_rpm" ]]; then
        echo "Please specify the location of the stig fix rpm."
        usage
        exit 1
    fi

    # check that the arguments exist
    local classification_banner_full_path="${classification_banner_path}/${CLASSIFICATION_BANNER_FILE_NAME}"
    if [[ ! -f "$classification_banner_full_path" ]]; then
        echo "Classification banner ${classification_banner_full_path} is not a regular file or it is not readble."
        usage
        exit 1
    fi

    if [[ ! -f "$rhel_iso" ]]; then
        echo "RHEL ISO ${rhel_iso} is not a regular file or it is not readable."
        usage
        exit 1
    fi

    if [[ ! -f "$stig_fix_rpm" ]]; then
        echo "STIG FIX RPM ${stig_fix_rpm} is not a regular file or it is not readable."
        usage
        exit 1
    fi

    # Check for root user
    if [[ $EUID -ne 0 ]]; then
        if [ -z "$QUIET" ]; then
            echo
            tput setaf 1;echo -e "\033[1mPlease re-run this script as root!\033[0m";tput sgr0
        fi
        exit 1
    fi

    create_iso "${classification_banner_full_path}" "${stig_fix_rpm}" "${rhel_iso}"
    exit 0
}

create_iso () {
    local banner="$1"
    local rpm="$2"
    local iso="$3"

    # Determine if DVD is Bootable
    file $iso | grep 9660 | grep -q bootable
    if [[ $? -eq 0 ]]; then
        echo "Mounting RHEL DVD Image..."
        mkdir -p /rhel
        mount -o loop "$iso" /rhel
        echo "Done."

        # Tests DVD for RHEL 6.4+
        if [[ $(grep "Red Hat" /rhel/.discinfo | awk '{ print $5 }' | awk -F '.' '{ print $1 }') -ne 6 ]]; then
            echo "ERROR: Image is not RHEL 6.4+"
            cleanup
            exit 1
        fi
        if [[ $(grep "Red Hat" /rhel/.discinfo | awk '{ print $5 }' | awk -F '.' '{ print $2 }') -lt 4 ]]; then
            echo "ERROR: Image is not RHEL 6.4+"
            cleanup
            exit 1
        fi

        echo -n "Copying the mounted RHEL DVD Image to the working directory..."
        mkdir $DIR/rhel-dvd
        cp -a /rhel/* $DIR/rhel-dvd/
        cp -a /rhel/.discinfo $DIR/rhel-dvd/
        echo " Done."
        cleanup
    else
        echo "ERROR: ISO image is not bootable."
        exit 1
    fi

    echo -n "Modifying RHEL DVD Image..."
    cp -va $DIR/config/* $DIR/rhel-dvd/
    cp -v  "$banner"     $DIR/rhel-dvd/stig-fix/
    cp -v  "$rpm"        $DIR/rhel-dvd/stig-fix/
    echo " Done."

    echo "Remastering RHEL DVD Image..."
    cd $DIR/rhel-dvd
    chmod ug+w isolinux/isolinux.bin
    find . -name TRANS.TBL -exec rm '{}' \; 
    /usr/bin/mkisofs -quiet -J -T -o $DIR/rhel-stig-fix.iso -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -R -m TRANS.TBL .
    cd $DIR
    echo "Removing working directory..."
    rm -rf $DIR/rhel-dvd
    echo "Done."

    echo "Signing RHEL DVD Image..."
    /usr/bin/implantisomd5 $DIR/rhel-stig-fix.iso
    echo "Done."

    echo "Hardened RHEL 6 ISO image ready. [rhel-stig-fix.iso]"

    exit 0
}

main "$@"
