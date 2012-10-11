exerstack  
=========

Description
--
exerstack is a bash tool to test each of the python command line clients from the core OpenStack projects (glance, nova, swift, keystone, horizon)


Basic usage
--
`exercise.sh [release] [tests]`

Examples:

`exercise.sh`

will run all tests that exist in the exercises directory against the default release (as defined in the top of the exerstack.sh script), unless skipped in testmap.conf

`exercise.sh essex-final`

will run all tests that exist in the exercises directory, unless skipped in testmap.conf

`exercise.sh essex-final glance.sh`

will run all glance tests that are valid for the essex-final release, unless skipped in testmap.conf



Files
--
`exercise.sh` - main script  
`exercises/*` - each script in here defines a set of tests for a particular client  
`exercises/include/*` - supporting files for some of the tests  
`testmap.conf` - defines the tests you would like to skip, and the conditions under which you want to skip them  
`openrc` - defines global environment variables  
`localrc` - (optional) defines your own overrides for environment variables in here - gets called by openrc

configuring testmap.conf
--

testmap.conf can skip entire test sets (an entire *.sh file in exercises/), or individual tests within a test set.  Since OpenStack releases are alphabetical, it uses lexical comparison to see if a release is 'older than' or 'newer than' the one specified in the skip condition (ie diablo-final is 'older than' essex-e2 because d comes before e in the alphabet)

The structure of a skip condition is as follows:

`[test_set:optional_test_name]="condition (<=>) release : message`

Examples:

`[keystone-manage]="< essex-e4 : keystone-legacy was replaced with keystone-ksl in essex >= e4"`  

skips the entire keystone-manage.sh test set for any release that is 'newer than' essex-e4.

`[glance:011_glance_delete-TOKEN]="< essex-e3 : glance token auth works on essex < e3"`

skips the test '011\_glance\_delete-TOKEN' within the glance.sh test set, for any release that is 'newer than' essex-e3
