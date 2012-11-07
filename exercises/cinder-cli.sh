#!/usr/bin/env bash

function setup() {
    # Max time to wait while vm goes from build to active state
    ACTIVE_TIMEOUT=${ACTIVE_TIMEOUT:-60}
    # Max time till the vm is bootable
    BOOT_TIMEOUT=${BOOT_TIMEOUT:-60}
    # Max time to wait for suspend/pause/resume
    SUSPEND_TIMEOUT=$(( BOOT_TIMEOUT + ACTIVE_TIMEOUT ))
    # Max time to wait for a reboot
    REBOOT_TIMEOUT=$(( ( ACTIVE_TIMEOUT * 2 ) + BOOT_TIMEOUT ))
    # Max time to wait for proper association and dis-association.
    ASSOCIATE_TIMEOUT=${ASSOCIATE_TIMEOUT:-30}
    # Default username to use with ssh
    DEFAULT_SSH_USER=${DEFAULT_SSH_USER:-root}
    # Default volume name
    DEFAULT_VOLUME_NAME=${DEFAULT_VOLUME_NAME:-test-volume}
    # Instance name
    DEFAULT_INSTANCE_NAME=${DEFAULT_INSTANCE_NAME:-test_nova_cli_instance}
    # Instance type to create
    DEFAULT_INSTANCE_TYPE=${DEFAULT_INSTANCE_TYPE:-m1.tiny}
    # Boot this image, use first AMi image if unset
    DEFAULT_IMAGE_NAME=${DEFAULT_IMAGE_NAME:-$(nova image-list | awk '{ print $4 }' | grep "\-image" | head -n1)}
    # Name for volume snapshot
    DEFAULT_VOLUME_SNAP_NAME=${DEFAULT_VOLUME_SNAP_NAME:-test-volume-snapshot}
    # Find the instance type ID
    INSTANCE_TYPE=$(nova flavor-list | egrep $DEFAULT_INSTANCE_TYPE | head -1 | cut -d" " -f2)
    # Find an image to spin
    IMAGE=$(nova image-list|egrep $DEFAULT_IMAGE_NAME|head -1|cut -d" " -f2)
    # Define the network name to use for ping/ssh tests
    DEFAULT_NETWORK_NAME=${DEFAULT_NETWORK_NAME:-public}
    # Default floating IP pool name
    DEFAULT_FLOATING_POOL=${DEFAULT_FLOATING_POOL:-nova}
    # Default SSH OPTIONS
    SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

    # File name for generated keys
    TEST_KEY_NAME=${TEST_KEY_NAME:-nova_test_key}
    TEST_PRIV_KEY=${TEST_PRIV_KEY:-$TEST_KEY_NAME.pem}
    # TEST_PUB_KEY=${TEST_PUB_KEY:-$TEST_KEY_NAME.pub}

    # create a volume group if we don't already have one to test on
    if ! vgdisplay cinder-volumes ; then
        dd if=/dev/zero of=${TMPDIR}/cinder-volumes bs=1 count=0 seek=6G
        losetup /dev/loop3 ${TMPDIR}/cinder-volumes
        pvcreate /dev/loop3
        vgcreate cinder-volumes /dev/loop3
        service cinder-volume restart
        sleep 5
    fi
}

#######    absolute-limits     Print a list of absolute limits for a user
#######   create              Add a new volume.
#######    credentials         Show user credentials returned from auth
#    delete              Remove a volume.
#######    endpoints           Discover endpoints that get returned from the
#                        authenticate services
#######    list                List all the volumes.
#    quota-class-show    List the quotas for a quota class.
#    quota-class-update  Update the quotas for a quota class.
#######    quota-defaults      List the default quotas for a tenant.
#######    quota-show          List the quotas for a tenant.
#    quota-update        Update the quotas for a tenant.
#######    rate-limits         Print a list of rate limits for a user
#    rename              Rename a volume.
#    show                Show details about a volume.
#    snapshot-create     Add a new snapshot.
#    snapshot-delete     Remove a snapshot.
#    snapshot-list       List all the snapshots.
#    snapshot-rename     Rename a snapshot.
#    snapshot-show       Show details about a snapshot.
#    type-create         Create a new volume type.
#    type-delete         Delete a specific flavor
#    type-list           Print a list of available 'volume types'.
#    bash-completion     Prints all of the commands and options to stdout so


function 010_cinder_limits() {
    if ! cinder absolute-limits; then
        echo "could not get api limits"
    fi
}

function 020_cinder_credentials() {
    if ! cinder credentials; then
        echo "could not get cinder credentials"
    fi

}

function 030_cinder_endpoints() {
    if ! cinder endpoints; then
        echo "could not get endpoints"
    fi
}

function 040_cinder_quota_defaults() {
    if ! cinder quota-defaults ${OS_TENANT_NAME}; then
        echo "could not get default quotas for tenant ${OS_TENANT_NAME}"
    fi
}

function 050_cinder_quota_show() {
    if ! cinder quota-show ${OS_TENANT_NAME}; then
        echo "could not get actual quotas for tenant ${OS_TENANT_NAME}"
    fi
}

function 060_cinder_quota_update() {
    CURRENT_VOLUME_QUOTA=$(cinder quota-show ${OS_TENANT_NAME}|grep -i volumes|cut -d'|' -f 3|sed -e 's/ //g')
    TARGET_VOLUME_QUOTA=$(( CURRENT_VOLUME_QUOTA +1 ))
    cinder quota-update --volumes ${TARGET_VOLUME_QUOTA} ${OS_TENANT_NAME}
    NEW_VOLUME_QUOTA=$(cinder quota-show ${OS_TENANT_NAME}|grep -i volumes|cut -d'|' -f 3|sed -e 's/ //g')

    if [ ${NEW_VOLUME_QUOTA} != ${TARGET_VOLUME_QUOTA} ]; then
        echo "could not update quotas for tenant"
    fi
}
 
function 070_cinder_rate_limits() {
    if ! cinder rate-limits ${OS_TENANT_NAME}; then
        echo "could not get actual quotas for tenant ${OS_TENANT_NAME}"
    fi
}

function 100_cinder_create() {
    if VOLUME_ID=$(cinder create --display-name ${DEFAULT_VOLUME_NAME} 1 | grep ' id ' | cut -d'|'  -f 3) ; then
        if ! timeout ${ASSOCIATE_TIMEOUT} sh -c "while ! cinder list | grep ${DEFAULT_VOLUME_NAME} | grep available ; do sleep 1 ; done"; then
            echo "volume ${DEFAULT_VOLUME_NAME} did not become available in ${ASSOCIATE_TIMEOUT} seconds"
            return 1
        fi
    else
        echo "Unable to create volume ${DEFAULT_VOLUME_NAME}"
        return 1
    fi
}

function 110_cinder_show() {
    if ! cinder show ${VOLUME_ID}; then
        echo "could not get details on the test volume"
    fi
}

function 120_cinder_snapshot_create() {
    if  SNAPSHOT_ID=$(cinder snapshot-create --display-name ${DEFAULT_VOLUME_SNAP_NAME} ${VOLUME_ID} | grep ' id ' | cut -d'|' -f3); then
        if ! timeout ${ASSOCIATE_TIMEOUT} sh -c "while ! cinder snapshot-list | grep ${DEFAULT_VOLUME_SNAP_NAME} | grep available ; do sleep 1 ; done"; then
            echo "volume snapshot ${DEFAULT_VOLUME_SNAP_NAME} did not become available in ${ASSOCIATE_TIMEOUT} seconds"
            return 1
        fi
    else
        echo "could not create snapshot of volume ${VOLUME_ID}"
        return 1
    fi
}
    
function 130_cinder_snapshot_delete() {
    if cinder snapshot-delete ${SNAPSHOT_ID}; then
        if ! timeout 30 sh -c "while cinder snapshot-show ${SNAPSHOT_ID} ; do sleep 1 ; done"; then
            echo "snapshot did not get deleted properly within ${ASSOCIATE_TIMEOUT} seconds"
            return 1
        fi
    else
        echo "could not delete snapshot ${SNAPSHOT_ID}"
        return 1
    fi
}

function 180_cinder_delete() {
    if cinder delete ${VOLUME_ID}; then
        if ! timeout 30 sh -c "while cinder show ${VOLUME_ID} ; do sleep 1 ; done"; then
            echo "volume did not get deleted properly within ${ASSOCIATE_TIMEOUT} seconds"
            return 1
        fi
    else
        echo "could not deletevolume  ${VOLUME_ID}"
        return 1
    fi
}



#function 050_nova-boot() {
#    # usage: nova boot [--flavor <flavor>] [--image <image>] [--meta <key=value>] [--file <dst-path=src-path>]
#    #                  [--key_path [<key_path>]] [--key_name <key_name>] [--user_data <user-data>]
#    #                  [--availability_zone <availability-zone>] [--security_groups <security_groups>]
#    #                  <name>
#    echo ${IMAGE}
#    nova boot --flavor ${INSTANCE_TYPE} --image ${IMAGE} --key_name ${TEST_KEY_NAME} --security_groups ${SECGROUP} ${DEFAULT_INSTANCE_NAME}
#    if ! timeout $ACTIVE_TIMEOUT sh -c "while ! nova list | grep ${DEFAULT_INSTANCE_NAME} | grep ACTIVE; do sleep 1; done"; then
#        echo "Instance ${DEFAULT_INSTANCE_NAME} failed to go active after ${ACTIVE_TIMEOUT} seconds"
#        return 1
#    fi
#}
#
#
#function 053_nova-boot_verify_ssh_key() {
#    local image_id=${DEFAULT_INSTANCE_NAME}
#    local ip=${FLOATING_IP:-""}
#
#    if [ ${NOVA_HAS_FLOATING} -eq 0 ]; then
#        ip=$(nova show ${image_id} | grep ${DEFAULT_NETWORK_NAME} | cut -d'|' -f3)
#    fi
#
#    if ! timeout ${BOOT_TIMEOUT} sh -c "while ! ping -c1 -w1 ${ip}; do sleep 1; done"; then
#        echo "Could not ping server with floating/local ip after ${BOOT_TIMEOUT} seconds"
#        return 1
#    fi
#
#    if ! timeout ${BOOT_TIMEOUT} sh -c "while ! nc ${ip} 22 -w 1  < /dev/null; do sleep 1; done"; then
#        echo "port 22 never became available after ${BOOT_TIMEOUT} seconds"
#        return 1
#    fi
#
#    timeout ${ACTIVE_TIMEOUT} sh -c "ssh ${ip} -i $TMPDIR/$TEST_PRIV_KEY ${SSH_OPTS} -l ${DEFAULT_SSH_USER} -- id";
#}

function teardown() {
#    cinder delete ${VOLUME_ID}
#    vgremove cinder-volumes
#    rm -fr ${TMPDIR}/cinder-volumes
#_    losetup -d /dev/loop3
return 0
}       
