#!/bin/bash
# seems like a lot of this is changing in essex so these are
# probably only going to be relevant for <diablo

function setup() {

KS_TEST_TENANT=${KS_TEST_TENANT:-"exerTenant"}
KS_TEST_USER=${KS_TEST_USER:-"exerUser"}
KS_TEST_ROLE=${KS_TEST_ROLE:-"exerRole"}
KS_TEST_TOKEN=${KS_TEST_TOKEN:-"wibblypibbly"}
KS_TEST_PASS=${KS_TEST_PASS:-"sminkypinky"}

}


function 010_add_tenant() {

# add it
keystone-manage tenant add $KS_TEST_TENANT

# is it really there?
if ! keystone-manage tenant list|grep $KS_TEST_TENANT|cut -f2; then
    echo "can't see $KS_TEST_TENANT in the tenant list output"
    exit 1
fi

}

function 020_add_user() {

# add it
keystone-manage user add $KS_TEST_USER $KS_TEST_PASS

# is it really there?
if ! keystone-manage user list|grep $KS_TEST_USER|cut -f2; then
    echo "can't see $KS_TEST_USER in the user list output"
    exit 1
fi

}

function 030_add_role() {

# add it
keystone-manage role add $KS_TEST_ROLE

# is it really there?
if ! keystone-manage role list|grep $KS_TEST_ROLE|cut -f2; then
    echo "can't see $KS_TEST_ROLE in the role list output"
    exit 1
fi

}


function 030_add_token() {

# add it
keystone-manage token add $KS_TEST_TOKEN $KS_TEST_USER $KS_TEST_TENANT "2015-02-05T00:00"

# is it really there?
if ! keystone-manage token list|grep $KS_TEST_TOKEN|cut -f1; then
    echo "can't see $KS_TEST_TOKEN in the token list output"
    exit 1
fi

}


function cleanup() {

# so, yeah, we can't use keystone-manage to delete the cruft we
# created. direct db manipulation ftw
mysql -uroot -psecrete -e "DELETE from keystone.users where name='$KS_TEST_USER'"
mysql -uroot -psecrete -e "DELETE from keystone.tenants where name='$KS_TEST_TENANT'"
mysql -uroot -psecrete -e "DELETE from keystone.roles where name='$KS_TEST_ROLE'"

keystone-manage token delete $KS_TEST_TOKEN

# make sure we really did clean up
for k in role admin token user; do
    f=$(echo $k|tr '[a-z]' '[A-Z]')
    if keystone-manage $k list|grep $KS_TEST_${f}; then
        echo "oh we didn't get rid of $k"
        exit 1
    fi
done

}
