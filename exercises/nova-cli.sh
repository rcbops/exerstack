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
    IMAGE=$(nova image-list|egrep $DEFAULT_IMAGE_NAME|head -1|cut -d" " -f2)

    # Find the instance type ID
    INSTANCE_TYPE=$(nova flavor-list | egrep $DEFAULT_INSTANCE_TYPE | head -1 | cut -d" " -f2)

    # Define secgroup
    SECGROUP=${SECGROUP:-test_nova_cli_secgroup}

    # Define a source_secgroup
    SOURCE_SECGROUP=${SOURCE_SECGROUP:-default}

    # Boot this image, use first AMi image if unset
    DEFAULT_IMAGE_NAME=${DEFAULT_IMAGE_NAME:-server}

    # Default floating IP pool name
    DEFAULT_FLOATING_POOL=${DEFAULT_FLOATING_POOL:-nova}

    # Additional floating IP pool and range
    TEST_FLOATING_POOL=${TEST_FLOATING_POOL:-test}

    # File name for generated keys
    TEST_KEY_NAME=${TEST_KEY_NAME:-nova_test_key}
    TEST_PRIV_KEY=${TEST_PRIV_KEY:-$TEST_KEY_NAME.pem}
    # TEST_PUB_KEY=${TEST_PUB_KEY:-$TEST_KEY_NAME.pub}
}

function teardown() {
	x = 1
}

#    actions             Retrieve server actions.
#    add-fixed-ip        Add new IP address to network.
#    add-floating-ip     Add a floating IP address to a server.
#    boot                Boot a new server.
#    delete              Immediately shut down and delete a server.
#    diagnostics         Retrieve server diagnostics.
#                        servers).
#    floating-ip-create  Allocate a floating IP for the current tenant.
#    floating-ip-delete  De-allocate a floating IP.
#    floating-ip-list    List floating ips for this tenant.
#    image-create        Create a new image by taking a snapshot of a running
#                        server.
#    image-delete        Delete an image.
#    image-meta          Set or Delete metadata on an image.
#    image-show          Show details about the given image.
#    keypair-add         Create a new key pair for use with instances
#    keypair-delete      Delete keypair by its id
#    keypair-list        Print a list of keypairs for a user
#    list                List active servers.
#    meta                Set or Delete metadata on a server.
#    migrate             Migrate a server.
#    pause               Pause a server.
#    reboot              Reboot a server.
#    rebuild             Shutdown, re-image, and re-boot a server.
#    remove-fixed-ip     Remove an IP address from a server.
#    remove-floating-ip  Remove a floating IP address from a server.
#    rename              Rename a server.
#    rescue              Rescue a server.
#    resize              Resize a server.
#    resize-confirm      Confirm a previous resize.
#    resize-revert       Revert a previous resize (and return to the previous
#                        VM).
#    resume              Resume a server.
#    root-password       Change the root password for a server.
#    show                Show details about the given server.
#    suspend             Suspend a server.
#    unpause             Unpause a server.
#    unrescue            Unrescue a server.
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
    echo "Unable to find DEFAULT_IMAGE_NAME"
    return 1
  fi
}

function 011_nova_flavor-list() {
  if ! nova flavor-list|egrep $DEFAULT_INSTANCE_TYPE; then
    echo "Unable to find DEFAULT_INSTANCE_TYPE"
    return 1
  fi
}

function 020_nova_secgroup-create() {
  # usage: nova secgroup-create <name> <description>
  if ! nova secgroup-list|grep $SECGROUP; then
    nova secgroup-create $SECGROUP "$SECGROUP description"
    if ! timeout $ASSOCIATE_TIMEOUT sh -c "while ! nova secgroup-list | grep $SECGROUP; do sleep 1; done"; then
      echo "Security group not created"
      return 1
    fi
  else
    echo "SECURITY GROUP: $SECGROUP already exists"
    return 1
  fi
}

function 021_nova_secgroup-add-rule() {
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

function 022_nova_secgroup-add-group-rule() {
  # usage: nova secgroup-add-group-rule [--ip_proto <ip_proto>] [--from_port <from_port>]
  #                                      [--to_port <to_port>] <secgroup> <source_group>
  nova secgroup-add-group-rule --ip_proto tcp --from_port 80 --to_port 80 $SECGROUP $SOURCE_SECGROUP
  if ! timeout $ASSOCIATE_TIMEOUT sh -c "while ! nova secgroup-list-rules $SECGROUP | grep $SOURCE_SECGROUP; do sleep 1; done"; then
    echo "Security group rule not added"
    return 1
  fi
}

function 030_nova_keypair-add() {
  # usage: nova keypair-add [--pub_key <pub_key>] <name>
  nova keypair-add $TEST_KEY_NAME > $TEST_PRIV_KEY
  if [ -e $TEST_PRIV_KEY ]; then
    chmod 600 $TEST_PRIV_KEY
  else
    echo "Private key $TEST_PRIV_KEY not redirected to file"
    return 1
  fi
  if ! timeout $ASSOCIATE_TIMEOUT sh -c "while ! nova keypair-list | grep $TEST_KEY_NAME; do sleep 1; done"; then
    echo "Keypair $TEST_KEY_NAME not created"
    return 1
  fi
}

function 031_nova_keypair-add--pub_key() {
  # usage: nova keypair-add [--pub_key <pub_key>] <name>
  nova keypair-add --pub_key $SHARED_PUB_KEY $SHARED_KEY_NAME
  if ! timeout $ASSOCIATE_TIMEOUT sh -c "while ! nova keypair-list | grep $SHARED_KEY_NAME; do sleep 1; done"; then
    echo "Keypair $SHARED_PRIV_KEY not imported"
    return 1
  fi
}

function 995_nova_keypair-delete--pub_key() {
  # usage: nova keypair-delete <name>
  nova keypair-delete $SHARED_KEY_NAME
  if ! timeout $ASSOCIATE_TIMEOUT sh -c "while nova keypair-list | grep $SHARED_KEY_NAME; do sleep 1; done"; then
    echo "Keypair $SHARED_KEY_NAME not deleted"
    return 1
  fi
}

function 996_nova_keypair-delete() {
  # usage: nova keypair-delete <name>
  nova keypair-delete $TEST_KEY_NAME
  if [ -e $TEST_PRIV_KEY ]; then
    rm $TEST_PRIV_KEY
  fi
  if ! timeout $ASSOCIATE_TIMEOUT sh -c "while nova keypair-list | grep $TEST_KEY_NAME; do sleep 1; done"; then
    echo "Keypair $TEST_PRIVATE_KEY not deleted"
    return 1
  fi
}

function 997_nova_secgroup-delete-group-rule() {
  # usage: nova secgroup-delete-group-rule [--ip_proto <ip_proto>] [--from_port <from_port>]
  #                                     [--to_port <to_port>] <secgroup> <source_group>
  nova secgroup-delete-group-rule --ip_proto tcp --from_port 80 --to_port 80 $SECGROUP $SOURCE_SECGROUP
  if ! timeout $ASSOCIATE_TIMEOUT sh -c "while nova secgroup-list-rules $SECGROUP | grep $SOURCE_SECGROUP; do sleep 1; done"; then
    echo "Security group rule not added"
    return 1
  fi
}

function 998_nova_secgroup-delete-rule() {
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

function 999_nova_secgroup-delete() {
  # usage: nova secgroup-delete <secgroup>
  nova secgroup-delete $SECGROUP
  if ! timeout $ASSOCIATE_TIMEOUT sh -c "while nova secgroup-list | grep $SECGROUP; do sleep 1; done"; then
    echo "Security group not deleted"
    return 1
  fi
}