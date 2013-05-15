#!/usr/bin/env bash

function setup() {
    # Max time to wait for volume operations (specifically create and delete)
    VOLUME_TIMEOUT=${VOLUME_TIMEOUT:-240}
    # Default volume name
    DEFAULT_VOLUME_NAME=${DEFAULT_VOLUME_NAME:-test-volume}
    # Default volume name
    DEFAULT_TYPE_NAME=${DEFAULT_TYPE_NAME:-test-type}
    # Name for volume snapshot
    DEFAULT_VOLUME_SNAP_NAME=${DEFAULT_VOLUME_SNAP_NAME:-test-volume-snapshot}

    if [ -e /etc/redhat-release ]; then
        CINDER_VOLUME_SERVICE='openstack-cinder-volume'
    else
        CINDER_VOLUME_SERVICE='cinder-volume'
    fi

    # create a faked volume group for testing, if we don't already have one
    if ! vgdisplay cinder-volumes ; then
        dd if=/dev/zero of=${TMPDIR}/cinder-volumes bs=1 count=0 seek=6G
        losetup /dev/loop3 ${TMPDIR}/cinder-volumes
        pvcreate /dev/loop3
        vgcreate cinder-volumes /dev/loop3
        service ${CINDER_VOLUME_SERVICE} restart
        sleep 5
    fi
}

#    absolute-limits     Print a list of absolute limits for a user
#    create              Add a new volume.
#    credentials         Show user credentials returned from auth
#    delete              Remove a volume.
#    endpoints           Discover endpoints that get returned from the
#                        authenticate services
#    list                List all the volumes.
#    quota-class-show    List the quotas for a quota class.
#    quota-class-update  Update the quotas for a quota class.
#    quota-defaults      List the default quotas for a tenant.
#    quota-show          List the quotas for a tenant.
#    quota-update        Update the quotas for a tenant.
#    rate-limits         Print a list of rate limits for a user
#    show                Show details about a volume.
#    snapshot-create     Add a new snapshot.
#    snapshot-delete     Remove a snapshot.
#    snapshot-list       List all the snapshots.
#    snapshot-show       Show details about a snapshot.
#    type-create         Create a new volume type.
#    type-delete         Delete a specific flavor
#    type-list           Print a list of available 'volume types'.


function 010_cinder_limits() {
    SKIP_TEST=1
    SKIP_MSG='pending cinderclient bug 1180059'
    return 1
    if ! cinder absolute-limits; then
        echo "could not get api limits"
        return 1
    fi
}

function 020_cinder_credentials() {
    if ! cinder credentials; then
        echo "could not get cinder credentials"
        return 1
    fi

}

function 030_cinder_endpoints() {
    if ! cinder endpoints; then
        echo "could not get endpoints"
        return 1
    fi
}

function 040_cinder_quota-defaults() {
    if ! cinder quota-defaults ${OS_TENANT_NAME}; then
        echo "could not get default quotas for tenant ${OS_TENANT_NAME}"
        return 1
    fi
}

function 050_cinder_quota-show() {
    if ! cinder quota-show ${OS_TENANT_NAME}; then
        echo "could not get actual quotas for tenant ${OS_TENANT_NAME}"
        return 1
    fi
}

function 060_cinder_quota-update() {
    CURRENT_VOLUME_QUOTA=$(cinder quota-show ${OS_TENANT_NAME}|grep -i volumes|cut -d'|' -f 3|sed -e 's/ //g')
    TARGET_VOLUME_QUOTA=$(( CURRENT_VOLUME_QUOTA +1 ))
    cinder quota-update --volumes ${TARGET_VOLUME_QUOTA} ${OS_TENANT_NAME}
    NEW_VOLUME_QUOTA=$(cinder quota-show ${OS_TENANT_NAME}|grep -i volumes|cut -d'|' -f 3|sed -e 's/ //g')

    if [ ${NEW_VOLUME_QUOTA} != ${TARGET_VOLUME_QUOTA} ]; then
        echo "could not update quotas for tenant"
        return 1
    fi
}

function 065_cinder_quota-class-show() {
    if ! cinder quota-class-show default ; then
        echo "could not get actual quotas for quota class default"
        return 1
    fi
}

function 068_cinder_quota-class-update() {
    CURRENT_VOLUME_QUOTA_CLASS=$(cinder quota-class-show default |grep -i volumes|cut -d'|' -f 3|sed -e 's/ //g')
    TARGET_VOLUME_QUOTA=$(( CURRENT_VOLUME_QUOTA_CLASS +1 ))
    cinder quota-class-update --volumes ${TARGET_VOLUME_QUOTA} default
    NEW_VOLUME_QUOTA=$(cinder quota-class-show default|grep -i volumes|cut -d'|' -f 3|sed -e 's/ //g')

    if [ ${NEW_VOLUME_QUOTA} != ${TARGET_VOLUME_QUOTA} ]; then
        echo "could not update quotas for quota-class default"
        return 1
    fi
}

function 070_cinder_rate-limits() {
    SKIP_TEST=1
    SKIP_MSG='pending cinderclient bug 1180059'
    return 1
    if ! cinder rate-limits ; then
        echo "could not get actual quotas for tenant ${OS_TENANT_NAME}"
        return 1
    fi
}

function 080_cinder_type-create() {
    if ! TYPE_ID=$( cinder type-create ${DEFAULT_TYPE_NAME}| grep ${DEFAULT_TYPE_NAME}|cut -d'|' -f2); then
        echo "could not create volume type ${DEFAULT_TYPE_NAME}"
        return 1
    fi
}

function 090_cinder_type-list() {
    if ! cinder type-list | grep ${DEFAULT_TYPE_NAME} ; then
        echo "could not get volume type listing"
        return 1
    fi
}

function 100_cinder_create() {
    if VOLUME_ID=$(cinder create --display-name ${DEFAULT_VOLUME_NAME} --volume-type ${DEFAULT_TYPE_NAME} 1 | grep ' id ' | cut -d'|'  -f 3) ; then
        if ! timeout ${VOLUME_TIMEOUT} sh -c "while ! cinder list | grep ${DEFAULT_VOLUME_NAME} | grep available ; do sleep 1 ; done"; then
            echo "volume ${DEFAULT_VOLUME_NAME} did not become available in ${VOLUME_TIMEOUT} seconds"
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
        return 1
    fi
}

function 120_cinder_snapshot-create() {
    if SNAPSHOT_ID=$(cinder snapshot-create --display-name ${DEFAULT_VOLUME_SNAP_NAME} ${VOLUME_ID} | grep ' id ' | cut -d'|' -f3); then
        if ! timeout ${VOLUME_TIMEOUT} sh -c "while ! cinder snapshot-list | grep ${DEFAULT_VOLUME_SNAP_NAME} | grep available ; do sleep 1 ; done"; then
            echo "volume snapshot ${DEFAULT_VOLUME_SNAP_NAME} did not become available in ${VOLUME_TIMEOUT} seconds"
            return 1
        fi
    else
        echo "could not create snapshot of volume ${VOLUME_ID}"
        return 1
    fi
}

function 130_cinder_snapshot-delete() {
    if cinder snapshot-delete ${SNAPSHOT_ID}; then
        if ! timeout ${VOLUME_TIMEOUT} sh -c "while cinder snapshot-show ${SNAPSHOT_ID} ; do sleep 1 ; done"; then
            echo "snapshot did not get deleted properly within ${VOLUME_TIMEOUT} seconds"
            return 1
        fi
    else
        echo "could not delete snapshot ${SNAPSHOT_ID}"
        return 1
    fi
}

function 180_cinder_delete() {
    if cinder delete ${VOLUME_ID}; then
        if ! timeout ${VOLUME_TIMEOUT} sh -c "while cinder show ${VOLUME_ID} ; do sleep 1 ; done"; then
            echo "volume did not get deleted properly within ${VOLUME_TIMEOUT} seconds"
            return 1
        fi
    else
        echo "could not delete volume ${VOLUME_ID}"
        return 1
    fi
}

function 190_cinder_type-delete() {
    if ! cinder type-delete ${TYPE_ID}; then
        echo "could not delete volume type ${DEFAULT_TYPE_NAME}"
        return 1
    fi
}

function teardown() {
#    vgremove cinder-volumes
#    rm -fr ${TMPDIR}/cinder-volumes
#_    losetup -d /dev/loop3
return 0
}
