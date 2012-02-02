#!/bin/bash

function successful_test() {
    echo "booger booger"
    sleep .5
}


function unsuccessful_test() {
    echo "some error message or something on stdout"
    echo "some error message or something on stderr" >&2

    sleep .5
    blah blah foo error
}

function long_running_test() {
    sleep 3
}

function d5_only_test() {
    sleep .5
}

function d_final_only_test() {
    sleep .5
}

function diablo_only_test() {
    sleep .5
}

function essex_only_test() {
    sleep .5
}
