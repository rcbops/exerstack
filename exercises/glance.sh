#!/usr/bin/env bash

# Test glance CLI

# This script exits on an error so that errors don't compound and you see
# only the first error that occured.
set -o errexit

# Print the commands being run so that we can see the command that triggers
# an error.  It is also useful for following allowing as the install occurs.
set -o xtrace


# Settings
# ========

# Use openrc + stackrc + localrc for settings
pushd $(cd $(dirname "$0")/.. && pwd)
source ./openrc
popd

## Glance settings
# Where we will grab our test image from if we don't already have it
IMAGE_URL="http://images.ansolabs.com/tty.tgz"

# Boot this image, use first AMi image if unset
DEFAULT_IMAGE_NAME=${DEFAULT_IMAGE_NAME:-ami}

# Auth token to use when querying glance
TOKEN=${TOKEN:-999888777666}

# where to store our downloaded images
IMAGE_DIR=${IMAGE_DIR:-images}

# where to store our untarred images
UNTARRED_IMAGES=${UNTARRED_IMAGES:-untarred_images}

## Nova settings
# Max time to wait while vm goes from build to active state
ACTIVE_TIMEOUT=${ACTIVE_TIMEOUT:-30}

# Max time till the vm is bootable
BOOT_TIMEOUT=${BOOT_TIMEOUT:-30}

# Max time to wait for proper association and dis-association.
ASSOCIATE_TIMEOUT=${ASSOCIATE_TIMEOUT:-15}

# Max time to wait for server to shut down
SHUTDOWN_TIMEOUT=${SHUTDOWN_TIMEOUT:-30}

# Instance type to create
DEFAULT_INSTANCE_TYPE=${DEFAULT_INSTANCE_TYPE:-m1.tiny}


# tests
# =====

# Pushing images to glance
# -------------------------

# Image to use
IMAGE="tty"

# Create a directory for the downloaded image tarballs.
mkdir -p $IMAGE_DIR/$UNTARRED_IMAGES

# we'll use ami-tty as our test image
if [[ ! -f $IMAGE_DIR/$IMAGE.tgz ]]; then
    wget -c $IMAGE_URL -O $IMAGE_DIR/$IMAGE.tgz
fi

# untar the image
tar -zxf $IMAGE_DIR/tty.tgz -C $IMAGE_DIR/$UNTARRED_IMAGES

# upload the kernel image
RVAL=`glance -A $TOKEN add name="tty-kernel" is_public=true container_format=aki disk_format=aki < $IMAGE_DIR/$UNTARRED_IMAGES/aki-tty/image`
KERNEL_ID=`echo $RVAL | cut -d":" -f2 | tr -d " "`
if [[ -z $KERNEL_ID ]]; then
	echo "image failed to upload"
	exit 1
fi

# upload the ramdisk image
RVAL=`glance -A $TOKEN add name="tty-ramdisk" is_public=true container_format=ari disk_format=ari < $IMAGE_DIR/$UNTARRED_IMAGES/ari-tty/image`
RAMDISK_ID=`echo $RVAL | cut -d":" -f2 | tr -d " "`
if [[ -z $RAMDISK_ID ]]; then
	echo "image failed to upload"
	exit 1
fi

# upload the machine image
RVAL=`glance add -A $TOKEN name="tty" is_public=true container_format=ami disk_format=ami kernel_id=$KERNEL_ID ramdisk_id=$RAMDISK_ID < $IMAGE_DIR/$UNTARRED_IMAGES/ami-tty/image`
MACHINE_ID=`echo $RVAL | cut -d":" -f2 | tr -d " "`
if [[ -z $MACHINE_ID ]]; then
    echo "image failed to upload"
    exit 1
fi

# look at some details about our images
# TODO: what else do we want to look at?
for ID in $KERNEL_ID $RAMDISK_ID $MACHINE_ID; do
	GLANCE_SHOW=`glance -A $TOKEN show $ID`
	# first check the image is not zero bytes
	if [[ "$(echo "$GLANCE_SHOW" | grep Size|cut -d' ' -f2)" -eq 0 ]]; then
	    echo "this image is zero bytes"
	    exit 1
	elif ! echo "$GLANCE_SHOW" | grep "Status: Active" && \
	     ! echo "$GLANCE_SHOW" | grep "Public: Yes"; then
	    echo "Something is wrong with this image"
	    exit 1
	else
	    echo "THIS IMAGE IS FINE - MOVE ALONG PLEASE"
	fi
done

# TODO: MORE TESTS!



# boot a nova instance using our uploaded glance image 
# ----------------------------------------------------

# determine instance type to boot
INSTANCE_TYPE=`nova flavor-list | grep $DEFAULT_INSTANCE_TYPE | cut -d"|" -f2`
if [[ -z "$INSTANCE_TYPE" ]]; then
   # grab the first flavor in the list to launch if default doesn't exist
   INSTANCE_TYPE=`nova flavor-list | head -n 4 | tail -n 1 | cut -d"|" -f2`
fi

# boot a server!
NAME="myserver"
VM_UUID=`nova boot --flavor $INSTANCE_TYPE --image $MACHINE_ID $NAME | grep ' id ' | cut -d"|" -f3 | sed 's/ //g'`


# Waiting for boot
# check that the status is active within ACTIVE_TIMEOUT seconds
if ! timeout $ACTIVE_TIMEOUT sh -c "while ! nova show $VM_UUID | grep status | grep -q ACTIVE; do sleep 1; done"; then
    echo "server didn't become active!"
    exit 1
fi

# get the IP of the server
IP=`nova show $VM_UUID | grep "private network" | cut -d"|" -f3`

# for single node deployments, we can ping private ips
MULTI_HOST=${MULTI_HOST:-0}
if [ "$MULTI_HOST" = "0" ]; then
    # sometimes the first ping fails (10 seconds isn't enough time for the VM's
    # network to respond?), so let's ping for a default of 15 seconds with a
    # timeout of a second for each ping.
    if ! timeout $BOOT_TIMEOUT sh -c "while ! ping -c1 -w1 $IP; do sleep 1; done"; then
        echo "Couldn't ping server"
        exit 1
    fi
else
    # On a multi-host system, without vm net access, do a sleep to wait for the boot
    sleep $BOOT_TIMEOUT
fi




# delete the server
nova delete $VM_UUID
if ! timeout $SHUTDOWN_TIMEOUT sh -c " while nova list | cut -d' ' -f2 | egrep -v '^\||^\+|ID'|grep -q $VM_UUID; do sleep 1; done"; then 
	echo "server didn't shut down properly"
	exit 1
fi


# cleanup
for IMAGE in $KERNEL_ID $RAMDISK_ID $MACHINE_ID; do
    if ! glance -A $TOKEN --force delete $IMAGE; then
	echo "image did not delete properly"
	exit 1
    fi
done
