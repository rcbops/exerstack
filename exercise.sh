#!/bin/bash

source ./openrc

SKIPPED=0
FAILED=0
PASSED=0

SKIP_MSG=""

# FIXME: make command-line option override ENV
PACKAGESET=${1:-${PACKAGESET:-"diablo-final"}}
shift
TESTSCRIPTS=$@
BASEDIR=$(dirname $(readlink -f ${0}))
ONESHOT=${ONESHOT-0}

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

TMPDIR=$(mktemp -d)
trap "rm -rf ${TMPDIR}" EXIT

COLSIZE=40


function skip_if_distro() {
    #$* distro names
    local distro_name
    local running_release=""

    if ! running_release=$( lsb_release -a ); then
	# need to figure out what distro we are on
	distro_name=unknown
    else
	running_release=$(echo "${running_release}" | grep -i "Codename" | awk '{ print $2 }')
    fi

    while [ ${#@} -gt 0 ]; do
	if [[ ${running_release} == $1 ]]; then
	    SKIP_MSG="Skipping: unsupported distro"
	    SKIP_TEST=1
	    return 0
	fi
	shift
    done

    return 1
}

function skip_if_not_distro() {
    if skip_if_distro $*; then
	SKIP_TEST=0
	return 1
    else
	SKIP_TEST=1
	SKIP_MSG="Skipping: unsupported distro"
	return 0
    fi
}

function should_run() {
    # $1 - file (nova_api)
    # $2 - test (list)

    local file=${1}
    local test=${2}
    local result=0
    local expr=""
    local condition=""
    local conditions=()
    local conditions_string=""

    [ -z "${PACKAGESET-}" ] && return 0
    [ -z "${test_config[${file}]-}" ] || conditions_string=${test_config[${file}]-}
    [ -z "${test_config[${file-}:${test-}]-}" ] || conditions_string=${test_config[${file-}:${test-}]-}
    [ -z "${conditions_string-}" ] && return 0

    # side effects rule
    SKIP_MSG=${conditions_string##*:}
    conditions_string=${conditions_string%%:*}

    local oldifs="${IFS}"
    IFS=,
    conditions=( $conditions_string )
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

[[ -z $(which bc) ]] && echo "Test timings will not be calculated as bc is not available"

declare -A test_config
source testmap.conf

set | grep ' ()' | cut -d' ' -f1 |sort > ${TMPDIR}/fn_pre.txt

echo "Running test suite for packageset \"${PACKAGESET}\""

if [ "${TESTSCRIPTS}" == "" ]; then
    TESTSCRIPTS="*.sh"
fi

TESTS=""
pushd ${BASEDIR}/exercises > /dev/null 2>&1
for d in ${TESTSCRIPTS}; do
    for f in $(ls ${d}); do
	TESTS+="${BASEDIR}/exercises/${f} "
    done
done
popd > /dev/null 2>&1

for d in ${TESTS}; do
    testname=$(basename ${d} .sh)

    echo -e "\n=== ${testname} ===\n"

    if ( ! /bin/bash -n ${d} > /dev/null 2>&1 ); then
	colourise red -n "Compile error in ${d}"
	echo
	FAILED=$(( ${FAILED} + 1 ))
	continue
    fi

    source ${d}

    # don't use grep -q as it causes grep to quit after the first match and
    # send SIGPIPE to the source. The source is bash (set builtin) which
    # doesn't handle the signal properly.
    if $(set | grep 'setup ()' &>/dev/null); then
	# not in a subshell, so globals can be modified
	FAIL_REASON="Setup function failed"
	echo "======== TEST SETUP FOR ${d} =========" > ${TMPDIR}/test.txt

	set -E
	trap "status=\$?; trap - ERR; if [ ! -z \${FUNCNAME-} ]; then return \$status; fi" ERR
	status=0
	eval "set -x; setup; set +x" >> ${TMPDIR}/test.txt 2>&1
	trap - ERR
	set +E

	if [ $status -ne 0 ]; then
	    colourise red -n "FAIL: ${FAIL_REASON}"
	    echo
	    FAILED=$(( ${FAILED} + 1 ))
	    cat ${TMPDIR}/test.txt >> ${TMPDIR}/notice.txt
	    continue
	fi
    fi

    # find all the functions defined in the newly sourced file.
    set | grep ' ()' | cut -d' ' -f1 | sort > ${TMPDIR}/fn_post.txt

    fnlist=$(comm -23 ${TMPDIR}/fn_post.txt ${TMPDIR}/fn_pre.txt)

    # run each test
    for test in ${fnlist}; do

    # Skip functions that don't start with a number.
    # This includes setup and teardown and allows for utility functions
    # within exercise scripts.
	[[ ! ${test} =~ ^[0-9] ]] && continue

    printf " %-${COLSIZE}s" "${test}"
	SKIP_MSG=""
	SKIP_TEST=0

	if should_run ${testname} ${test}; then
	    resultcolour="green"  # for you, darren :p
	    start=$(date +%s.%N)

	    echo "=== TEST: ${testname}/${test} ===" > ${TMPDIR}/test.txt

#	    eval "(set -e; set -x; ${test}; set +x; set +e); status=\$?" >> ${TMPDIR}/test.txt 2>&1

	    set -E
	    trap "status=\$?; trap - ERR; if [ ! -z \${FUNCNAME-} ]; then return \$status; fi" ERR
	    status=0
	    eval "set -x; ${test}; set +x" >> ${TMPDIR}/test.txt 2>&1
	    trap - ERR
	    set +E

	    end=$(date +%s.%N)

	    elapsed=$(echo "${end}-${start}*100/100" | bc -q 2> /dev/null)
	    result="OK"

	    if [ "${DEBUG-}" != "" ]; then
		cat ${TMPDIR}/test.txt >> ${TMPDIR}/debug.txt
	    fi

	    if [ ${status} -ne 0 ] && [ $SKIP_TEST -eq 0 ]; then
		resultcolour="red"
		result="FAIL (Error Code: $status)"
		cat ${TMPDIR}/test.txt >> ${TMPDIR}/notice.txt
		echo >> ${TMPDIR}/notice.txt

		FAILED=$(( ${FAILED} + 1 ))
        if [ $ONESHOT -eq 1 ]; then
            echo; echo "ONESHOT ACTIVATED!"; echo
            if [ -e ${TMPDIR}/notice.txt ]; then
                colourise red ERROR TEST OUTPUT
                cat ${TMPDIR}/notice.txt
            fi
            exit 1
        fi
		colourise ${resultcolour} " ${result}"
	    elif [ $SKIP_TEST -eq 0 ]; then
		result=$(printf "%0.3fs" "${elapsed}")
		PASSED=$(( ${PASSED} + 1 ))
		colourise ${resultcolour} " ${result}"
	    fi
	else
	    SKIP_TEST=1
	fi

	if [ $SKIP_TEST -eq 1 ]; then
	    colourise boldyellow -n " SKIP"
	    if [ ! -z "${SKIP_MSG-}" ]; then
		echo ": ${SKIP_MSG}"
	    else
		echo
	    fi

	    SKIPPED=$(( ${SKIPPED} + 1 ))
	fi
    done

    if $(set | grep -q 'teardown ()'); then
	teardown > /dev/null 2>&1
    fi

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
[ -e ${TMPDIR}/debug.txt ] && cat ${TMPDIR}/debug.txt

echo

if [ "$FAILED" -ne "0" ]; then
    if [ -e ${TMPDIR}/notice.txt ]; then
	colourise red ERROR TEST OUTPUT
	cat ${TMPDIR}/notice.txt
    fi
    exit 1
fi

