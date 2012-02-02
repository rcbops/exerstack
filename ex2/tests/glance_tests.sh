#!/bin/bash

function real_error_output() {
    curl http://www.google.com --output /dev/null
    blarg
}

function some_glance_thing() {
    sleep .8
}