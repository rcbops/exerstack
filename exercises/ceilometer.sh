#!/usr/bin/env bash

function setup() {

    pass
}

#   meter-list          List the user's meter
#   project-list        List the projects
#   resource-list       List the resources
#   sample-list         List the samples for this meters
#   user-list           List the users


function 010_meter-list() {

    if ! ceilometer meter-list
        echo "Could not get meter-list from ceilometer"
        return 1
    fi
}

function 020_project-list() {

    if ! ceilometer project-list
        echo "Could not get project-list from ceilometer"
        return 1
    fi
}

function 030_resource-list() {

    if ! ceilometer resource-list
        echo "Could not get resource-list from ceilometer"
        return 1
    fi
}

function 040_sample-list() {

    if ! ceilometer sample-list
        echo "Could not get sample-list from ceilometer"
        return 1
    fi
}

function 050_user-list() {

    if ! ceilometer user-list
        echo "Could not get user-list from ceilometer"
        return 1
    fi
}
