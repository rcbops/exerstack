#!/bin/bash



function 010_upload_image() {
    # Create a directory for the downloaded image tarballs.
    if ! mkdir -p $IMAGE_DIR/$UNTARRED_IMAGES; then
	echo "could not make directory"
    fi
   
    # we'll use ami-tty as our test image
    if [[ ! -f $IMAGE_DIR/$IMAGE_BASENAME ]]; then
        wget -q -c $IMAGE_URL -O $IMAGE_DIR/$IMAGE_BASENAME
    fi
   
    # untar the image
    tar -zxf $IMAGE_DIR/$IMAGE_BASENAME -C $IMAGE_DIR/$UNTARRED_IMAGES

    # null the image_numbers file to make sure the delete 
    # function doesn't try and delete old images if we bomb out of this
    # function early
    >$IMAGE_DIR/$IMAGES_FILE
    
    # upload the kernel image
    KERNEL_ID=$(glance -A $TOKEN add name="tty-kernel" is_public=true \
    container_format=aki disk_format=aki < $IMAGE_DIR/$UNTARRED_IMAGES/aki-tty/image |  \
    cut -d":" -f2 | tr -d " ")
    
    # write the ID out to a local file for use in other tests/functions
    if [[ $KERNEL_ID =~ ^[0-9]+$ ]]; then
        echo "KERNEL_ID=$KERNEL_ID" >> $IMAGE_DIR/$IMAGES_FILE
    else
        echo "we don't appear to have uploaded the $KERNEL_ID image correctly"
        exit 1
    fi
    
    # upload the ramdisk image
    RAMDISK_ID=$(glance -A $TOKEN add name="tty-ramdisk" is_public=true \
    container_format=ari disk_format=ari < $IMAGE_DIR/$UNTARRED_IMAGES/ari-tty/image |  \
    cut -d":" -f2 | tr -d " ")
    
    # write the ID out to a local file for use in other tests/functions
    if [[ $RAMDISK_ID =~ ^[0-9]+$ ]]; then
        echo "RAMDISK_ID=$RAMDISK_ID" >> $IMAGE_DIR/$IMAGES_FILE
    else
        echo "we don't appear to have uploaded the $RAMDISK_ID image correctly"
        exit 1
    fi
    
    # upload the machine image
    MACHINE_ID=$(glance add -A $TOKEN name="tty" is_public=true \
    container_format=ami disk_format=ami kernel_id=$KERNEL_ID ramdisk_id=$RAMDISK_ID \
    < $IMAGE_DIR/$UNTARRED_IMAGES/ami-tty/image |  cut -d":" -f2 | tr -d " ")
    
    # write the ID out to a local file for use in other tests/functions
    if [[ $MACHINE_ID =~ ^[0-9]+$ ]]; then
        echo "MACHINE_ID=$MACHINE_ID" >> $IMAGE_DIR/$IMAGES_FILE
    else
        echo "we don't appear to have uploaded the $MACHINE_ID image correctly"
        exit 1
    fi

    # NB: we need to use a file to pass the variables to the next function as each
    # function is being executed in a subshell and can't pass variables back
    # to the parent shell
}


function 080_boot_image() {


    # let's get the image numbers we're dealing with here
    if [[ -f $IMAGE_DIR/$IMAGES_FILE ]]; then
        source $IMAGE_DIR/$IMAGES_FILE
    else
        echo "there was no $IMAGES_FILE file"
        exit 1
    fi

    # determine instance type to boot
    INSTANCE_TYPE=$(nova flavor-list | grep $DEFAULT_INSTANCE_TYPE | cut -d"|" -f2)
    if [[ -z "$INSTANCE_TYPE" ]]; then
       # grab the first flavor in the list to launch if default doesn't exist
       INSTANCE_TYPE=$(nova flavor-list | head -n 4 | tail -n 1 | cut -d"|" -f2)
    else
       INSTANCE_TYPE="1"
    fi
    
    # boot a server!
    NAME="myserver"
    VM_UUID=$(nova boot --flavor $INSTANCE_TYPE --image $MACHINE_ID $NAME | grep ' id ' | cut -d"|" -f3 | sed 's/ //g')
    
    
    # Waiting for boot
    # check that the status is active within ACTIVE_TIMEOUT seconds
    if ! timeout $ACTIVE_TIMEOUT sh -c "while ! nova show $VM_UUID | grep status | grep -q ACTIVE; do sleep 1; done"; then
        echo "server didn't become active!"
        exit 1
    fi
    
    # get the IP of the server
    IP=$(nova show $VM_UUID | grep "private network" | cut -d"|" -f3)
    
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
        # boot an instance from our newly uploaded image
        echo "boot image"

}


function 030_show_details() {

    # let's get the image numbers we're dealing with here
    if [[ -f $IMAGE_DIR/$IMAGES_FILE ]]; then
        source $IMAGE_DIR/$IMAGES_FILE
    else
        echo "there was no $IMAGES_FILE file"
        exit 1
    fi

    for ID in $KERNEL_ID $RAMDISK_ID $MACHINE_ID; do
        GLANCE_SHOW=$(glance -A $TOKEN show $ID)
        # first check the image is not zero bytes
        if [[ "$(echo "$GLANCE_SHOW" | grep Size|cut -d' ' -f2)" -eq "0" ]]; then
            echo "The $ID image is zero bytes"
        exit 1
        fi
        
        # now check that the image looks to be available
        if ! echo "$GLANCE_SHOW" | grep "Status: Active" && \
             ! echo "$GLANCE_SHOW" | grep "Public: Yes"; then
            echo "Something is wrong with this image"
            exit 1
        fi

        # finally check the machine image has the correct associated
        # metadata
        if [[ $ID = $MACHINE_ID ]]; then
            if ! echo $GLANCE_SHOW | grep "Property \'kernel_id\': $KERNEL_ID"; then 
                echo "Kernel image is not properly associated with the machine image"
            elif ! echo $GLANCE SHOW | grep "Property \'ramdisk_id\': $RAMDISK_ID"; then
                echo "Ramdisk image is not properly associated with the machine image"
            fi
        fi
    done

}

function 035_show_index() {

    # let's get the image numbers we're dealing with here
    if [[ -f $IMAGE_DIR/$IMAGES_FILE ]]; then
        source $IMAGE_DIR/$IMAGES_FILE
    else
        echo "there was no $IMAGES_FILE file"
        exit 1
    fi

    # glance does not nicely detect non-interactive mode so we
    # need to force it to show the full index (without paging)
    # by enforcing an artifically high limit
    GLANCE_INDEX=$(glance -A $TOKEN --limit 200 index)

    # check that we can see our images in the index listing
    # first check we got a normal header from glance index
    if echo $GLANCE_INDEX | grep -e '^ID'; then
        # then check that our images are there
        for ID in $KERNEL_ID $MACHINE_ID $RAMDISK_ID; do
            if ! echo $GLANCE_INDEX | grep -e "$ID"; then
                echo "Could not see image id $ID in the glance index"
                exit 1
            fi
        done
    else
        echo "We don't appear to have got a normal response from glance index:"
        echo "$GLANCE_INDEX"
        exit 1
    fi
    
}

function 040_update_metadata() {

    # let's get the image numbers we're dealing with here
    if [[ -f $IMAGE_DIR/$IMAGES_FILE ]]; then
        source $IMAGE_DIR/$IMAGES_FILE
    else
        echo "there was no $IMAGES_FILE file"
        exit 1
    fi

    # probably just need to update the metadata on just one of our images
    glance -A $TOKEN update $RAMDISK_ID is_public=false
    # check it's been update with glance show $RAMDISK_ID
    if ! glance -A $TOKEN show $RAMDISK_ID|grep 'Public: No'; then
    echo "metadata did not get updated correctly"
    exit 1
    fi

    # now put it back the way it was
    glance -A $TOKEN update $RAMDISK_ID is_public=true
    # check it's been update with glance show $RAMDISK_ID
    if ! glance -A $TOKEN show $RAMDISK_ID|grep 'Public: Yes'; then
    echo "metadata did not get updated correctly"
    exit 1
    fi

}


function 090_delete_images() {

    # let's get the image numbers we're dealing with here
    if [[ -f $IMAGE_DIR/$IMAGES_FILE ]]; then
        source $IMAGE_DIR/$IMAGES_FILE
    else
        echo "there was no $IMAGES_FILE file"
        exit 1
    fi

    
    for ID in $KERNEL_ID $RAMDISK_ID $MACHINE_ID; do
        glance -A $TOKEN --force delete $ID
    done

    rm -f $IMAGE_DIR/$IMAGES_FILE
    
}
