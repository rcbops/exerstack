#!/usr/bin/env bash

function setup() {
    # Filename for tmp image
    TMP_IMAGE_FILE=$(mktemp $TMPDIR/test_glanceXXXXXXX)

    # dd 5K into TMP_IMAGE_FILE
    dd if=/dev/zero of=${TMP_IMAGE_FILE} bs=1K count=5

    # Image name for tmp image
    TMP_IMAGE_NAME=$(echo $TMP_IMAGE_FILE|cut -d'/' -f4)

    TOKEN=`curl -s -d  "{\"auth\":{\"passwordCredentials\": {\"username\": \"$NOVA_USERNAME\", \"password\": \"$NOVA_PASSWORD\"}}}" -H "Content-type: application/json" http://$HOST_IP:5000/v2.0/tokens | python -c "import sys; import json; tok = json.loads(sys.stdin.read()); print tok['access']['token']['id'];"`

    # Export required ENV vars
    export OS_AUTH_USER=$NOVA_USERNAME
    export OS_AUTH_KEY=$NOVA_PASSWORD
    export OS_AUTH_TENANT=$NOVA_PROJECT_ID
    export OS_AUTH_URL=$NOVA_URL
    export OS_AUTH_STRATEGY=keystone
}

#    update          Updates an image's metadata in Glance
#    details         Return detailed information about images in
#                    Glance
#    clear           Removes all images and metadata from Glance
#    cache-index          List all images currently cached
#    cache-invalid        List current invalid cache images
#    cache-incomplete     List images currently being fetched
#    cache-prefetching    List images that are being prefetched
#    cache-prefetch       Pre-fetch an image or list of images into the cache
#    cache-purge          Purges an image from the cache
#    cache-clear          Removes all images from the cache
#    cache-reap-invalid   Reaps any invalid images that were left for
#                         debugging purposes
#    cache-reap-stalled   Reaps any stalled incomplete images
#    image-members    List members an image is shared with
#    member-images    List images shared with a member
#    member-add       Grants a member access to an image
#    member-delete    Revokes a member's access to an image
#    members-replace  Replaces all membership for an image

function 010_glance_add-TOKEN() {
    if ! IMAGE_ID=$(glance -A ${TOKEN} add name="${TMP_IMAGE_NAME}-TOKEN" is_public=true container_format=ami disk_format=ami < ${TMP_IMAGE_FILE}); then
        echo "Failed to upload image using the glance add command"
        return 1
    fi  
    local image_id=$(echo $IMAGE_ID| awk -F ": " '{print $2}')
    if ! glance -A ${TOKEN} show ${image_id} | grep Status | grep active; then
        echo "Image uploaded but not marked as active"
        return 1
    fi
}

function 011_glance_delete-TOKEN() {
    local image_id=$(echo $IMAGE_ID| awk -F ": " '{print $2}')

    if ! glance -A ${TOKEN} delete --force $image_id; then
        echo "Unable to delete image from glance with ID: ${image_id}"
        return 1
    fi
}

function 030_glance_add-ENV_VARS() {
    if ! IMAGE_ID=$(glance add name="${TMP_IMAGE_NAME}-ENV" is_public=true container_format=ami disk_format=ami < ${TMP_IMAGE_FILE}); then
        echo "Failed to upload image using the glance add command"
        return 1
    fi  
    local image_id=$(echo $IMAGE_ID| awk -F ": " '{print $2}')
    if ! glance show ${image_id} | grep Status | grep active; then
        echo "Image uploaded but not marked as active"
        return 1
    fi
}

function 031_glance_update() {
    local image_id=$(echo $IMAGE_ID| awk -F ": " '{print $2}')

    if ! glance update $image_id arch='x86_64' distro='Ubuntu'; then
        echo "glance update failed"
        return 1
    fi 

    # verify that the expected metadata is there
    if ! glance show $image_id | grep "Property 'arch': x86_64"; then
        echo "Property 'arch' not set properly"
        return 1
    fi
    if ! glance show $image_id | grep "Property 'distro': Ubuntu"; then
        echo "Property 'distro' not set properly"
        return 1
    fi

    # Update and replace metadata
    if ! glance update $image_id arch='x86_64'; then
        echo "glance update failed"
        return 1
    fi 

    # verify that the expected metadata is there
    if ! glance show $image_id | grep "Property 'arch': x86_64"; then
        echo "Property 'arch' not set properly"
        return 1
    fi
    if glance show $image_id | grep "Property 'distro': Ubuntu"; then
        echo "Property 'distro' not deleted properly"
        return 1
    fi
}

function 900_glance_delete-ENV_VARS() {
    local image_id=$(echo $IMAGE_ID| awk -F ": " '{print $2}')

    if ! glance delete --force $image_id; then
        echo "Unable to delete image from glance with ID: ${image_id}"
        return 1
    fi
}

function teardown() {
    # Remove TMP_IMAGE_FILE
    if [ -e ${TMP_IMAGE_FILE} ]; then
        rm $TMP_IMAGE_FILE
    fi
}

#function 030_show_details() {
#
#    # let's get the image numbers we're dealing with here
#    if [[ -f $IMAGE_DIR/$IMAGES_FILE ]]; then
#        source $IMAGE_DIR/$IMAGES_FILE
#    else
#        echo "there was no $IMAGES_FILE file"
#        exit 1
#    fi
#
#    for ID in $KERNEL_ID $RAMDISK_ID $MACHINE_ID; do
#        GLANCE_SHOW=$(glance -A $TOKEN show $ID)
#        # first check the image is not zero bytes
}

function 900_glance_delete-ENV_VARS() {
    local image_id=$(echo $IMAGE_ID| awk -F ": " '{print $2}')

    if ! glance delete --force $image_id; then
        echo "Unable to delete image from glance with ID: ${image_id}"
        return 1
    fi
}

function teardown() {
    # Remove TMP_IMAGE_FILE
    if [ -e ${TMP_IMAGE_FILE} ]; then
        rm $TMP_IMAGE_FILE
    fi
}

#function 030_show_details() {
#
#    # let's get the image numbers we're dealing with here
#    if [[ -f $IMAGE_DIR/$IMAGES_FILE ]]; then
#        source $IMAGE_DIR/$IMAGES_FILE
#    else
#        echo "there was no $IMAGES_FILE file"
#        exit 1
#    fi
#
#    for ID in $KERNEL_ID $RAMDISK_ID $MACHINE_ID; do
#        GLANCE_SHOW=$(glance -A $TOKEN show $ID)
#        # first check the image is not zero bytes
#        if [[ "$(echo "$GLANCE_SHOW" | grep Size|cut -d' ' -f2)" -eq "0" ]]; then
#            echo "The $ID image is zero bytes"
#        exit 1
#        fi
#        
#        # now check that the image looks to be available
#        if ! echo "$GLANCE_SHOW" | grep "Status: Active" && \
#             ! echo "$GLANCE_SHOW" | grep "Public: Yes"; then
#            echo "Something is wrong with this image"
#            exit 1
#        fi
#
#        # finally check the machine image has the correct associated
#        # metadata
#        if [[ $ID = $MACHINE_ID ]]; then
#            if ! echo $GLANCE_SHOW | grep "Property \'kernel_id\': $KERNEL_ID"; then 
#                echo "Kernel image is not properly associated with the machine image"
#            elif ! echo $GLANCE SHOW | grep "Property \'ramdisk_id\': $RAMDISK_ID"; then
#                echo "Ramdisk image is not properly associated with the machine image"
#            fi
#        fi
#    done
#
#}

#function 035_show_index() {
#
#    # let's get the image numbers we're dealing with here
#    if [[ -f $IMAGE_DIR/$IMAGES_FILE ]]; then
#        source $IMAGE_DIR/$IMAGES_FILE
#    else
#        echo "there was no $IMAGES_FILE file"
#        exit 1
#    fi
#
#    # glance does not nicely detect non-interactive mode so we
#    # need to force it to show the full index (without paging)
#    # by enforcing an artifically high limit
#    GLANCE_INDEX=$(glance -A $TOKEN --limit 200 index)
#
#    # check that we can see our images in the index listing
#    # first check we got a normal header from glance index
#    if echo $GLANCE_INDEX | grep -e '^ID'; then
#        # then check that our images are there
#        for ID in $KERNEL_ID $MACHINE_ID $RAMDISK_ID; do
#            if ! echo $GLANCE_INDEX | grep -e "$ID"; then
#                echo "Could not see image id $ID in the glance index"
#                exit 1
#            fi
#        done
#    else
#        echo "We don't appear to have got a normal response from glance index:"
#        echo "$GLANCE_INDEX"
#        exit 1
#    fi
#    
#}

#function 040_update_metadata() {
#
#    # let's get the image numbers we're dealing with here
#    if [[ -f $IMAGE_DIR/$IMAGES_FILE ]]; then
#        source $IMAGE_DIR/$IMAGES_FILE
#    else
#        echo "there was no $IMAGES_FILE file"
#        exit 1
#    fi
#
#    # probably just need to update the metadata on just one of our images
#    glance -A $TOKEN update $RAMDISK_ID is_public=false
#    # check it's been update with glance show $RAMDISK_ID
#    if ! glance -A $TOKEN show $RAMDISK_ID|grep 'Public: No'; then
#    echo "metadata did not get updated correctly"
#    exit 1
#    fi
#
#    # now put it back the way it was
#    glance -A $TOKEN update $RAMDISK_ID is_public=true
#    # check it's been update with glance show $RAMDISK_ID
#    if ! glance -A $TOKEN show $RAMDISK_ID|grep 'Public: Yes'; then
#    echo "metadata did not get updated correctly"
#    exit 1
#    fi
#
#}


#function 090_delete_images() {
#
#    # let's get the image numbers we're dealing with here
#    if [[ -f $IMAGE_DIR/$IMAGES_FILE ]]; then
#        source $IMAGE_DIR/$IMAGES_FILE
#    else
#        echo "there was no $IMAGES_FILE file"
#        exit 1
#    fi
#
#    
#    for ID in $KERNEL_ID $RAMDISK_ID $MACHINE_ID; do
#        glance -A $TOKEN --force delete $ID
#    done
#
#    rm -f $IMAGE_DIR/$IMAGES_FILE
#    
#}
