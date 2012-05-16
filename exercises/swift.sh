#!/usr/bin/env bash

# Test swift via the command line tools that ship with it.  Apparently
# there is no error so severe that the swift tool will return a non-zero
# return code, so we have to go to great lengths to check the results of
# the tool.

function setup() {
    # we could be testing either with keystone using auth-version 2, or
    # using swauth with auth-version 1.
    #
    # we will default to swauth

    SWIFT_AUTH_MODE=${SWIFT_AUTH_MODE:-keystone}
    SWIFT_TEST_CONTAINER=${SWIFT_TEST_CONTAINER:-test_container}

    if [ "${SWIFT_AUTH_MODE}" == "swauth" ]; then
        SWIFT_AUTH_ENDPOINT=${SWIFT_AUTH_ENDPOINT:-http://localhost:8080/auth/v1.0}
        SWIFT_AUTH_VERSION=""
        SWIFT_AUTH_USER=${SWIFT_AUTH_USER:-admin:admin}
        SWIFT_AUTH_PASSWORD=${SWIFT_AUTH_PASSWORD:-secrete}
    else
        SWIFT_AUTH_ENDPOINT=${SWIFT_AUTH_ENDPOINT:-${OS_AUTH_URL}}
        SWIFT_AUTH_VERSION="--auth-version 2"
        SWIFT_AUTH_USER=${SWIFT_AUTH_USER:-${NOVA_USERNAME}}
        SWIFT_AUTH_PASSWORD=${SWIFT_AUTH_PASSWORD:-${NOVA_PASSWORD}}
    fi

    SWIFT_EXEC="swift ${SWIFT_AUTH_VERSION} -A ${SWIFT_AUTH_ENDPOINT} -U ${SWIFT_AUTH_USER} -K ${SWIFT_AUTH_PASSWORD}"

    local containers=$($SWIFT_EXEC stat | grep "Containers" | awk '{ print $2 }')
    if [ "$containers" != "0" ]; then
        FAIL_REASON="Account already has data"
        return 1
    fi

    dd if=/dev/urandom bs=1024 count=1 of=${TMPDIR}/small.txt
    dd if=/dev/urandom bs=1024 count=1 of=${TMPDIR}/small2.txt
}

function 010_stat() {
    $SWIFT_EXEC stat | grep "Account"
}

function 020_create_container() {
    $SWIFT_EXEC post ${SWIFT_TEST_CONTAINER}
    $SWIFT_EXEC list | grep ${SWIFT_TEST_CONTAINER}
}

function 030_upload_file() {
    pushd ${TMPDIR} 2>&1
    $SWIFT_EXEC upload ${SWIFT_TEST_CONTAINER} small.txt
    $SWIFT_EXEC list ${SWIFT_TEST_CONTAINER} | grep small.txt
    popd 2>&1
}

function 040_download_file() {
    $SWIFT_EXEC download ${SWIFT_TEST_CONTAINER} small.txt -o - > ${TMPDIR}/small3.txt
    local original_md5=$(md5sum ${TMPDIR}/small.txt | awk '{ print $1 }')
    local new_md5=$(md5sum ${TMPDIR}/small3.txt | awk '{ print $1 }')

    if [ "${original_md5}" != "${new_md5}" ]; then
        echo "MD5 Checksums do not match!"
        return 1
    fi
}

function 050_update_file() {
    pushd ${TMPDIR} 2>&1
    $SWIFT_EXEC upload ${SWIFT_TEST_CONTAINER} small2.txt
    $SWIFT_EXEC list ${SWIFT_TEST_CONTAINER} | grep small2.txt
    popd 2>&1
}

function 060_verify_file() {
    $SWIFT_EXEC download ${SWIFT_TEST_CONTAINER} small2.txt -o - > ${TMPDIR}/small3.txt
    local original_md5=$(md5sum ${TMPDIR}/small2.txt | awk '{ print $1 }')
    local new_md5=$(md5sum ${TMPDIR}/small3.txt | awk '{ print $1 }')

    if [ "${original_md5}" != "${new_md5}" ]; then
        echo "MD5 Checksums do not match!"
        return 1
    fi
}

function 070_delete_container() {
    $SWIFT_EXEC delete ${SWIFT_TEST_CONTAINER}
    if $SWIFT_EXEC list | grep ${SWIFT_TEST_CONTAINER}; then
        echo "Container is still there!"
        return 1
    fi
}
