#!/usr/bin/env bash

function setup() {
    IMAGE_PREFIX="cirros-0.3.1-x86_64-disk"

    DEFAULT_TIMEOUT=${DEFAULT_TIMEOUT:-60}
    DEFAULT_VOLUME_NAME=${DEFAULT_VOLUME_NAME:-test-volume}
    DEFAULT_INSTANCE_NAME=${DEFAULT_INSTANCE_NAME:-test-instance}
    DEFAULT_IMAGE_POOL=${DEFAULT_IMAGE_POOL:-images}
    DEFAULT_VOLUME_POOL=${DEFAULT_VOLUME_POOL:-volumes}
    DEFAULT_NETWORK_NAME=${DEFAULT_NETWORK_NAME:-public}
    DEFAULT_SSH_USER=${DEFAULT_SSH_USER:-root}
    DEFAULT_SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

    TEST_KEY_NAME=${TEST_KEY_NAME:-nova_test_key}
    TEST_PRIV_KEY=${TEST_PRIV_KEY:-$TEST_KEY_NAME.pem}

}

function 010_download_cirros_image() {
    if ! timeout ${DEFAULT_TIMEOUT} sh -c "wget -O ${TMPDIR}/${IMAGE_PREFIX}.img http://download.cirros-cloud.net/0.3.1/${IMAGE_PREFIX}.img"; then
        echo "Failed to download ${IMAGE_PREFIX}.img within ${DEFAULT_TIMEOUT} seconds"
        return 1
    fi
}

function 020_convert_qcow2_image() {
    if ! qemu-img convert -O raw ${TMPDIR}/${IMAGE_PREFIX}.img ${TMPDIR}/${IMAGE_PREFIX}.raw; then
        echo "Failed to convert image from qcow2 to raw"
        return 1
    fi
}

function 030_glance_image-create() {
    ADD_CMD="glance --debug image-create --name ${IMAGE_PREFIX} --is-public true --container-format bare --disk-format raw --file ${TMPDIR}/${IMAGE_PREFIX}.raw"

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

function 040_rbd_info_for_image() {
    if ! rbd -p ${DEFAULT_IMAGE_POOL} info ${IMAGE_ID}; then
        echo "No rbd image found for glance image ${IMAGE_ID}"
        return 1
    fi
}

function 050_cinder_volume_create() {
    if VOLUME_ID=$(cinder create --image-id ${IMAGE_ID} --display-name ${DEFAULT_VOLUME_NAME} 1 | grep ' id ' | cut -d'|'  -f 3) ; then
        if ! timeout ${DEFAULT_TIMEOUT} sh -c "while ! cinder list | grep ${DEFAULT_VOLUME_NAME} | grep available ; do sleep 1 ; done"; then
            echo "Instance ${DEFAULT_VOLUME_NAME} did not become available in ${DEFAULT_TIMEOUT} seconds"
            return 1
        fi
    else
        echo "Unable to create volume ${DEFAULT_VOLUME_NAME}"
        return 1
    fi
}

function 060_rbd_info_for_volume() {
    if ! rbd -p ${DEFAULT_VOLUME_POOL} info volume-$(echo ${VOLUME_ID} | tr -d ' '); then
        echo "No rbd image found for cinder volume ${VOLUME_ID}"
        return 1
    fi
}

function 070_rbd_children_for_image() {
    if ! rbd -p ${DEFAULT_IMAGE_POOL} children --snap snap --image ${IMAGE_ID}; then
        echo "Volume does not appear to be a child of ${IMAGE_ID}'s snapshot"
        return 1
    fi
}

function 080_nova_keypair-add() {
    # usage: nova keypair-add [--pub_key <pub_key>] <name>
    nova keypair-add $TEST_KEY_NAME > $TMPDIR/$TEST_PRIV_KEY
    if [ -e $TMPDIR/$TEST_PRIV_KEY ]; then
        chmod 600 $TMPDIR/$TEST_PRIV_KEY
    else
        echo "Private key ${TEST_PRIV_KEY} not redirected to file"
        return 1
    fi

    if ! timeout $DEFAULT_TIMEOUT sh -c "while ! nova keypair-list | grep $TEST_KEY_NAME; do sleep 1; done"; then
        echo "Keypair ${TEST_KEY_NAME} not created"
        return 1
    fi
}

function 090_nova_boot() {
    if INSTANCE_ID=$(nova boot --boot-volume ${VOLUME_ID} --flavor 1 --key_name ${TEST_KEY_NAME} ${DEFAULT_INSTANCE_NAME} | grep ' id ' | cut -d'|'  -f 3) ; then
        if ! timeout ${DEFAULT_TIMEOUT} sh -c "while ! nova list | grep ${DEFAULT_INSTANCE_NAME} | grep ACTIVE ; do sleep 1 ; done"; then
            echo "Volume ${DEFAULT_INSTANCE_NAME} did not become available in ${DEFAULT_TIMEOUT} seconds"
            return 1
        fi
    else
        echo "Unable to create instance ${DEFAULT_INSTANCE_NAME}"
    fi
}

function 100_nova-boot_verify_ssh_key() {
    local ip=$(nova show ${INSTANCE_ID} | grep ${DEFAULT_NETWORK_NAME} | cut -d'|' -f3)

    if ! timeout ${DEFAULT_TIMEOUT} sh -c "while ! ping -c1 -w1 ${ip}; do sleep 1; done"; then
        echo "Could not ping server with floating/local ip after ${DEFAULT_TIMEOUT} seconds"
        return 1
    fi

    if ! timeout ${DEFAULT_TIMEOUT} sh -c "while ! nc ${ip} 22 -w 1  < /dev/null; do sleep 1; done"; then
        echo "Port 22 never became available after ${DEFAULT_TIMEOUT} seconds"
        return 1
    fi

    timeout ${ACTIVE_TIMEOUT} sh -c "ssh ${ip} -i $TMPDIR/$TEST_PRIV_KEY ${DEFAULT_SSH_OPTS} -l ${DEFAULT_SSH_USER} -- id";
}

function 110_nova_delete() {
    # usage: nova delete <server>
    nova delete ${INSTANCE_ID}
    if ! timeout $DEFAULT_TIMEOUT sh -c "while nova list | grep ${INSTANCE_ID}; do sleep 1; done"; then
        echo "Unable to delete instance: ${DEFAULT_INSTANCE_NAME}"
        return 1
    fi
}

function 120_nova_keypair-delete() {
    # usage: nova keypair-delete <name>
    nova keypair-delete $TEST_KEY_NAME
    if [ -e $TMPDIR/$TEST_PRIV_KEY ]; then
        rm $TMPDIR/$TEST_PRIV_KEY
    fi
    if ! timeout $ASSOCIATE_TIMEOUT sh -c "while nova keypair-list | grep $TEST_KEY_NAME; do sleep 1; done"; then
        echo "Keypair $TEST_PRIVATE_KEY not deleted"
        return 1
    fi
}

function 130_cinder_delete() {
    if cinder delete ${VOLUME_ID}; then
        if ! timeout ${DEFAULT_TIMEOUT} sh -c "while cinder show ${VOLUME_ID} ; do sleep 1 ; done"; then
            echo "Volume did not get deleted properly within ${DEFAULT_TIMEOUT} seconds"
            return 1
        fi
    else
        echo "Could not delete volume ${VOLUME_ID}"
        return 1
    fi
}

function 140_glance_image-delete() {
    if ! glance --debug image-delete $IMAGE_ID; then
        echo "Unable to delete image from glance with ID: ${IMAGE_ID}"
            return 1
    fi

    # make sure it's gone
    if glance --debug image-list | grep $IMAGE_ID ; then
        echo "Image has not actually been removed properly from glance"
        return 1
    fi
}

function teardown() {
    # Remove TMP_IMAGE_FILE
    for file in ${TMPDIR}/${IMAGE_PREFIX}.img ${IMAGE_PREFIX}.raw; do
        if [ -e ${file} ]; then
            rm ${file}
        fi
    done
}
