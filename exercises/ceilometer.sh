#!/usr/bin/env bash

function setup() {
    USER=$(ceilometer user-list|egrep -v '^\+'|tail -1|cut -d' ' -f2)
    PROJECT=$(ceilometer project-list|egrep -v '^\+'|tail -1|cut -d' ' -f2)
}

#   meter-list          List the user's meter
#   project-list        List the projects
#   resource-list       List the resources
#   sample-list         List the samples for this meters
#   user-list           List the users

#   note: we are not able to do anything interesting with the cli
#   and so these tests are effectively just ensuring that the commands
#   run without error


function 010_meter-list() {

    if ! ceilometer meter-list; then
        echo "Could not get meter-list from ceilometer"
        return 1
    fi
}

function 020_meter-list_for_user() {

    if [ -z $USER ]; then
        SKIP_TEST=1
        SKIP_MSG='No ceilometer user registered'
        return 1
    fi

    if ! ceilometer meter-list -u ${USER}; then
        echo "Could not get meter-list from ceilometer for user ${USER}"
        return 1
    fi
}

function 030_meter-list_for_project() {

    if [ -z $PROJECT ]; then
        SKIP_TEST=1
        SKIP_MSG='No ceilometer project registered'
        return 1
    fi

    if ! ceilometer meter-list -p ${PROJECT}; then
        echo "Could not get meter-list from ceilometer for user ${USER}"
        return 1
    fi
}


function 040_resource-list() {

    if ! ceilometer resource-list; then
        echo "Could not get resource-list from ceilometer"
        return 1
    fi
}

function 050_resource-list_for_user() {

    if [ -z $USER ]; then
        SKIP_TEST=1
        SKIP_MSG='No ceilometer user registered'
        return 1
    fi

    if ! ceilometer resource-list -u ${USER}; then
        echo "Could not get resource-list from ceilometer for user ${USER}"
        return 1
    fi
}

function 060_resource-list_for_project() {

    if [ -z $PROJECT ]; then
        SKIP_TEST=1
        SKIP_MSG='No ceilometer project registered'
        return 1
    fi

    if ! ceilometer resource-list -p ${PROJECT}; then
        echo "Could not get resource-list from ceilometer for user ${USER}"
        return 1
    fi
}

function 070_project-list() {

    if ! ceilometer project-list; then
        echo "Could not get project-list from ceilometer"
        return 1
    fi
}

function 080_sample-list() {

    if ! ceilometer sample-list; then
        echo "Could not get sample-list from ceilometer"
        return 1
    fi
}

function 090_user-list() {

    if ! ceilometer user-list; then
        echo "Could not get user-list from ceilometer"
        return 1
    fi
}
