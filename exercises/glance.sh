#!/usr/bin/env bash

function setup() {
    # Filename for tmp image
    TMP_IMAGE_FILE=$(mktemp $TMPDIR/test_glanceXXXXXXX)

    # dd 5K into TMP_IMAGE_FILE
    dd if=/dev/zero of=${TMP_IMAGE_FILE} bs=1K count=5

    # Image name for tmp image
    TMP_IMAGE_NAME=$(echo $TMP_IMAGE_FILE|cut -d'/' -f4)

    TOKEN=`curl -s -d  "{\"auth\":{\"passwordCredentials\": {\"username\": \"$OS_USERNAME\", \"password\": \"$OS_PASSWORD\"}}}" -H "Content-type: application/json" $OS_AUTH_URL/tokens | python -c "import sys; import json; tok = json.loads(sys.stdin.read()); print tok['access']['token']['id'];"`

}

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

function 035_glance_update() {
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

function 040_glance_delete-ENV_VARS() {
    local image_id=$(echo $IMAGE_ID| awk -F ": " '{print $2}')

    if [[ $PACKAGESET < "folsom" ]]; then
        if ! glance delete --force $image_id; then
            echo "Unable to delete image from glance with ID: ${image_id}"
            return 1
        fi
    else
        if ! glance -f delete $image_id; then
            echo "Unable to delete image from glance with ID: ${image_id}"
            return 1
        fi
    fi
}

function 060_glance_image-add_new-syntax() {

    ADD_CMD="glance --debug image-create --name ${TMP_IMAGE_NAME}-ENV --is-public true --container-format ami --disk-format ami --file ${TMP_IMAGE_FILE}"

    if ! IMAGE_ID=$(${ADD_CMD}); then
        echo "Failed to upload image using the glance add command"
        return 1
    fi

    local image_id=$(echo "${IMAGE_ID}" | grep ' id ' | cut -d '|' -f 3)

    if ! glance --debug image-show ${image_id} | grep status | grep active; then
        echo "Image uploaded but not marked as active"
        return 1
    fi
}

function 065_glance_image-update_new-syntax() {
    #SKIP_TEST=1
    #SKIP_MSG='image-update with no-tty borken pending new glanceclient packages bug #1166263'
    #return 1

    local image_id=$(echo "${IMAGE_ID}" | grep ' id ' | cut -d '|' -f 3)

    if ! glance --debug image-update --property 'arch=x86_64' --property 'distro=Ubuntu' $image_id ; then
        echo "glance update failed"
        return 1
    fi

    # verify that the expected metadata is there
    if ! glance --debug image-show $image_id | grep 'arch'|grep 'x86_64'; then
        echo "Property 'arch' not set properly"
        return 1
    fi
    if ! glance --debug image-show $image_id | grep 'distro'|grep 'Ubuntu'; then
        echo "Property 'distro' not set properly"
        return 1
    fi

    # Update and replace metadata
    if ! glance --debug image-update --property 'arch=i386' --purge-props $image_id; then
        echo "glance update failed"
        return 1
    fi

    # verify that the expected metadata is there
    if ! glance --debug image-show $image_id | grep 'arch'| grep 'i386'; then
        echo "Property 'arch' not set properly"
        return 1
    fi
    if glance --debug image-show $image_id | grep 'distro'|grep 'Ubuntu'; then
        echo "Property 'distro' not deleted properly"
        return 1
    fi
}

function 070_glance_image-delete_new-syntax() {
    local image_id=$(echo "${IMAGE_ID}" | grep ' id ' | cut -d '|' -f 3)

    if ! glance --debug image-delete $image_id; then
        echo "Unable to delete image from glance with ID: ${image_id}"
            return 1
    fi

    # make sure it's gone
    if glance --debug image-list | grep $image_id ; then
        echo "image has not actually been removed properly from glance"
        return 1
    fi
}

function teardown() {
    # Remove TMP_IMAGE_FILE
    if [ -e ${TMP_IMAGE_FILE} ]; then
        rm $TMP_IMAGE_FILE
    fi
}
