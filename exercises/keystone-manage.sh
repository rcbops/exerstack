#!/bin/bash
# seems like a lot of this is changing in essex so these are
# probably only going to be relevant for <diablo

function setup() {
  KS_TEST_TENANT=${KS_TEST_TENANT:-"exerTenant"}
  KS_TEST_USER=${KS_TEST_USER:-"exerUser"}
  KS_TEST_ROLE=${KS_TEST_ROLE:-"exerRole"}
  KS_TEST_TOKEN=${KS_TEST_TOKEN:-"exerToken"}
  KS_TEST_PASS=${KS_TEST_PASS:-"exerPass"}
  KS_TEST_SERVICE=${KS_TEST_SERVICE:-"exerService"}
  KS_TEST_REGION=${KS_TEST_REGION:-"exerRegion"}
  MYSQL_PASS=${MYSQL_PASS:-'secrete'}
}


function 010_add_tenant() {
  # add it
  keystone-manage tenant add $KS_TEST_TENANT

  # is it really there?
  if ! keystone-manage tenant list|grep $KS_TEST_TENANT; then
    echo "can't see $KS_TEST_TENANT in the tenant list output"
    exit 1
  fi
}


function 020_add_user() {
  # add it
  keystone-manage user add $KS_TEST_USER $KS_TEST_PASS $KS_TEST_TENANT

  # is it really there?
  if ! keystone-manage user list|grep $KS_TEST_USER; then
    echo "can't see $KS_TEST_USER in the user list output"
    exit 1
  fi
}


function 030_add_token() {
  # add it
  keystone-manage token add $KS_TEST_TOKEN $KS_TEST_USER $KS_TEST_TENANT "2015-02-05T00:00"

  # is it really there?
  if ! keystone-manage token list|grep $KS_TEST_TOKEN; then
    echo "can't see $KS_TEST_TOKEN in the token list output"
    exit 1
  fi
}


function 040_add_role() {
  # add it
  keystone-manage role add $KS_TEST_ROLE

  # is it really there?
  if ! keystone-manage role list|grep $KS_TEST_ROLE; then
    echo "can't see $KS_TEST_ROLE in the role list output"
    exit 1
  fi
}


function 045_grant_role() {
  # add it
  keystone-manage role grant $KS_TEST_ROLE $KS_TEST_USER $KS_TEST_TENANT

  # is it really there?
  if ! keystone-manage role list $KS_TEST_TENANT|grep $KS_TEST_ROLE; then
    echo "$KS_TEST_USER has not been granted $KS_TEST_ROLE"
    return 1
  fi
}


function 050_add_ec2_credentials() {
  # add it
  keystone-manage credentials add $KS_TEST_USER EC2 $KS_TEST_USER $KS_TEST_PASS $KS_TEST_TENANT

  # verify
  if ! keystone-manage credentials list|grep $KS_TEST_USER; then
    echo "can't verify EC2 credentials have been created for $KS_TEST_USER"
    return 1
  fi
}


function 060_add_service() {
  # add it
  keystone-manage service add $KS_TEST_SERVICE test

  # is it really there?
  if ! keystone-manage service list|grep $KS_TEST_SERVICE; then
    echo "can't see $KS_TEST_SERVICE in the role list output"
    exit 1
  fi
}


function 070_add_endpointTemplate() {
  # syntax endpointTemplates add 'region' 'service' 'publicURL' 'adminURL' 'internalURL' 'enabled' 'global'
  keystone-manage endpointTemplates add $KS_TEST_REGION $KS_TEST_SERVICE \
        'http://public.example.com/' 'http://admin.example.com/' \
        'http://internal.example.com/' 1 1
  if ! keystone-manage endpointTemplates list|grep $KS_TEST_SERVICE; then
    echo "can't see $KS_TEST_SERVIE in the endpointTemplates list output"
    return 1
  fi
}


function 080_disable_user() {
  keystone-manage user disable $KS_TEST_USER
  if [ $(keystone-manage user list|grep $KS_TEST_USER|cut -f 3) -ne 0 ]; then
    echo "$KS_TEST_USER has not been disabled"
    return 1
  fi
}


function 081_disable_tenant() {
  keystone-manage tenant disable $KS_TEST_TENANT
  if [ $(keystone-manage tenant list|grep $KS_TEST_TENANT|cut -f 3) -ne 0 ]; then
    echo "$KS_TEST_TENANT has not been disabled"
    return 1
  fi
}


function cleanup() {
  # so, yeah, we can't use keystone-manage to delete the cruft we
  # created. direct db manipulation ftw

  USER_ID=$(keystone-manage user list | grep $KS_TEST_USER|cut -f1)
  TENANT_ID=$(keystone-manage tenant list | grep $KS_TEST_TENANT| cut -f1)
  ROLE_ID=$(keystone-manage role list | grep $KS_TEST_ROLE | cut -f1)
  mysql -uroot -p$MYSQL_PASS -e "DELETE from keystone.user_roles WHERE user_id='$USER_ID'"
  mysql -uroot -p$MYSQL_PASS -e "DELETE from keystone.users WHERE name='$KS_TEST_USER'"
  mysql -uroot -p$MYSQL_PASS -e "DELETE from keystone.tenants WHERE name='$KS_TEST_TENANT'"
  mysql -uroot -p$MYSQL_PASS -e "DELETE from keystone.credentials WHERE user_id='$USER_ID'"
  mysql -uroot -p$MYSQL_PASS -e "DELETE from keystone.roles WHERE name='$KS_TEST_ROLE'"
  mysql -uroot -p$MYSQL_PASS -e "DELETE from keystone.services WHERE name='$KS_TEST_SERVICE'"
  mysql -uroot -p$MYSQL_PASS -e "DELETE from keystone.endpoint_templates WHERE region='$KS_TEST_REGION'"

  # amazing - we can actually delete the token with km
  if keystone-manage token list|grep $KS_TEST_TOKEN; then
    keystone-manage token delete $KS_TEST_TOKEN
  fi
}
