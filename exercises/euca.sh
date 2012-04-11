#!/usr/bin/env bash

function setup() {
    # Max time to wait while vm goes from build to active state
    ACTIVE_TIMEOUT=${ACTIVE_TIMEOUT:-30}

    # Max time till the vm is bootable
    BOOT_TIMEOUT=${BOOT_TIMEOUT:-30}

    # Max time to wait for proper association and dis-association.
    ASSOCIATE_TIMEOUT=${ASSOCIATE_TIMEOUT:-15}

    # Instance type to create
    DEFAULT_INSTANCE_TYPE=${DEFAULT_INSTANCE_TYPE:-m1.tiny}

    # Keypair to make
    EUCA_KEYPAIR=${EUCA_KEYPAIR:-euca_test_keypair}

    # Find an image to spin
    EUCA_IMAGE=$(euca-describe-images | grep machine | cut -f2 | head -n1)

    # Define secgroup
    EUCA_SECGROUP=euca_secgroup

    # Determine euca2ools version
    EUCA_VERSION=$(euca-version  | cut -d" " -f2)
}


function 010_add_secgroup() {
    # Add a secgroup
    if ! euca-describe-groups | grep -q $EUCA_SECGROUP; then
        euca-add-group -d "$EUCA_SECGROUP description" $EUCA_SECGROUP
        if ! timeout $ASSOCIATE_TIMEOUT sh -c "while ! euca-describe-groups | grep -q $EUCA_SECGROUP; do sleep 1; done"; then
            echo "Security group not created"
	    return 1
        fi
    fi
}

function 020_apply_secgroup_rule() {
    # Authorize pinging & ssh
    euca-authorize -P icmp -s 0.0.0.0/0 -t -1:-1 ${EUCA_SECGROUP}
    euca-authorize -P tcp -s 0.0.0.0/0 -p 22-22 ${EUCA_SECGROUP}
}

function 030_generate_keypair() {
    # throw down some pemmage
    euca-add-keypair ${EUCA_KEYPAIR} > ${TMPDIR}/${EUCA_KEYPAIR}.pem
    chmod 600 ${TMPDIR}/${EUCA_KEYPAIR}.pem
}


function 040_launch_instance() {
    # Launch it
    EUCA_INSTANCE=$(euca-run-instances -k ${EUCA_KEYPAIR} -g $EUCA_SECGROUP -t $DEFAULT_INSTANCE_TYPE $EUCA_IMAGE | grep INSTANCE | cut -f2)

    # Assure it has booted within a reasonable time
    if ! timeout $RUNNING_TIMEOUT sh -c "while ! euca-describe-instances $EUCA_INSTANCE | grep -q running; do sleep 1; done"; then
        echo "server didn't become active within $RUNNING_TIMEOUT seconds"
	return 1
    fi
}

function 050_associate_floating_ip() {
    # Allocate floating address
    FLOATING_IP=$(euca-allocate-address | cut -d" " -f2)

    EUCA_HAS_FLOATING=1
    if [[ ${FLOATING_IP} =~ "Zero" ]]; then
	EUCA_HAS_FLOATING=0
	SKIP_MSG="No floating ips"
	SKIP_TEST=1
	return 1
    fi

    # Associate floating address
    euca-associate-address -i $EUCA_INSTANCE $FLOATING_IP

    # Test we can ping our floating ip within ASSOCIATE_TIMEOUT seconds
    if ! timeout $ASSOCIATE_TIMEOUT sh -c "while ! ping -c1 -w1 $FLOATING_IP; do sleep 1; done"; then
        echo "Couldn't ping server with floating ip"
	return 1
    fi
}

function 055_verify_ssh_key() {
    # Fedora is running an old version of euca2ools
    # main-31337 2009-04-04
    if skip_if_distro "BeefyMiracle"; then return 0; fi

    # wait for 22 to become available
    local ip=${FLOATING_IP}

    if [ ${EUCA_HAS_FLOATING} -eq 0 ]; then
        if [[ ${EUCA_VERSION} < "2.0.0" ]]; then
            ip=$(euca-describe-instances | grep "$EUCA_INSTANCE" | cut -f4)
        else
            ip=$(euca-describe-instances | grep "$EUCA_INSTANCE" | cut -f17)
        fi
    fi

    # Test we can ping our floating ip within ASSOCIATE_TIMEOUT seconds
    if ! timeout $(( BOOT_TIMEOUT + ASSOCIATE_TIMEOUT )) sh -c "while ! ping -c1 -w1 $ip; do sleep 1; done"; then
        echo "Couldn't ping server with floating/local ip"
	return 1
    fi

    if ! timeout ${BOOT_TIMEOUT} sh -c "while ! nc ${ip} 22 -w 1 -q 0 < /dev/null; do sleep 1; done"; then
	echo "port 22 never became available"
	return 1
    fi

    timeout ${ACTIVE_TIMEOUT} ssh ${ip} -i ${TMPDIR}/${EUCA_KEYPAIR}.pem -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -l root -- id
}

function 060_disassociate_floating_ip() {
    [ $EUCA_HAS_FLOATING -eq 1 ] || SKIP_TEST=1; SKIP_MSG="No floating ips"; return

    # Release floating address
    euca-disassociate-address $FLOATING_IP

    # Wait just a tick for everything above to complete so release doesn't fail
    if ! timeout $ASSOCIATE_TIMEOUT sh -c "while euca-describe-addresses | grep $EUCA_INSTANCE | grep -q $FLOATING_IP; do sleep 1; done"; then
        echo "Floating ip $FLOATING_IP not disassociated within $ASSOCIATE_TIMEOUT seconds"
	return 1
    fi
}

function 065_delete_keypair() {
    # remove pem pair
    euca-delete-keypair ${EUCA_KEYPAIR}
}

function 070_terminate_instance() {
    # Terminate instance
    euca-terminate-instances $EUCA_INSTANCE

    if ! timeout $ACTIVE_TIMEOUT sh -c "while euca-describe-instances | grep $EUCA_INSTANCE; do sleep 1; done"; then
        echo "Unable to delete instance ${EUCA_INSTANCE}"
        return
    fi
}

function 080_revoke_secgroup_rule() {
    # Revoke pinging & ssh
    euca-revoke -P icmp -s 0.0.0.0/0 -t -1:-1 ${EUCA_SECGROUP}
    euca-revoke -P tcp -s 0.0.0.0/0 -p 22-22 ${EUCA_SECGROUP}
}

function 085_remove_security_group() {
    # Delete group
    euca-delete-group $EUCA_SECGROUP

    if ! timeout $ASSOCIATE_TIMEOUT sh -c "while euca-describe-groups | grep -q $EUCA_SECGROUP; do sleep 1; done"; then
        echo "Security group not deleted"
	return 1
    fi
}

function 090_release_floating() {
    [ $EUCA_HAS_FLOATING -eq 1 ] || SKIP_TEST=1; SKIP_MSG="No floating ips"; return

    # Release floating address
    euca-release-address $FLOATING_IP

    # Wait just a tick for everything above to complete so terminate doesn't fail
    if ! timeout $ASSOCIATE_TIMEOUT sh -c "while euca-describe-addresses | grep -q $FLOATING_IP; do sleep 1; done"; then
        echo "Floating ip $FLOATING_IP not released within $ASSOCIATE_TIMEOUT seconds"
	return 1
    fi
}
