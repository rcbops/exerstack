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
    IMAGE=$(nova image-list|egrep $DEFAULT_IMAGE_NAME|head -1|cut -d" " -f1)

    # Define secgroup
    SECGROUP=${SECGROUP:-test_nova_cli_secgroup}

    # Boot this image, use first AMi image if unset
    DEFAULT_IMAGE_NAME=${DEFAULT_IMAGE_NAME:-server}

    # Default floating IP pool name
    DEFAULT_FLOATING_POOL=${DEFAULT_FLOATING_POOL:-nova}

    # Additional floating IP pool and range
    TEST_FLOATING_POOL=${TEST_FLOATING_POOL:-test}
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
#    flavor-list         Print a list of available 'flavors' (sizes of
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
#    secgroup-add-group-rule
#                        Add a source group rule to a security group.
#    secgroup-add-rule   Add a rule to a security group.
#    secgroup-delete-group-rule
#                        Delete a source group rule from a security group.
#    secgroup-delete-rule
#                        Delete a rule from a security group.
#    secgroup-list-rules
#                        List rules for a security group.
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
#    help                Display help about this program or one of its
#                        subcommands.

function 010_nova_image-list() {
  if ! nova image-list|egrep $DEFAULT_IMAGE_NAME; then
    echo "Unable to find DEFAULT_IMAGE_NAME"
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

function 025_nova_secgroup-add-rule() {
  # usage: nova secgroup-add-rule <secgroup> <ip_proto> <from_port> <to_port> <cidr>
  nova secgroup-add-rule $SECGROUP icmp -1 -1 0.0.0.0/0
  if ! timeout $ASSOCIATE_TIMEOUT sh -c "while ! nova secgroup-list-rules $SECGROUP | grep icmp; do sleep 1; done"; then
    echo "Security group rule not added"
    return 1
  fi 
}

function 998_nova_secgroup-delete-rule() {
  # usage: nova secgroup-delete-rule <secgroup> <ip_proto> <from_port> <to_port> <cidr>
  nova secgroup-delete-rule $SECGROUP icmp -1 -1 0.0.0.0/0
  if ! timeout $ASSOCIATE_TIMEOUT sh -c "while nova secgroup-list-rules $SECGROUP | grep icmp; do sleep 1; done"; then
    echo "Security group rule not deleted"
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
