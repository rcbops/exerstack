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
    ASSOCIATE_TIMEOUT=${ASSOCIATE_TIMEOUT:-15}

    # Default username to use with ssh
    DEFAULT_SSH_USER=${DEFAULT_SSH_USER:-root}

    # Instance name
    DEFAULT_INSTANCE_NAME=${DEFAULT_INSTANCE_NAME:-test_nova_cli_instance}

    # Instance type to create
    DEFAULT_INSTANCE_TYPE=${DEFAULT_INSTANCE_TYPE:-m1.tiny}

    # Boot this image, use first AMi image if unset
    DEFAULT_IMAGE_NAME=${DEFAULT_IMAGE_NAME:-$($NOVA_COMMAND image-list | awk '{ print $4 }' | grep "\-image" | head -n1)}

    # Name for snapshot
    DEFAULT_SNAP_NAME=${DEFAULT_SNAP_NAME:-${DEFAULT_IMAGE_NAME}-snapshot}

    # Find the instance type ID
    INSTANCE_TYPE=$($NOVA_COMMAND flavor-list | egrep $DEFAULT_INSTANCE_TYPE | head -1 | cut -d" " -f2)

    # Find an image to spin
    IMAGE=$($NOVA_COMMAND image-list|egrep $DEFAULT_IMAGE_NAME|head -1|cut -d" " -f2)

    # Define secgroup
    SECGROUP=${SECGROUP:-test_nova_cli_secgroup}

    # Define a source_secgroup
    SOURCE_SECGROUP=${SOURCE_SECGROUP:-default}

    # Define the network name to use for ping/ssh tests
    DEFAULT_NETWORK_NAME=${DEFAULT_NETWORK_NAME:-public}

    # Default floating IP pool name
    DEFAULT_FLOATING_POOL=${DEFAULT_FLOATING_POOL:-nova}

    # Additional floating IP pool and range
    TEST_FLOATING_POOL=${TEST_FLOATING_POOL:-test}

    # Default SSH OPTIONS
    SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

    # File name for generated keys
    TEST_KEY_NAME=${TEST_KEY_NAME:-nova_test_key}
    TEST_PRIV_KEY=${TEST_PRIV_KEY:-$TEST_KEY_NAME.pem}
    # TEST_PUB_KEY=${TEST_PUB_KEY:-$TEST_KEY_NAME.pub}

    # nova command OPTIONS
    NOVA_COMMAND="$NOVA_COMMAND"
}

#    actions             Retrieve server actions.
#    add-fixed-ip        Add new IP address to network.
#    diagnostics         Retrieve server diagnostics.
#                        servers).
#    image-create        Create a new image by taking a snapshot of a running
#                        server.
#    image-delete        Delete an image.
#    image-meta          Set or Delete metadata on an image.
#    meta                Set or Delete metadata on a server.
#    migrate             Migrate a server.
#    rebuild             Shutdown, re-image, and re-boot a server.
#    remove-fixed-ip     Remove an IP address from a server.
#    remove-floating-ip  Remove a floating IP address from a server.
#    resize              Resize a server.
#    resize-confirm      Confirm a previous resize.
#    resize-revert       Revert a previous resize (and return to the previous
#                        VM).
#    root-password       Change the root password for a server.
#    volume-attach       Attach a volume to a server.
#    volume-create       Add a new volume.
#    volume-delete       Remove a volume.
#    volume-detach       Detach a volume from a server.
#    volume-list         List all the volumes.
#    volume-show         Show details about a volume.
#    zone                Show or edit a child zone. No zone arg for this zone.
#    zone-add            Add a new child zone.
#    zone-boot           Boot a new server, potentially across Zones.
#    zone-delete         Delete a zone.
#    zone-info           Get this zones name and capabilities.
#    zone-list           List the children of a zone.

function 010_nova_image-list() {
    if ! $NOVA_COMMAND image-list|egrep $DEFAULT_IMAGE_NAME; then
        echo "Unable to find ${DEFAULT_IMAGE_NAME}"
        return 1
    fi
}

function 011_nova_image-show() {
    if ! $NOVA_COMMAND image-show $DEFAULT_IMAGE_NAME|egrep status|grep ACTIVE; then
        echo "${DEFAULT_IMAGE_NAME} is not listed as ACTIVE"
        return 1
    fi
}

function 012_nova_flavor-list() {
    if ! $NOVA_COMMAND flavor-list|egrep $DEFAULT_INSTANCE_TYPE; then
        echo "Unable to find ${DEFAULT_INSTANCE_TYPE}"
        return 1
    fi
}

function 020_shared_key-nova_keypair-add() {
    # usage: $NOVA_COMMAND keypair-add [--pub_key <pub_key>] <name>
    $NOVA_COMMAND keypair-add --pub_key $SHARED_PUB_KEY $SHARED_KEY_NAME
    if ! timeout $ASSOCIATE_TIMEOUT sh -c "while ! $NOVA_COMMAND keypair-list | grep $SHARED_KEY_NAME; do sleep 1; done"; then
        echo "Keypair ${SHARED_PRIV_KEY} not imported"
        return 1
    fi
}

function 021_verify_fingerprints_match() {
    FILE_FINGERPRINT=$(ssh-keygen -lf $SHARED_PUB_KEY | cut -d" " -f2)
    NOVA_FINGERPRINT=$($NOVA_COMMAND keypair-list | grep $SHARED_KEY_NAME | cut -d" " -f4)
    if [ ${NOVA_FINGERPRINT} != ${FILE_FINGERPRINT} ]; then
        echo "Imported fingerprint does not match file fingerprint"
        return 1
    fi
}

function 022_shared_key-nova-keypair-delete() {
    # usage: $NOVA_COMMAND keypair-delete <name>
    $NOVA_COMMAND keypair-delete $SHARED_KEY_NAME
    if ! timeout $ASSOCIATE_TIMEOUT sh -c "while $NOVA_COMMAND keypair-list | grep $SHARED_KEY_NAME; do sleep 1; done"; then
        echo "Keypair ${SHARED_KEY_NAME} not deleted"
        return 1
    fi
}

function 030_nova_secgroup-create() {
    # usage: $NOVA_COMMAND secgroup-create <name> <description>
    if ! $NOVA_COMMAND secgroup-list|grep $SECGROUP; then
        $NOVA_COMMAND secgroup-create $SECGROUP "$SECGROUP description"
        if ! timeout $ASSOCIATE_TIMEOUT sh -c "while ! $NOVA_COMMAND secgroup-list | grep $SECGROUP; do sleep 1; done"; then
            echo "Security group not created"
            return 1
        fi
    else
        echo "SECURITY GROUP: ${SECGROUP} already exists"
        return 1
    fi
}

function 031_nova_secgroup-add-rule() {
    # usage: $NOVA_COMMAND secgroup-add-rule <secgroup> <ip_proto> <from_port> <to_port> <cidr>
    $NOVA_COMMAND secgroup-add-rule $SECGROUP icmp -1 -1 0.0.0.0/0
    if ! timeout $ASSOCIATE_TIMEOUT sh -c "while ! $NOVA_COMMAND secgroup-list-rules $SECGROUP | grep icmp; do sleep 1; done"; then
        echo "PING: Security group rule not added"
        return 1
    fi

    $NOVA_COMMAND secgroup-add-rule $SECGROUP tcp 22 22 0.0.0.0/0
    if ! timeout $ASSOCIATE_TIMEOUT sh -c "while ! $NOVA_COMMAND secgroup-list-rules $SECGROUP | grep tcp; do sleep 1; done"; then
        echo "SSH: Security group rule not added"
        return 1
    fi
}

function 032_nova_secgroup-add-group-rule() {
    # usage: $NOVA_COMMAND secgroup-add-group-rule [--ip_proto <ip_proto>] [--from_port <from_port>]
    #                                      [--to_port <to_port>] <secgroup> <source_group>
    $NOVA_COMMAND secgroup-add-group-rule --ip_proto tcp --from_port 80 --to_port 80 $SECGROUP $SOURCE_SECGROUP
    if ! timeout $ASSOCIATE_TIMEOUT sh -c "while ! $NOVA_COMMAND secgroup-list-rules $SECGROUP | grep $SOURCE_SECGROUP; do sleep 1; done"; then
        echo "Security group rule not added"
        return 1
    fi
}

function 033_nova_secgroup-add-group-rule-folsom() {
    # usage: $NOVA_COMMAND secgroup-add-group-rule <secgroup> <source_group> <ip_proto> <from_port> <to_port>]
    nova --no-cache secgroup-add-group-rule $SECGROUP $SOURCE_SECGROUP tcp 80 80
    if ! timeout $ASSOCIATE_TIMEOUT sh -c "while ! nova --no-cache secgroup-list-rules $SECGROUP | grep $SOURCE_SECGROUP; do sleep 1; done"; then
        echo "Security group rule not added"
        return 1
    fi
}

function 040_nova_keypair-add() {
    # usage: $NOVA_COMMAND keypair-add [--pub_key <pub_key>] <name>
    $NOVA_COMMAND keypair-add $TEST_KEY_NAME > $TMPDIR/$TEST_PRIV_KEY
    if [ -e $TMPDIR/$TEST_PRIV_KEY ]; then
        chmod 600 $TMPDIR/$TEST_PRIV_KEY
    else
        echo "Private key ${TEST_PRIV_KEY} not redirected to file"
        return 1
    fi
    if ! timeout $ASSOCIATE_TIMEOUT sh -c "while ! $NOVA_COMMAND keypair-list | grep $TEST_KEY_NAME; do sleep 1; done"; then
        echo "Keypair ${TEST_KEY_NAME} not created"
        return 1
    fi
}

function 050_nova-boot() {
    # usage: $NOVA_COMMAND boot [--flavor <flavor>] [--image <image>] [--meta <key=value>] [--file <dst-path=src-path>]
    #                  [--key_path [<key_path>]] [--key_name <key_name>] [--user_data <user-data>]
    #                  [--availability_zone <availability-zone>] [--security_groups <security_groups>]
    #                  <name>
    echo ${IMAGE}
    $NOVA_COMMAND boot --flavor ${INSTANCE_TYPE} --image ${IMAGE} --key_name ${TEST_KEY_NAME} --security_groups ${SECGROUP} ${DEFAULT_INSTANCE_NAME}
    if ! timeout $ACTIVE_TIMEOUT sh -c "while ! $NOVA_COMMAND list | grep ${DEFAULT_INSTANCE_NAME} | grep ACTIVE; do sleep 1; done"; then
        echo "Instance ${DEFAULT_INSTANCE_NAME} failed to go active after ${ACTIVE_TIMEOUT} seconds"
        return 1
    fi
}

function 051_nova-show() {
    local image_id=${DEFAULT_INSTANCE_NAME}
    if ! $NOVA_COMMAND show ${image_id} |grep flavor|grep $DEFAULT_INSTANCE_TYPE; then
        echo "$NOVA_COMMAND show: flavor is not correct"
        return 1
    fi
    if ! $NOVA_COMMAND show ${image_id} |grep image|grep $DEFAULT_IMAGE_NAME; then
        echo "$NOVA_COMMAND show: user_id is not correct"
        return 1
    fi
}

function 052_associate_floating_ip() {
    local image_id=${DEFAULT_INSTANCE_NAME}

    NOVA_HAS_FLOATING=1
    # Allocate floating address'
    if ! IP=$($NOVA_COMMAND floating-ip-create); then
        NOVA_HAS_FLOATING=0
        SKIP_MSG="No floating ips"
        SKIP_TEST=1
        return 1
    fi

    if [[ $PACKAGESET < "essex" ]]; then
        FLOATING_IP=$(echo ${IP} | cut -d' ' -f13)
    else
        # Essex added a new column to the output
        FLOATING_IP=$(echo ${IP} | cut -d' ' -f15)
    fi

    # Associate floating address
    # usage: $NOVA_COMMAND add-floating-ip <server> <address>
    $NOVA_COMMAND add-floating-ip ${image_id} ${FLOATING_IP}

    if ! timeout ${ASSOCIATE_TIMEOUT} sh -c "while ! $NOVA_COMMAND show ${image_id} | grep ${DEFAULT_NETWORK_NAME} | grep ${FLOATING_IP}; do sleep 1; done"; then
        echo "floating ip ${FLOATING_IP} not added within ${ASSOCIATE_TIMEOUT} seconds"
        return 1
    fi
}

function 053_nova-boot_verify_ssh_key() {
    local image_id=${DEFAULT_INSTANCE_NAME}
    local ip=${FLOATING_IP:-""}

    if [ ${NOVA_HAS_FLOATING} -eq 0 ]; then
        ip=$($NOVA_COMMAND show ${image_id} | grep ${DEFAULT_NETWORK_NAME} | cut -d'|' -f3)
    fi

    if ! timeout ${BOOT_TIMEOUT} sh -c "while ! ping -c1 -w1 ${ip}; do sleep 1; done"; then
        echo "Could not ping server with floating/local ip after ${BOOT_TIMEOUT} seconds"
        return 1
    fi

    if ! timeout ${BOOT_TIMEOUT} sh -c "while ! nc ${ip} 22 -w 1  < /dev/null; do sleep 1; done"; then
        echo "port 22 never became available after ${BOOT_TIMEOUT} seconds"
        return 1
    fi

    timeout ${ACTIVE_TIMEOUT} sh -c "ssh ${ip} -i $TMPDIR/$TEST_PRIV_KEY ${SSH_OPTS} -l ${DEFAULT_SSH_USER} -- id";
}

function 054_nova_remove-floating-ip() {
    local image_id=${DEFAULT_INSTANCE_NAME}
    local ip=${FLOATING_IP:-""}

    if [ $NOVA_HAS_FLOATING -eq 0 ]; then
        SKIP_TEST=1
        SKIP_MSG="No floating ips"
        return 1
    fi

    # usage: $NOVA_COMMAND remove-floating-ip <server> <address>
    $NOVA_COMMAND remove-floating-ip ${image_id} ${ip}

    if ! timeout ${ASSOCIATE_TIMEOUT} sh -c "while $NOVA_COMMAND show ${DEFAULT_INSTANCE_NAME} | grep ${DEFAULT_NETWORK_NAME} | grep ${ip}; do sleep 1; done"; then
        echo "floating ip ${ip} not removed within ${ASSOCIATE_TIMEOUT} seconds"
        return 1
    fi

    if ! $NOVA_COMMAND floating-ip-delete ${ip}; then
        echo "Unable to delete floating ip ${ip}"
        return 1
    fi
}

function 055_nova-pause() {
    local image_id=${DEFAULT_INSTANCE_NAME}
    if ! $NOVA_COMMAND pause ${image_id}; then
        echo "Unable to pause instance"
        return 1
    fi
    if ! timeout ${SUSPEND_TIMEOUT} sh -c "while ! $NOVA_COMMAND show ${image_id}|grep status|grep PAUSED; do sleep 1; done"; then
        echo "Instance was not paused successfully"
        return 1
    fi
}

function 056_nova-unpause() {
    local image_id=${DEFAULT_INSTANCE_NAME}
    if ! $NOVA_COMMAND unpause ${image_id}; then
        echo "Unable to unpause instance"
        return 1
    fi
    if ! timeout $SUSPEND_TIMEOUT sh -c "while ! $NOVA_COMMAND show ${image_id}|grep status|grep ACTIVE; do sleep 1; done";  then
        echo "Instance was not unpaused successfully"
        return 1
    fi
}

function 057_nova-suspend() {
    if skip_if_distro "maverick" "natty"; then return 0; fi

    local image_id=${DEFAULT_INSTANCE_NAME}
    if ! $NOVA_COMMAND suspend ${image_id}; then
        echo "Unable to suspend instance"
        return 1
    fi
    if ! timeout ${SUSPEND_TIMEOUT} sh -c "while ! $NOVA_COMMAND show ${image_id}|grep status|grep SUSPENDED; do sleep 1; done"; then
        echo "Instance was not suspended successfully"
        return 1
    fi
}

function 058_nova-resume() {
    if skip_if_distro "maverick" "natty"; then return 0; fi

    local image_id=${DEFAULT_INSTANCE_NAME}
    if ! $NOVA_COMMAND resume ${image_id}; then
        echo "Unable to resume instance"
        return 1
    fi
    if ! timeout ${SUSPEND_TIMEOUT} sh -c "while ! $NOVA_COMMAND show ${image_id}|grep status|grep ACTIVE; do sleep 1; done";  then
        echo "Instance was not resumed successfully"
        return 1
    fi
}

function 059_nova-reboot() {
    local image_id=${DEFAULT_INSTANCE_NAME}
    if ! $NOVA_COMMAND reboot --hard ${image_id}; then
        echo "Unable to reboot instance (hard)"
        return 1
    fi
    if ! timeout $ACTIVE_TIMEOUT sh -c "while ! $NOVA_COMMAND show ${image_id}|grep status|grep REBOOT; do sleep 1;done"; then
        echo "Instance never entered REBOOT status"
        return 1
    fi
    if ! timeout ${REBOOT_TIMEOUT} sh -c "while ! $NOVA_COMMAND show ${image_id}|grep status|grep ACTIVE; do sleep 1;done"; then
        echo "Instance never returned to ACTIVE status"
        return 1
    fi
}

function 060_nova_image-create() {
    # usage: $NOVA_COMMAND image-create <server> <name>
    local image_id=${DEFAULT_INSTANCE_NAME}
    $NOVA_COMMAND image-create ${image_id} ${DEFAULT_SNAP_NAME}

    if ! timeout ${BOOT_TIMEOUT} sh -c "while ! $NOVA_COMMAND image-show ${DEFAULT_SNAP_NAME} | grep ACTIVE; do sleep 1; done"; then
        echo "Snapshot not created within ${BOOT_TIMEOUT} seconds"
        return 1
    fi
}

function 064_nova_image-delete() {
    # usage: $NOVA_COMMAND image-delete <image>
    local image_id=${DEFAULT_SNAP_NAME}
    $NOVA_COMMAND image-delete ${image_id}

    if ! timeout ${ACTIVE_TIMEOUT} sh -c "while $NOVA_COMMAND image-list | grep ${DEFAULT_SNAP_NAME}; do sleep 1; done"; then
        echo "Snapshot not deleted within ${ACTIVE_TIMEOUT} seconds"
        return 1
    fi
}

function 065_nova-rename() {
    local image_id=${DEFAULT_INSTANCE_NAME}
    $NOVA_COMMAND rename ${image_id} ${DEFAULT_INSTANCE_NAME}-rename
    if ! timeout $ACTIVE_TIMEOUT sh -c "while ! $NOVA_COMMAND show ${image_id}-rename|grep name| grep $DEFAULT_INSTANCE_NAME-rename; do sleep 1; done"; then
        echo "Unable to rename instance"
        return 1
    fi
}

function 099_nova-delete() {
    # usage: $NOVA_COMMAND delete <server>
    local image_id=${DEFAULT_INSTANCE_NAME}-rename
    $NOVA_COMMAND delete ${image_id}
    if ! timeout $ACTIVE_TIMEOUT sh -c "while $NOVA_COMMAND list | grep ${image_id}; do sleep 1; done"; then
	echo "Unable to delete instance: ${DEFAULT_INSTANCE_NAME}"
	return 1
    fi
}

function 110_custom_key-nova_boot() {
    SKIP_MSG="Not Implemented in diablo-final"
    SKIP_TEST=1
    return 1

    $NOVA_COMMAND boot --flavor ${INSTANCE_TYPE} --image ${IMAGE} --key_path $SHARED_PUB_KEY ${DEFAULT_INSTANCE_NAME}
    if ! timeout $ACTIVE_TIMEOUT sh -c "while ! $NOVA_COMMAND list | grep ${DEFAULT_INSTANCE_NAME} | grep ACTIVE; do sleep 1; done"; then
        echo "Instance ${DEFAULT_INSTANCE_NAME} failed to boot"
        return 1
    fi
}

function 111_custom_key-verify_ssh_key() {
    SKIP_MSG="Not Implemented in diablo-final"
    SKIP_TEST=1
    return 1

    local image_id=${DEFAULT_INSTANCE_NAME}
    INSTANCE_IP=$($NOVA_COMMAND show ${image_id} | grep ${DEFAULT_NETWORK_NAME} | cut -d'|' -f3)
    if ! timeout $BOOT_TIMEOUT sh -c "while ! nc ${INSTANCE_IP} 22 -w 1  < /dev/null; do sleep 1; done"; then
        echo "port 22 never became available"
        return 1
    fi
    timeout $ACTIVE_TIMEOUT sh -c "ssh ${INSTANCE_IP} -i ${SHARED_PRIV_KEY} ${SSH_OPTS} -l ${DEFAULT_SSH_USER} -- id"
}

function 112_custom_key-nova_delete() {
    SKIP_MSG="Not Implemented in diablo-final"
    SKIP_TEST=1
    return 1

    local image_id=${DEFAULT_INSTANCE_NAME}
    $NOVA_COMMAND delete ${image_id}
    if ! timeout $ACTIVE_TIMEOUT sh -c "while $NOVA_COMMAND list | grep ${image_id}; do sleep 1; done"; then
        echo "Unable to delete instance: ${DEFAULT_INSTANCE_NAME}"
        return 1
    fi
}

function 120_file_injection-nova_boot() {
    SKIP_TEST=1
    SKIP_MSG="Skipping due to https://bugs.launchpad.net/nova/+bug/1024586"
    return 1

    local image_id=${DEFAULT_INSTANCE_NAME}-file
    local FILE_OPTS="--file /tmp/foo.txt=exercises/include/foo.txt"
    local BOOT_OPTS="--flavor ${INSTANCE_TYPE} --image ${IMAGE}"
    local KEY_OPTS="--key_name ${TEST_KEY_NAME}"
    local SEC_OPTS="--security_groups ${SECGROUP}"

    $NOVA_COMMAND boot ${BOOT_OPTS} ${KEY_OPTS} ${FILE_OPTS} ${SEC_OPTS} ${image_id}
    if ! timeout $ACTIVE_TIMEOUT sh -c "while ! $NOVA_COMMAND list | grep ${image_id} | grep ACTIVE; do sleep 1; done"; then
        echo "Instance ${image_id} failed to go active after ${ACTIVE_TIMEOUT} seconds"
        return 1
    fi
}

function 121_file_injection-verify_file_contents() {
    SKIP_TEST=1
    SKIP_MSG="Skipping due to https://bugs.launchpad.net/nova/+bug/1024586"
    return 1

    local image_id=${DEFAULT_INSTANCE_NAME}-file
    local ip=$($NOVA_COMMAND show ${image_id} | grep ${DEFAULT_NETWORK_NAME} | cut -d'|' -f3)

    if ! timeout ${BOOT_TIMEOUT} sh -c "while ! ping -c1 -w1 ${ip}; do sleep 1; done"; then
        echo "Could not ping server with floating/local ip after ${BOOT_TIMEOUT} seconds"
        return 1
    fi

    if ! timeout ${BOOT_TIMEOUT} sh -c "while ! nc ${ip} 22 -w 1  < /dev/null; do sleep 1; done"; then
        echo "port 22 never became available after ${BOOT_TIMEOUT} seconds"
        return 1
    fi

    timeout ${ACTIVE_TIMEOUT} sh -c "ssh ${ip} -i ${TMPDIR}/${TEST_PRIV_KEY} ${SSH_OPTS} -l ${DEFAULT_SSH_USER} -- cat /tmp/foo.txt";
}

function 122_file_injection-nova_delete() {
    SKIP_TEST=1
    SKIP_MSG="Skipping due to https://bugs.launchpad.net/nova/+bug/1024586"
    return 1

    local image_id=${DEFAULT_INSTANCE_NAME}-file
    $NOVA_COMMAND delete ${image_id}
    if ! timeout $ACTIVE_TIMEOUT sh -c "while $NOVA_COMMAND list | grep ${image_id}; do sleep 1; done"; then
        echo "Unable to delete instance: ${DEFAULT_INSTANCE_NAME}"
        return 1
    fi
}

function 200_nova_keypair-delete() {
    # usage: $NOVA_COMMAND keypair-delete <name>
    $NOVA_COMMAND keypair-delete $TEST_KEY_NAME
    if [ -e $TMPDIR/$TEST_PRIV_KEY ]; then
        rm $TMPDIR/$TEST_PRIV_KEY
    fi
    if ! timeout $ASSOCIATE_TIMEOUT sh -c "while $NOVA_COMMAND keypair-list | grep $TEST_KEY_NAME; do sleep 1; done"; then
        echo "Keypair $TEST_PRIVATE_KEY not deleted"
        return 1
    fi
}

function 201_nova_secgroup-delete-group-rule() {
    # usage: $NOVA_COMMAND secgroup-delete-group-rule [--ip_proto <ip_proto>] [--from_port <from_port>]
    #                                     [--to_port <to_port>] <secgroup> <source_group>
    $NOVA_COMMAND secgroup-delete-group-rule --ip_proto tcp --from_port 80 --to_port 80 $SECGROUP $SOURCE_SECGROUP
    if ! timeout $ASSOCIATE_TIMEOUT sh -c "while $NOVA_COMMAND secgroup-list-rules $SECGROUP | grep $SOURCE_SECGROUP; do sleep 1; done"; then
        echo "Security group rule not added"
        return 1
    fi
}

function 202_nova_secgroup-delete-rule() {
    # usage: $NOVA_COMMAND secgroup-delete-rule <secgroup> <ip_proto> <from_port> <to_port> <cidr>
    $NOVA_COMMAND secgroup-delete-rule $SECGROUP tcp 22 22 0.0.0.0/0
    if ! timeout $ASSOCIATE_TIMEOUT sh -c "while $NOVA_COMMAND secgroup-list-rules $SECGROUP | grep tcp; do sleep 1; done"; then
        echo "SSH: Security group rule not deleted"
        return 1
    fi
    $NOVA_COMMAND secgroup-delete-rule $SECGROUP icmp -1 -1 0.0.0.0/0
    if ! timeout $ASSOCIATE_TIMEOUT sh -c "while $NOVA_COMMAND secgroup-list-rules $SECGROUP | grep icmp; do sleep 1; done"; then
        echo "PING: Security group rule not deleted"
        return 1
    fi
}

function 203_nova_secgroup-delete() {
  # usage: $NOVA_COMMAND secgroup-delete <secgroup>
    $NOVA_COMMAND secgroup-delete $SECGROUP
    if ! timeout $ASSOCIATE_TIMEOUT sh -c "while $NOVA_COMMAND secgroup-list | grep $SECGROUP; do sleep 1; done"; then
        echo "Security group not deleted"
        return 1
    fi
}
