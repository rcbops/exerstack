#!/usr/bin/env bash

function setup() {
    # Max time to wait while vm goes from build to active state
    ACTIVE_TIMEOUT=${ACTIVE_TIMEOUT:-30}

    # Max time till the vm is bootable
    BOOT_TIMEOUT=${BOOT_TIMEOUT:-30}

    # Max time to wait for suspend/pause/resume
    SUSPEND_TIMEOUT=$(( BOOT_TIMEOUT + ACTIVE_TIMEOUT ))

    # Max time to wait for a reboot
    REBOOT_TIMEOUT=$(( ( ACTIVE_TIMEOUT * 2 ) + BOOT_TIMEOUT ))

    # Max time to wait for proper association and dis-association.
    ASSOCIATE_TIMEOUT=${ASSOCIATE_TIMEOUT:-15}

    # Instance name
    DEFAULT_INSTANCE_NAME=${DEFAULT_INSTANCE_NAME:-test_nova_cli_instance}

    # Instance type to create
    DEFAULT_INSTANCE_TYPE=${DEFAULT_INSTANCE_TYPE:-m1.tiny}

    # Boot this image, use first AMi image if unset
    DEFAULT_IMAGE_NAME=${DEFAULT_IMAGE_NAME:-$(nova image-list | awk '{ print $4 }' | grep "\-image" | head -n1)}

    # Name for snapshot
    DEFAULT_SNAP_NAME=${DEFAULT_SNAP_NAME:-${DEFAULT_IMAGE_NAME}-snapshot}

    # Find the instance type ID
    INSTANCE_TYPE=$(nova flavor-list | egrep $DEFAULT_INSTANCE_TYPE | head -1 | cut -d" " -f2)

    # Find an image to spin
    IMAGE=$(nova image-list|egrep $DEFAULT_IMAGE_NAME|head -1|cut -d" " -f2)

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
    if ! nova image-list|egrep $DEFAULT_IMAGE_NAME; then
        echo "Unable to find ${DEFAULT_IMAGE_NAME}"
        return 1
    fi
}

function 011_nova_image-show() {
    if ! nova image-show $DEFAULT_IMAGE_NAME|egrep status|grep ACTIVE; then
        echo "${DEFAULT_IMAGE_NAME} is not listed as ACTIVE"
        return 1
    fi
}

function 012_nova_flavor-list() {
    if ! nova flavor-list|egrep $DEFAULT_INSTANCE_TYPE; then
        echo "Unable to find ${DEFAULT_INSTANCE_TYPE}"
        return 1
    fi
}

function 020_shared_key-nova_keypair-add() {
    # usage: nova keypair-add [--pub_key <pub_key>] <name>
    nova keypair-add --pub_key $SHARED_PUB_KEY $SHARED_KEY_NAME
    if ! timeout $ASSOCIATE_TIMEOUT sh -c "while ! nova keypair-list | grep $SHARED_KEY_NAME; do sleep 1; done"; then
        echo "Keypair ${SHARED_PRIV_KEY} not imported"
        return 1
    fi
}

function 021_verify_fingerprints_match() {
    FILE_FINGERPRINT=$(ssh-keygen -lf $SHARED_PUB_KEY | cut -d" " -f2)
    NOVA_FINGERPRINT=$(nova keypair-list | grep $SHARED_KEY_NAME | cut -d" " -f4)
    if [ ${NOVA_FINGERPRINT} != ${FILE_FINGERPRINT} ]; then
        echo "Imported fingerprint does not match file fingerprint"
        return 1
    fi
}

function 022_shared_key-nova-keypair-delete() {
    # usage: nova keypair-delete <name>
    nova keypair-delete $SHARED_KEY_NAME
    if ! timeout $ASSOCIATE_TIMEOUT sh -c "while nova keypair-list | grep $SHARED_KEY_NAME; do sleep 1; done"; then
        echo "Keypair ${SHARED_KEY_NAME} not deleted"
        return 1
    fi
}

function 030_nova_secgroup-create() {
    # usage: nova secgroup-create <name> <description>
    if ! nova secgroup-list|grep $SECGROUP; then
        nova secgroup-create $SECGROUP "$SECGROUP description"
        if ! timeout $ASSOCIATE_TIMEOUT sh -c "while ! nova secgroup-list | grep $SECGROUP; do sleep 1; done"; then
            echo "Security group not created"
            return 1
        fi
    else
        echo "SECURITY GROUP: ${SECGROUP} already exists"
        return 1
    fi
}

function 031_nova_secgroup-add-rule() {
    # usage: nova secgroup-add-rule <secgroup> <ip_proto> <from_port> <to_port> <cidr>
    nova secgroup-add-rule $SECGROUP icmp -1 -1 0.0.0.0/0
    if ! timeout $ASSOCIATE_TIMEOUT sh -c "while ! nova secgroup-list-rules $SECGROUP | grep icmp; do sleep 1; done"; then
        echo "PING: Security group rule not added"
        return 1
    fi

    nova secgroup-add-rule $SECGROUP tcp 22 22 0.0.0.0/0
    if ! timeout $ASSOCIATE_TIMEOUT sh -c "while ! nova secgroup-list-rules $SECGROUP | grep tcp; do sleep 1; done"; then
        echo "SSH: Security group rule not added"
        return 1
    fi
}

function 032_nova_secgroup-add-group-rule() {
    # usage: nova secgroup-add-group-rule [--ip_proto <ip_proto>] [--from_port <from_port>]
    #                                      [--to_port <to_port>] <secgroup> <source_group>
    nova secgroup-add-group-rule --ip_proto tcp --from_port 80 --to_port 80 $SECGROUP $SOURCE_SECGROUP
    if ! timeout $ASSOCIATE_TIMEOUT sh -c "while ! nova secgroup-list-rules $SECGROUP | grep $SOURCE_SECGROUP; do sleep 1; done"; then
        echo "Security group rule not added"
        return 1
    fi
}

function 040_nova_keypair-add() {
    # usage: nova keypair-add [--pub_key <pub_key>] <name>
    nova keypair-add $TEST_KEY_NAME > $TMPDIR/$TEST_PRIV_KEY
    if [ -e $TMPDIR/$TEST_PRIV_KEY ]; then
        chmod 600 $TMPDIR/$TEST_PRIV_KEY
    else
        echo "Private key ${TEST_PRIV_KEY} not redirected to file"
        return 1
    fi
    if ! timeout $ASSOCIATE_TIMEOUT sh -c "while ! nova keypair-list | grep $TEST_KEY_NAME; do sleep 1; done"; then
        echo "Keypair ${TEST_KEY_NAME} not created"
        return 1
    fi
}

function 050_nova-boot() {
    # usage: nova boot [--flavor <flavor>] [--image <image>] [--meta <key=value>] [--file <dst-path=src-path>]
    #                  [--key_path [<key_path>]] [--key_name <key_name>] [--user_data <user-data>]
    #                  [--availability_zone <availability-zone>] [--security_groups <security_groups>]
    #                  <name>
    echo ${IMAGE}
    nova boot --flavor ${INSTANCE_TYPE} --image ${IMAGE} --key_name ${TEST_KEY_NAME} --security_groups ${SECGROUP} ${DEFAULT_INSTANCE_NAME}
    if ! timeout $ACTIVE_TIMEOUT sh -c "while ! nova list | grep ${DEFAULT_INSTANCE_NAME} | grep ACTIVE; do sleep 1; done"; then
        echo "Instance ${DEFAULT_INSTANCE_NAME} failed to boot"
        return 1
    fi
}

function 051_nova-show() {
    local image_id=${DEFAULT_INSTANCE_NAME}
    if ! nova show ${image_id} |grep flavor|grep $DEFAULT_INSTANCE_TYPE; then
        echo "nova show: flavor is not correct"
        return 1
    fi
    if ! nova show ${image_id} |grep image|grep $DEFAULT_IMAGE_NAME; then
        echo "nova show: user_id is not correct"
        return 1
    fi
}

function 052_associate_floating_ip() {
    local image_id=${DEFAULT_INSTANCE_NAME}

    NOVA_HAS_FLOATING=1
    # Allocate floating address'
    if ! IP=$(nova floating-ip-create); then
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
    # usage: nova add-floating-ip <server> <address>
    nova add-floating-ip ${image_id} ${FLOATING_IP}

    if ! timeout ${ASSOCIATE_TIMEOUT} sh -c "while ! nova show ${image_id} | grep ${DEFAULT_NETWORK_NAME} | grep ${FLOATING_IP}; do sleep 1; done"; then
        echo "floating ip ${FLOATING_IP} not added within ${ASSOCIATE_TIMEOUT} seconds"
        return 1
    fi
}

function 053_nova-boot_verify_ssh_key() {
    local image_id=${DEFAULT_INSTANCE_NAME}
    local ip=${FLOATING_IP:-""}

    if [ ${NOVA_HAS_FLOATING} -eq 0 ]; then
        ip=$(nova show ${image_id} | grep ${DEFAULT_NETWORK_NAME} | cut -d'|' -f3)
    fi

    if ! timeout ${BOOT_TIMEOUT} sh -c "while ! ping -c1 -w1 ${ip}; do sleep 1; done"; then
        echo "Could not ping server with floating/local ip"
        return 1
    fi

    if ! timeout ${BOOT_TIMEOUT} sh -c "while ! nc ${ip} 22 -w 1 -q 0 < /dev/null; do sleep 1; done"; then
        echo "port 22 never became available"
        return 1
    fi

    timeout ${ACTIVE_TIMEOUT} sh -c "ssh ${ip} -i $TMPDIR/$TEST_PRIV_KEY ${SSH_OPTS} -l root -- id";
}

function 054_nova_remove-floating-ip() {
    local image_id=${DEFAULT_INSTANCE_NAME}
    local ip=${FLOATING_IP:-""}

    if [ $NOVA_HAS_FLOATING -eq 0 ]; then
        SKIP_TEST=1
        SKIP_MSG="No floating ips"
        return 1
    fi
    
    # usage: nova remove-floating-ip <server> <address>
    nova remove-floating-ip ${image_id} ${ip}

    if ! timeout ${ASSOCIATE_TIMEOUT} sh -c "while nova show ${DEFAULT_INSTANCE_NAME} | grep ${DEFAULT_NETWORK_NAME} | grep ${ip}; do sleep 1; done"; then
        echo "floating ip ${ip} not removed within ${ASSOCIATE_TIMEOUT} seconds"
        return 1
    fi

    if ! nova floating-ip-delete ${ip}; then
        echo "Unable to delete floating ip ${ip}"
        return 1
    fi
}

function 055_nova-pause() {
    local image_id=${DEFAULT_INSTANCE_NAME}
    if ! nova pause ${image_id}; then
        echo "Unable to pause instance"
        return 1
    fi
    if ! timeout ${SUSPEND_TIMEOUT} sh -c "while ! nova show ${image_id}|grep status|grep PAUSED; do sleep 1; done"; then
        echo "Instance was not paused successfully"
        return 1
    fi
}

function 056_nova-unpause() {
    local image_id=${DEFAULT_INSTANCE_NAME}
    if ! nova unpause ${image_id}; then
        echo "Unable to unpause instance"
        return 1
    fi
    if ! timeout $SUSPEND_TIMEOUT sh -c "while ! nova show ${image_id}|grep status|grep ACTIVE; do sleep 1; done";  then
        echo "Instance was not unpaused successfully"
        return 1
    fi
}

function 057_nova-suspend() {
    if skip_if_distro "maverick" "natty"; then return 0; fi

    local image_id=${DEFAULT_INSTANCE_NAME}
    if ! nova suspend ${image_id}; then
        echo "Unable to suspend instance"
        return 1
    fi
    if ! timeout ${SUSPEND_TIMEOUT} sh -c "while ! nova show ${image_id}|grep status|grep SUSPENDED; do sleep 1; done"; then
        echo "Instance was not suspended successfully"
        return 1
    fi
}

function 058_nova-resume() {
    if skip_if_distro "maverick" "natty"; then return 0; fi

    local image_id=${DEFAULT_INSTANCE_NAME}
    if ! nova resume ${image_id}; then
        echo "Unable to resume instance"
        return 1
    fi
    if ! timeout ${SUSPEND_TIMEOUT} sh -c "while ! nova show ${image_id}|grep status|grep ACTIVE; do sleep 1; done";  then
        echo "Instance was not resumed successfully"
        return 1
    fi
}

function 059_nova-reboot() {
    local image_id=${DEFAULT_INSTANCE_NAME}
    if ! nova reboot ${image_id}; then
        echo "Unable to reboot instance"
        return 1
    fi
    if ! timeout $ACTIVE_TIMEOUT sh -c "while ! nova show ${image_id}|grep status|grep REBOOT; do sleep 1;done"; then
        echo "Instance never entered REBOOT status"
        return 1
    fi
    if ! timeout ${REBOOT_TIMEOUT} sh -c "while ! nova show ${image_id}|grep status|grep ACTIVE; do sleep 1;done"; then
        echo "Instance never returned to ACTIVE status"
        return 1
    fi
}

function 060_nova_image-create() {
    # usage: nova image-create <server> <name>
    local image_id=${DEFAULT_INSTANCE_NAME}
    nova image-create ${image_id} ${DEFAULT_SNAP_NAME}

    if ! timeout ${BOOT_TIMEOUT} sh -c "while ! nova image-show ${DEFAULT_SNAP_NAME} | grep ACTIVE; do sleep 1; done"; then
        echo "Snapshot not created within ${BOOT_TIMEOUT} seconds"
        return 1
    fi
}

function 064_nova_image-delete() {
    # usage: nova image-delete <image>
    local image_id=${DEFAULT_SNAP_NAME}
    nova image-delete ${image_id}

    if ! timeout ${ACTIVE_TIMEOUT} sh -c "while nova image-list | grep ${DEFAULT_SNAP_NAME}; do sleep 1; done"; then
        echo "Snapshot not deleted within ${ACTIVE_TIMEOUT} seconds"
        return 1
    fi
}

function 065_nova-rename() {
    local image_id=${DEFAULT_INSTANCE_NAME}
    nova rename ${image_id} ${DEFAULT_INSTANCE_NAME}-rename
    if ! timeout $ACTIVE_TIMEOUT sh -c "while ! nova show ${image_id}-rename|grep name| grep $DEFAULT_INSTANCE_NAME-rename; do sleep 1; done"; then
        echo "Unable to rename instance"
        return 1
    fi
}

function 099_nova-delete() {
    # usage: nova delete <server>
    local image_id=${DEFAULT_INSTANCE_NAME}-rename
    nova delete ${image_id}
    if ! timeout $ACTIVE_TIMEOUT sh -c "while nova list | grep ${image_id}; do sleep 1; done"; then
	echo "Unable to delete instance: ${DEFAULT_INSTANCE_NAME}"
	return 1
    fi
}

function 110_custom_key-nova_boot() {
    SKIP_MSG="Not Implemented in diablo-final"
    SKIP_TEST=1

    nova boot --flavor ${INSTANCE_TYPE} --image ${IMAGE} --key_path $SHARED_PUB_KEY ${DEFAULT_INSTANCE_NAME}
    if ! timeout $ACTIVE_TIMEOUT sh -c "while ! nova list | grep ${DEFAULT_INSTANCE_NAME} | grep ACTIVE; do sleep 1; done"; then
        echo "Instance ${DEFAULT_INSTANCE_NAME} failed to boot"
        return 1
    fi
}

function 111_custom_key-verify_ssh_key() {
    SKIP_MSG="Not Implemented in diablo-final"
    SKIP_TEST=1

    local image_id=${DEFAULT_INSTANCE_NAME}
    INSTANCE_IP=$(nova show ${image_id} | grep ${DEFAULT_NETWORK_NAME} | cut -d'|' -f3)
    if ! timeout $BOOT_TIMEOUT sh -c "while ! nc ${INSTANCE_IP} 22 -w 1 -q 0 < /dev/null; do sleep 1; done"; then
        echo "port 22 never became available"
        return 1
    fi
    timeout $ACTIVE_TIMEOUT sh -c "ssh ${INSTANCE_IP} -i ${SHARED_PRIV_KEY} ${SSH_OPTS} -l root -- id"
}

function 112_custom_key-nova_delete() {
    SKIP_MSG="Not Implemented in diablo-final"
    SKIP_TEST=1

    local image_id=${DEFAULT_INSTANCE_NAME}
    nova delete ${image_id}
    if ! timeout $ACTIVE_TIMEOUT sh -c "while nova list | grep ${image_id}; do sleep 1; done"; then
        echo "Unable to delete instance: ${DEFAULT_INSTANCE_NAME}"
        return 1
    fi
}

function 210_file_injection-nova_boot() {
    SKIP_MSG="Not Implemented in diablo-final"
    SKIP_TEST=1

    local instance_name=${DEFAULT_INSTANCE_NAME}-injection
    local FILE_OPTS="--file /tmp/foo.txt=exercises/include/foo.txt"
    local BOOT_OPTS="--flavor ${INSTANCE_TYPE} --image ${IMAGE}"
    local KEY_OPTS="--key_name ${TEST_KEY_NAME}"
    local SEC_OPTS="--security_groups ${SECGROUP}"

    nova boot ${BOOT_OPTS} ${KEY_OPTS} ${FILE_OPTS} ${SEC_OPTS} ${SECGROUP} ${instance_name}
    if ! timeout $ACTIVE_TIMEOUT sh -c "while ! nova list | grep ${instance_name} | grep ACTIVE; do sleep 1; done"; then
        echo "Instance ${instance_name} failed to boot"
        return 1
    fi
}

function 211_file_injection-verify_file_contents() {
    SKIP_MSG="Not Implemented in diablo-final"
    SKIP_TEST=1

    local instance_name=${DEFAULT_INSTANCE_NAME}
    local KEY_OPTS="-i ${TMPDIR}/${TEST_PRIV_KEY}"
    INSTANCE_IP=$(nova show ${instance_name} | grep ${DEFAULT_NETWORK_NAME} | cut -d'|' -f3)
    if ! timeout $BOOT_TIMEOUT sh -c "while ! nc ${INSTANCE_IP} 22 -w 1 -q 0 < /dev/null; do sleep 1; done"; then
        echo "port 22 never became available"
        return 1
    fi
    timeout $ACTIVE_TIMEOUT sh -c "ssh ${INSTANCE_IP} ${KEY_OPTS} ${SSH_OPTS} -l root -- cat /tmp/foo.txt"
}

function 212_file_injection-nova_delete() {
    SKIP_MSG="Not Implemented in diablo-final"
    SKIP_TEST=1

    local instance_name=${DEFAULT_INSTANCE_NAME}-injection
    nova delete ${instance_name}
    if ! timeout $ACTIVE_TIMEOUT sh -c "while nova list | grep ${instance_name}; do sleep 1; done"; then
        echo "Unable to delete instance: ${instance_name}"
        return 1
    fi
}

function 200_nova_keypair-delete() {
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

function 201_nova_secgroup-delete-group-rule() {
    # usage: nova secgroup-delete-group-rule [--ip_proto <ip_proto>] [--from_port <from_port>]
    #                                     [--to_port <to_port>] <secgroup> <source_group>
    nova secgroup-delete-group-rule --ip_proto tcp --from_port 80 --to_port 80 $SECGROUP $SOURCE_SECGROUP
    if ! timeout $ASSOCIATE_TIMEOUT sh -c "while nova secgroup-list-rules $SECGROUP | grep $SOURCE_SECGROUP; do sleep 1; done"; then
        echo "Security group rule not added"
        return 1
    fi
}

function 202_nova_secgroup-delete-rule() {
    # usage: nova secgroup-delete-rule <secgroup> <ip_proto> <from_port> <to_port> <cidr>
    nova secgroup-delete-rule $SECGROUP tcp 22 22 0.0.0.0/0
    if ! timeout $ASSOCIATE_TIMEOUT sh -c "while nova secgroup-list-rules $SECGROUP | grep tcp; do sleep 1; done"; then
        echo "SSH: Security group rule not deleted"
        return 1
    fi
    nova secgroup-delete-rule $SECGROUP icmp -1 -1 0.0.0.0/0
    if ! timeout $ASSOCIATE_TIMEOUT sh -c "while nova secgroup-list-rules $SECGROUP | grep icmp; do sleep 1; done"; then
        echo "PING: Security group rule not deleted"
        return 1
    fi
}

function 203_nova_secgroup-delete() {
  # usage: nova secgroup-delete <secgroup>
    nova secgroup-delete $SECGROUP
    if ! timeout $ASSOCIATE_TIMEOUT sh -c "while nova secgroup-list | grep $SECGROUP; do sleep 1; done"; then
        echo "Security group not deleted"
        return 1
    fi
}
