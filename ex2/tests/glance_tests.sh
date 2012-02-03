#!/bin/bash


function real_error_output() {
    blarg
}

function some_glance_thing() {
    sleep .8
}


function glance_010_upload_image() {
    # Image to use
    IMAGE="tty"
    IMAGE_DIR="images"
    UNTARRED_IMAGES="untarred_images"
    IMAGE_URL="http://images.ansolabs.com/tty.tgz"
    TOKEN="999888777666"

    # Create a directory for the downloaded image tarballs.
    if ! mkdir -p $IMAGE_DIR/$UNTARRED_IMAGES; then
	echo "could not make directory"
    fi
   
    # we'll use ami-tty as our test image
    if [[ ! -f $IMAGE_DIR/$IMAGE.tgz ]]; then
        wget -q -c $IMAGE_URL -O $IMAGE_DIR/$IMAGE.tgz
    fi
   
    # untar the image
    tar -zxf $IMAGE_DIR/tty.tgz -C $IMAGE_DIR/$UNTARRED_IMAGES
    
    # upload the kernel image
    KERNEL_ID=$(glance -A $TOKEN add name="tty-kernel" is_public=true container_format=aki disk_format=aki < $IMAGE_DIR/$UNTARRED_IMAGES/aki-tty/image |  cut -d":" -f2 | tr -d " ")
    if [[ -z $KERNEL_ID ]]; then
    	echo "image failed to upload"
    fi
    
    # upload the ramdisk image
    RAMDISK_ID=$(glance -A $TOKEN add name="tty-ramdisk" is_public=true container_format=ari disk_format=ari < $IMAGE_DIR/$UNTARRED_IMAGES/ari-tty/image |  cut -d":" -f2 | tr -d " ")
    if [[ -z $RAMDISK_ID ]]; then
    	echo "image failed to upload"
    fi
    
    # upload the machine image
    MACHINE_ID=$(glance add -A $TOKEN name="tty" is_public=true container_format=ami disk_format=ami kernel_id=$KERNEL_ID ramdisk_id=$RAMDISK_ID < $IMAGE_DIR/$UNTARRED_IMAGES/ami-tty/image |  cut -d":" -f2 | tr -d " ")
    if [[ -z $MACHINE_ID ]]; then
        echo "image failed to upload"
    fi
}

function glance_020_boot_image() {
echo "boot image"
}
