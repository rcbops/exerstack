#!/usr/bin/env bash

function setup() {
    IMAGE_PREFIX="cirros-0.3.1-x86_64-disk"
    wget -O /tmp/${IMAGE_PREFIX}.img http://download.cirros-cloud.net/0.3.1/${IMAGE_PREFIX}.img
    qemu-img convert -O raw /tmp/${IMAGE_PREFIX}.img /tmp/${IMAGE_PREFIX}.raw

    # Max time to wait for volume operations (specifically create and delete)
    DEFAULT_TIMEOUT=${DEFAULT_TIMEOUT:-60}
    # Default volume name
    DEFAULT_VOLUME_NAME=${DEFAULT_VOLUME_NAME:-test-volume}
    DEFAULT_INSTANCE_NAME=${DEFAULT_INSTANCE_NAME:-test-instance}
    # Name for volume snapshot
    DEFAULT_VOLUME_SNAP_NAME=${DEFAULT_VOLUME_SNAP_NAME:-test-volume-snapshot}
    DEFAULT_IMAGE_POOL=${DEFAULT_IMAGE_POOL:-images}
    DEFAULT_VOLUME_POOL=${DEFAULT_VOLUME_POOL:-volumes}
}

function 010_glance_image_create() {
    ADD_CMD="glance --debug image-create --name ${IMAGE_PREFIX} --is-public true --container-format bare --disk-format raw --file /tmp/${IMAGE_PREFIX}.raw"

    if ! TMP_IMAGE_ID=$(${ADD_CMD}); then
        echo "Failed to upload image using the glance add command"
        return 1
    fi

    IMAGE_ID=$(echo "${TMP_IMAGE_ID}" | grep ' id ' | cut -d '|' -f 3)

    if ! glance --debug image-show ${IMAGE_ID} | grep status | grep active; then
        echo "Image uploaded but not marked as active"
        return 1
    fi
}

function 020_rbd_info_for_image() {
    if ! rbd -p ${DEFAULT_IMAGE_POOL} info ${IMAGE_ID}; then
        echo "No rbd image found for glance image ${IMAGE_ID}"
        return 1
    fi
}

function 030_cinder_volume_create() {
    if VOLUME_ID=$(cinder create --image-id ${IMAGE_ID} --display-name ${DEFAULT_VOLUME_NAME} 1 | grep ' id ' | cut -d'|'  -f 3) ; then
        if ! timeout ${DEFAULT_TIMEOUT} sh -c "while ! cinder list | grep ${DEFAULT_VOLUME_NAME} | grep available ; do sleep 1 ; done"; then
            echo "instance ${DEFAULT_VOLUME_NAME} did not become available in ${DEFAULT_TIMEOUT} seconds"
            return 1
        fi
    else
        echo "Unable to create volume ${DEFAULT_VOLUME_NAME}"
        return 1
    fi
}

function 040_rbd_info_for_volume() {
    if ! rbd -p ${DEFAULT_VOLUME_POOL} info volume-$(echo ${VOLUME_ID} | tr -d ' '); then
        echo "No rbd image found for cinder volume ${VOLUME_ID}"
        return 1
    fi
}

function 050_rbd_children_for_image() {
    if ! rbd -p ${DEFAULT_IMAGE_POOL} children --snap snap --image ${IMAGE_ID}; then
        echo "volume does not appear to be a child of ${IMAGE_ID}'s snapshot"
        return 1
    fi
}

function 060_nova_boot() {
    if INSTANCE_ID=$(nova boot --boot-volume ${VOLUME_ID} --flavor 1 ${DEFAULT_INSTANCE_NAME} | grep ' id ' | cut -d'|'  -f 3) ; then
        if ! timeout ${DEFAULT_TIMEOUT} sh -c "while ! nova list | grep ${DEFAULT_INSTANCE_NAME} | grep ACTIVE ; do sleep 1 ; done"; then
            echo "volume ${DEFAULT_INSTANCE_NAME} did not become available in ${DEFAULT_TIMEOUT} seconds"
            return 1
        fi
    else
        echo "Unable to create instance ${DEFAULT_INSTANCE_NAME}"
    fi
}

function 070_nova_delete() {
    # usage: nova delete <server>
    nova delete ${INSTANCE_ID}
    if ! timeout $DEFAULT_TIMEOUT sh -c "while nova list | grep ${INSTANCE_ID}; do sleep 1; done"; then
        echo "Unable to delete instance: ${DEFAULT_INSTANCE_NAME}"
        return 1
    fi
}

function 080_cinder_delete() {
    if cinder delete ${VOLUME_ID}; then
        if ! timeout ${DEFAULT_TIMEOUT} sh -c "while cinder show ${VOLUME_ID} ; do sleep 1 ; done"; then
            echo "volume did not get deleted properly within ${DEFAULT_TIMEOUT} seconds"
            return 1
        fi
    else
        echo "could not delete volume ${VOLUME_ID}"
        return 1
    fi
}

function 090_glance_image_delete() {
    if ! glance --debug image-delete $IMAGE_ID; then
        echo "Unable to delete image from glance with ID: ${IMAGE_ID}"
            return 1
    fi

    # make sure it's gone
    if glance --debug image-list | grep $IMAGE_ID ; then
        echo "image has not actually been removed properly from glance"
        return 1
    fi
}

function teardown() {
    # Remove TMP_IMAGE_FILE
    for file in /tmp/${IMAGE_PREFIX}.img ${IMAGE_PREFIX}.raw; do
        if [ -e ${file} ]; then
            rm ${file}
        fi
    done
}
