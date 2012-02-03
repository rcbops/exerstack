#!/bin/bash

SKIPPED=0
FAILED=0
PASSED=0

PACKAGESET=${PACKAGESET-"diablo-final"}
BASEDIR=$(dirname $(readlink -f ${0}))

set -u

###
# set up some globals
###

black='\033[0m'
boldblack='\033[1;0m'
red='\033[31m'
boldred='\033[1;31m'
green='\033[32m'
boldgreen='\033[1;32m'
yellow='\033[33m'
boldyellow='\033[1;33m'
blue='\033[34m'
boldblue='\033[1;34m'
magenta='\033[35m'
boldmagenta='\033[1;35m'
cyan='\033[36m'
boldcyan='\033[1;36m'
white='\033[37m'
boldwhite='\033[1;37m'

tmpdir=$(mktemp -d)
trap "rm -rf ${tmpdir}" EXIT


COLSIZE=40

function should_run() {
    # $1 - file (nova_api)
    # $2 - test (list)

    local result=0
    local file=${1}
    local test=${2}
    local expr=""
    local condition=""
    local conditions=()

    if [ "${PACKAGESET-}" == "" ] || [ "${test_config[${file-}:${test-}]-}" == "" ]; then
	return 0
    fi

    local oldifs="${IFS}"
    IFS=,
    conditions=( ${test_config[${file}:${test}]} )
    IFS="${oldifs}"

    for condition in "${conditions[@]}"; do
	expr="if [[ ${PACKAGESET} ${condition} ]]; then echo \"yes\"; else echo \"no\"; fi"
	if [ $(eval ${expr}) == "no" ]; then
	    result=$(( result + 1 ))
	fi
    done

    if [ ${result} -gt 0 ]; then
	return 1
    fi

    return 0
}

function colourise() {
    # $1: colour
    # $2+ message

    local colour=${1}
    shift
    local message="$@"

    if [ -t 1 ] && [ "${TERM}" != "" ]; then
	eval "printf \"\$${colour}\""
    fi

    echo ${message}

    if [ -t 1 ] && [ "${TERM}" != "" ]; then
	tput sgr0
    fi
}


declare -A test_config
source testmap.conf


set | grep ' ()' | cut -d' ' -f1 |sort > ${tmpdir}/fn_pre.txt

echo "Running test suite for packageset \"${PACKAGESET}\""

for d in ${BASEDIR}/tests/*.sh; do
    testname=$(basename ${d} .sh)

    source ${d}
    set | grep ' ()' | cut -d' ' -f1 | sort > ${tmpdir}/fn_post.txt

    fnlist=$(comm -23 ${tmpdir}/fn_post.txt ${tmpdir}/fn_pre.txt)
    echo -e "\n=== ${testname} ===\n"

    for test in ${fnlist}; do
    	printf " %-${COLSIZE}s" "${test}"
	if (should_run ${testname} ${test}); then
	    resultcolour="green"  # for you, darren :p
	    start=$(date +%s.%N)

	    echo "=== TEST: ${testname}/${test} ===" > ${tmpdir}/test.txt

	    eval "(set -e; ${test}; set +e); status=\$?" >> ${tmpdir}/test.txt 2>&1

	    end=$(date +%s.%N)

	    elapsed=$(echo "${end}-${start}*100/100" | bc -q 2> /dev/null)
	    result="OK"
	    if [ ${status} -ne 0 ]; then
		resultcolour="red"
		result="FAIL"
		cat ${tmpdir}/test.txt >> ${tmpdir}/notice.txt
		echo >> ${tmpdir}/notice.txt

		FAILED=$(( ${FAILED} + 1 ))
	    else
		result=$(printf "%0.3fs" "${elapsed}")
		PASSED=$(( ${PASSED} + 1 ))
	    fi

	    colourise ${resultcolour} " ${result}"
	else
	    colourise boldyellow " SKIP"
	    SKIPPED=$(( ${SKIPPED} + 1 ))
	fi
    done

    # undefine the tests
    for test in ${fnlist}; do
	unset -f ${test}
    done
done

echo
echo "RESULTS:"

echo -n "Passed:  "
colourise green ${PASSED}
echo -n "Failed:  "
colourise red ${FAILED}
echo -n "Skipped: "
colourise boldyellow ${SKIPPED}

echo
if [ "$FAILED" -ne "0" ]; then
    colourise red ERROR TEST OUTPUT
    cat ${tmpdir}/notice.txt
    exit 1
fi

