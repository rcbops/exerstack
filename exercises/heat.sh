#!/usr/bin/env bash

#  stack-list              List all of the stacks
#  stack-create            Create a stack
#  stack-show              Show Details on a stack
#  template-show           Show detailed information on a Template
#  template-validate       Validate a Template
#  resource-list           List all resources
#  resource-metadata       Show metadata on a resource
#  resource-show           Show detailed information on a resource
#  event-list              List all events
#  event-list w/resource   List all Events for a resource
#  event-show              Show detailed information on an event


function setup() {
  # Create a Heat Key to use
  TIMEOUT=${TIMEOUT:-120}
  NOSEC="--insecure"
  HCMD="heat ${NOSEC}"
  KEYNAME="HeatExerstackKey"
  if [ ! -f "/tmp/${KEYNAME}" ];then
    ssh-keygen -t rsa -f /tmp/${KEYNAME} -N ''
  fi
  nova ${NOSEC} keypair-add ${KEYNAME} --pub-key /tmp/${KEYNAME}.pub
  IMG_BASE_URL="https://launchpad.net/cirros/trunk/0.3.0"
  IMG_URL="${IMG_BASE_URL}/+download/cirros-0.3.0-x86_64-disk.img"
  HEAT_IMAGE_NAME="Cirros4Heat-$(date +%y%m%d%H%M)"
  IMG_LOCATION="/tmp/${HEAT_IMAGE_NAME}.img"
  wget --quiet -O ${IMG_LOCATION} ${IMG_URL}
  glance ${NOSEC} image-create --name ${HEAT_IMAGE_NAME} \
                               --disk-format qcow2 \
                               --container-format bare \
                               --is-public True \
                               --file ${IMG_LOCATION}
  HEAT_IMAGE_ID=$(glance image-list | grep ${HEAT_IMAGE_NAME} | awk '{print $2}')
  GIT_BASE_URL="https://raw.github.com/openstack/heat-templates"
  TEMPLATE_URL="${GIT_BASE_URL}/master/hot/hello_world.yaml"
  STACK_PARAMS+="KeyName=${KEYNAME};"
  STACK_PARAMS+="InstanceType=m1.small;"
  STACK_PARAMS+="ImageId=${HEAT_IMAGE_ID};"
  STACK_PARAMS+="db_password=Pass1234"
  STACK_NAME="Stack${HEAT_IMAGE_NAME}"
}

function teardown() {
  # Remove Heat Private Key
  if [ ! -f "/tmp/${KEYNAME}" ];then
    rm /tmp/${KEYNAME}
  fi
  # Remove Heat Public Key
  if [ ! -f "/tmp/${KEYNAME}.pub" ];then
    rm /tmp/${KEYNAME}.pub
  fi
  # Remove Glance Image
  if [ "${HEAT_IMAGE_ID}" ];then
    glance image-delete ${HEAT_IMAGE_ID}
  fi
  # Remove Glance Image File
  if [ -f "${IMG_LOCATION}" ];then
    rm ${IMG_LOCATION}
  fi
  nova ${NOSEC} keypair-delete ${KEYNAME}
  unset KEYNAME STACK_NAME STACK_PARAMS TEMPLATE_URL GIT_BASE_URL HEAT_IMAGE_ID
  unset HEAT_IMAGE_NAME IMG_URL IMG_BASE_URL IMG_LOCATION TIMEOUT HCMD
}

function 010_stack-craete() {
  if ! ${HCMD} stack-create ${STACK_NAME} -u ${TEMPLATE_URL} \
                                          -P "${STACK_PARAMS}"; then
    echo "Could not perform heat stack-create"
    return 1
  fi

  WAITCMD="while ! ${HCMD} stack-list | grep ${STACK_NAME} | grep CREATE_COMPLETE;do sleep 2;done"
  if ! timeout ${TIMEOUT} sh -c "${WAITCMD}"; then
    echo "Stack ${STACK_NAME} failed to complete creation after ${TIMEOUT} seconds"
    NOSTACK=0
    return 1
  else
    NOSTACK=1
    STACKID=$(${HCMD} stack-list | grep ${STACK_NAME} | awk '{print $2}')
  fi
}

function 011_stack-list() {
  if [ "${NOSTACK}" -eq 0 ];then
    SKIP_MSG="No Stack Created for test or Stack Create has Failed"
    SKIP_TEST=1
    echo "skipping"
    return 1
  fi

  if ! ${HCMD} stack-list; then
    echo "Could not get stack-list from heat"
    return 1
  fi
}

function 012_stack-show() {
  if [ "${NOSTACK}" -eq 0 ];then
    SKIP_MSG="No Stack Created for test or Stack Create has Failed"
    SKIP_TEST=1
    echo "skipping"
    return 1
  fi

  if ! ${HCMD} stack-show ${STACKID};then
    echo "Could not perform heat stack-show"
    return 1
  fi
}

function 013_stack-update() {
  if [ "${NOSTACK}" -eq 0 ];then
    SKIP_MSG="No Stack Created for test or Stack Create has Failed"
    SKIP_TEST=1
    echo "skipping"
    return 1
  fi
  
  STACK_PARAMS+=";db_port=43210"
  if ! ${HCMD} stack-update ${STACKID} -P ${STACK_PARAMS} \
                                       -u ${TEMPLATE_URL};then
    echo "Could not perform heat stack-update"
    return 1
  fi
  WAITCMD="while ! ${HCMD} stack-list | grep ${STACK_NAME} | grep UPDATE_COMPLETE;do sleep 2;done"
  if ! timeout ${TIMEOUT} sh -c "${WAITCMD}"; then
      echo "Stack ${STACK_NAME} failed to update after ${TIMEOUT} seconds"
      return 1
  fi
}

function 020_template-show() {
  if [ "${NOSTACK}" -eq 0 ];then
    SKIP_MSG="No Stack Created for test or Stack Create has Failed"
    SKIP_TEST=1
    echo "skipping"
    return 1
  fi
  
  if ! ${HCMD} template-show ${STACKID};then
    echo "Could not perform heat template-show"
    return 1
  fi
}

function 021_template-validate() {
  if ! ${HCMD} template-validate -u ${TEMPLATE_URL} \
                                 -P "${STACK_PARAMS}";then
    echo "Could not perform heat template-validate"
    return 1
  fi
}

function 030_resource-list() {
  if [ "${NOSTACK}" -eq 0 ];then
    SKIP_MSG="No Stack Created for test or Stack Create has Failed"
    SKIP_TEST=1
    echo "skipping"
    return 1
  fi

  if ! ${HCMD} resource-list ${STACKID};then
    echo "Could not perform heat resource-list"
    RESOURCE=0
    RESOURCE_NAME="None"
    return 1
  else
    RESOURCE=1
    RESOURCE_NAME=$(${HCMD} resource-list ${STACKID} | grep CREATE_COMPLETE | head -n 1 | awk '{print $2}')
  fi
}

function 031_resource-metadata() {
  if [ "${RESOURCE}" -eq 0 ];then
    SKIP_MSG="No Resource Found"
    SKIP_TEST=1
    echo "skipping"
    return 1
  fi
  if ! ${HCMD} resource-metadata ${STACKID} ${RESOURCE_NAME};then
    echo "Could not perform heat resource-metadata"
    return 1
  fi
}

function 032_resource-show() {
  if [ "${NOSTACK}" -eq 0 ];then
    SKIP_MSG="No Stack Created for test or Stack Create has Failed"
    SKIP_TEST=1
    echo "skipping"
    return 1
  fi
  if ! ${HCMD} resource-show ${STACKID} ${RESOURCE_NAME};then
    echo "Could not perform heat resource-show"
    return 1
  fi
}

function 040_event-list() {
  if [ "${NOSTACK}" -eq 0 ];then
    SKIP_MSG="No Stack Created for test or Stack Create has Failed"
    SKIP_TEST=1
    echo "skipping"
    return 1
  fi
  if ! ${HCMD} event-list ${STACKID};then
    echo "Could not perform heat event-list"
    return 1
  else
    EVENT_ID=$(${HCMD} event-list ${STACKID} | grep CREATE_COMPLETE | head -n 1 | awk '{print $4}')
    if [ "${EVENT_ID}" ];then
      EVENT=1
    else
      EVENT=0
    fi
  fi
}

function 041_event-list-with-resource() {
  if [ "${NOSTACK}" -eq 0 ];then
    SKIP_MSG="No Stack Created for test or Stack Create has Failed"
    SKIP_TEST=1
    echo "skipping"
    return 1
  fi
  if [ "${RESOURCE}" -eq 0 ];then
    SKIP_MSG="No Resource Found"
    SKIP_TEST=1
    echo "skipping"
    return 1
  fi
  if ! ${HCMD} event-list ${STACKID} -r ${RESOURCE_NAME};then
    echo "Could not perform heat event-list with a defined resource"
    return 1
  fi
}

function 042_event-show() {
  if [ "${NOSTACK}" -eq 0 ];then
    SKIP_MSG="No Stack Created for test or Stack Create has Failed"
    SKIP_TEST=1
    echo "skipping"
    return 1
  fi
  if [ "${RESOURCE}" -eq 0 ];then
    SKIP_MSG="No Resource Found"
    SKIP_TEST=1
    echo "skipping"
    return 1
  fi
  if [ "${EVENT}" -eq 0 ];then
    SKIP_MSG="No Event ID Found"
    SKIP_TEST=1
    echo "skipping"
    return 1
  fi
  if ! ${HCMD} event-show ${STACKID} ${RESOURCE_NAME} ${EVENT_ID};then
    echo "Could not perform heat event-show with a defined resource and event ID"
    return 1
  fi
}

function 099_stack-delete() {
  if [ "${NOSTACK}" -eq 0 ];then
    SKIP_MSG="No Stack Created for test or Stack Create has Failed"
    SKIP_TEST=1
    echo "skipping"
    return 1
  fi

  if ! ${HCMD} stack-delete ${STACKID};then
    echo "Could not perform heat stack-delete"
    return 1
  fi
}
