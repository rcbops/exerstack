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

    # Find an image to spin
    IMAGE=$(euca-describe-images | grep machine | cut -f2 | head -n1)

    # Define secgroup
    SECGROUP=euca_secgroup

}
function 005_something() {
    booger
}

function 010_add_secgroup() {
    # Add a secgroup
    if ! euca-describe-group | grep -q $SECGROUP; then
        euca-add-group -d "$SECGROUP description" $SECGROUP
        if ! timeout $ASSOCIATE_TIMEOUT sh -c "while ! euca-describe-group | grep -q $SECGROUP; do sleep 1; done"; then
            echo "Security group not created"
	    return 1
        fi
    fi
}


function 020_launch_instance() {
    # Launch it
    INSTANCE=$(euca-run-instances -g $SECGROUP -t $DEFAULT_INSTANCE_TYPE $IMAGE | grep INSTANCE | cut -f2)

    # Assure it has booted within a reasonable time
    if ! timeout $RUNNING_TIMEOUT sh -c "while ! euca-describe-instances $INSTANCE | grep -q running; do sleep 1; done"; then
        echo "server didn't become active within $RUNNING_TIMEOUT seconds"
	return 1
    fi
}

function 030_associate_floating_ip() {
    # Allocate floating address
    FLOATING_IP=`euca-allocate-address | cut -f2`

    # Associate floating address
    euca-associate-address -i $INSTANCE $FLOATING_IP

    # Authorize pinging
    euca-authorize -P icmp -s 0.0.0.0/0 -t -1:-1 $SECGROUP

    # Test we can ping our floating ip within ASSOCIATE_TIMEOUT seconds
    if ! timeout $ASSOCIATE_TIMEOUT sh -c "while ! ping -c1 -w1 $FLOATING_IP; do sleep 1; done"; then
        echo "Couldn't ping server with floating ip"
	return 1
    fi
}

function 040_secgroup_restrictions() {
    # Revoke pinging
    euca-revoke -P icmp -s 0.0.0.0/0 -t -1:-1 $SECGROUP

    # Delete group
    euca-delete-group $SECGROUP

    # Release floating address
    euca-disassociate-address $FLOATING_IP

    # Wait just a tick for everything above to complete so release doesn't fail
    if ! timeout $ASSOCIATE_TIMEOUT sh -c "while euca-describe-addresses | grep $INSTANCE | grep -q $FLOATING_IP; do sleep 1; done"; then
        echo "Floating ip $FLOATING_IP not disassociated within $ASSOCIATE_TIMEOUT seconds"
	return 1
    fi
}

function 050_release_floating() {
    # Release floating address
    euca-release-address $FLOATING_IP

    # Wait just a tick for everything above to complete so terminate doesn't fail
    if ! timeout $ASSOCIATE_TIMEOUT sh -c "while euca-describe-addresses | grep -q $FLOATING_IP; do sleep 1; done"; then
        echo "Floating ip $FLOATING_IP not released within $ASSOCIATE_TIMEOUT seconds"
	return 1
    fi
}

function 060_terminate_instance() {
    # Terminate instance
    euca-terminate-instances $INSTANCE
}
