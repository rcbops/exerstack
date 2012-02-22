#!/usr/bin/env bash

function setup() {
    # Max time to wait while vm goes from build to active state
    ACTIVE_TIMEOUT=${ACTIVE_TIMEOUT:-30}

    # Max time till the vm is bootable
    BOOT_TIMEOUT=${BOOT_TIMEOUT:-30}

    # Max time to wait for proper association and dis-association.
    ASSOCIATE_TIMEOUT=${ASSOCIATE_TIMEOUT:-15}

    # Instance name
    DEFAULT_INSTANCE_NAME=${DEFAULT_INSTANCE_NAME:-test_nova_cli_instance}

    # Instance type to create
    DEFAULT_INSTANCE_TYPE=${DEFAULT_INSTANCE_TYPE:-m1.tiny}

    # Boot this image, use first AMi image if unset
    DEFAULT_IMAGE_NAME=${DEFAULT_IMAGE_NAME:-ubuntu-11.04-server}

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
  if ! nova show ${image_id} |grep user_id|grep $NOVA_USERNAME; then
    echo "nova show: user_id is not correct"
    return 1
  fi
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
    SKIP_MSG="No floating ip"
    SKIP_TEST=1
    return 1
  fi

  FLOATING_IP=$(echo ${IP} | cut -d' ' -f13)

  # Associate floating address
  # usage: nova add-floating-ip <server> <address>
  nova add-floating-ip ${image_id} ${FLOATING_IP}
  
  if timeout ${ASSOCIATE_TIMEOUT} sh -c "while ! nova show ${image_id} | grep ${DEFAULT_NETWORK_NAME} | grep ${FLOATING_IP}; do sleep 1; done"; then
    echo "floating ip ${ip} not removed within ${ASSOCIATE_TIMEOUT} seconds"
    return 1
  fi

  # Test we can ping our floating ip within ASSOCIATE_TIMEOUT seconds
  if ! timeout $ASSOCIATE_TIMEOUT sh -c "while ! ping -c1 -w1 $FLOATING_IP; do sleep 1; done"; then
    echo "Couldn't ping server with floating ip"
    return 1
  fi
}

function 053_nova-boot_verify_ssh_key() {
  local image_id=${DEFAULT_INSTANCE_NAME}
  local ip=${FLOATING_IP}

  [ $NOVA_HAS_FLOATING -eq 1 ] || ip=$(nova show ${image_id} | grep ${DEFAULT_NETWORK_NAME}  | cut -f4)
  
  if ! timeout ${BOOT_TIMEOUT} sh -c "while ! ping -c1 -w1 ${ip}; do sleep 1; done"; then
    echo "Could not ping server with floating/local ip"
    return 1
  fi

  if ! timeout ${BOOT_TIMEOUT} sh -c "while ! nc ${ip} 22 -w 1 -q 0 < /dev/null; do sleep 1; done"; then
    echo "port 22 never became available"
    return 1
  fi

  timeout ${ACTIVE_TIMEOUT} ssh ${ip} -i $TMPDIR/$TEST_PRIV_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -l root -- id
}

function 054_nova_remove-floating-ip() {
  local image_id=${DEFAULT_INSTANCE_NAME}
  local ip=${FLOATING_IP}

  [ $NOVA_HAS_FLOATING -eq 1 ] || SKIP_TEST=1; SKIP_MSG="No floating ips"; return 1

  # usage: nova remove-floating-ip <server> <address>
  nova remove-floating-ip ${image_id} ${ip}

  if ! timeout ${ASSOCIATE_TIMEOUT} sh -c "while nova show ${DEFAULT_INSTANCE_NAME} | grep ${DEFAULT_NETWORK_NAME} | grep ${ip}; do sleep 1; done"; then
    echo "floating ip ${ip} not removed within ${ASSOCIATE_TIMEOUT} seconds"
    return 1
  fi
}

function 055_nova-pause() {
  local image_id=${DEFAULT_INSTANCE_NAME}
  if ! nova pause ${image_id}; then
    echo "Unable to pause instance"
    return 1
  fi
  if ! timeout ${ACTIVE_TIMEOUT} sh -c "while ! nova show ${image_id}|grep status|grep PAUSED; do sleep 1; done"; then
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
  if ! timeout $ACTIVE_TIMEOUT sh -c "while ! nova show ${image_id}|grep status|grep ACTIVE; do sleep 1; done";  then
    echo "Instance was not unpaused successfully"
    return 1
  fi
}

function 057_nova-suspend() {
  local image_id=${DEFAULT_INSTANCE_NAME}
  if ! nova suspend ${image_id}; then
    echo "Unable to suspend instance"
    return 1
  fi
  if ! timeout ${BOOT_TIMEOUT} sh -c "while ! nova show ${image_id}|grep status|grep SUSPENDED; do sleep 1; done"; then
    echo "Instance was not suspended successfully"
    return 1
  fi
}

function 058_nova-resume() {
  local image_id=${DEFAULT_INSTANCE_NAME}
  if ! nova resume ${image_id}; then
    echo "Unable to resume instance"
    return 1
  fi
  if ! timeout ${BOOT_TIMEOUT} sh -c "while ! nova show ${image_id}|grep status|grep ACTIVE; do sleep 1; done";  then
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
  if ! timeout $BOOT_TIMEOUT sh -c "while ! nova show ${image_id}|grep status|grep ACTIVE; do sleep 1;done"; then
    echo "Instance never returned to ACTIVE status"
    return 1
  fi
}

function 060_nova-rename() {
  local image_id=${DEFAULT_INSTANCE_NAME}
  nova rename ${image_id} ${DEFAULT_INSTANCE_NAME}-rename
  if ! timeout $ACTIVE_TIMEOUT sh -c "while ! nova show ${image_id}-rename|grep name| grep $DEFAULT_INSTANCE_NAME-rename; do sleep 1; done"; then
    echo "Unable to rename instance"
    return 1
  fi
}

function 061_nova_image-create() {
  # usage: nova image-create <server> <name>
  SKIP_MSG="Not Implemented Yet"
  SKIP_TEST=1
  return 1
}

function 064_nova_image-delete() {
  # usage: nova image-delete <image>
  SKIP_MSG="Not Implemented Yet"
  SKIP_TEST=1
  return 1
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

### Additional spin up tests ###

function 100_custom_key-nova-boot() {
  SKIP_MSG="Breaks metadata requests"
  SKIP_TEST=1
#  nova boot --flavor ${INSTANCE_TYPE} --image ${IMAGE} --key_path $SHARED_PUB_KEY ${DEFAULT_INSTANCE_NAME}
#  if ! timeout $ACTIVE_TIMEOUT sh -c "while ! nova list | grep ${DEFAULT_INSTANCE_NAME} | grep ACTIVE; do sleep 1; done"; then
#    echo "Instance ${DEFAULT_INSTANCE_NAME} failed to boot"
#    return 1
#  fi
}

function 101_custom_key-verify_ssh_key() {
  SKIP_MSG="Breaks metadata requests"
  SKIP_TEST=1
#  INSTANCE_IP=$(nova list | grep ${DEFAULT_INSTANCE_NAME}  | cut -d" " -f8 | sed -e 's/public=//g' | sed -e 's/;//g')
#  if ! timeout $BOOT_TIMEOUT sh -c "while ! nc ${INSTANCE_IP} 22 -w 1 -q 0 < /dev/null; do sleep 1; done"; then
#    echo "port 22 never became available"
#    return 1
#  fi
#  timeout $ACTIVE_TIMEOUT ssh ${INSTANCE_IP} -i ${SHARED_PRIV_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -l root -- id
}

function 102_custom_key-nova-delete() {
  SKIP_MSG="Breaks metadata requests"
  SKIP_TEST=1
#  local image_id=${DEFAULT_INSTANCE_NAME}
#  nova delete ${image_id}
#  if ! timeout $ACTIVE_TIMEOUT sh -c "while nova list | grep ${image_id}; do sleep 1; done"; then
#    echo "Unable to delete instance: ${DEFAULT_INSTANCE_NAME}"
#    return 1
#  fi
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
