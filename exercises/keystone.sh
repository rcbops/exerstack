#!/usr/bin/env bash

function setup() {

#    TOKEN=`curl -s -d  "{\"auth\":{\"passwordCredentials\": {\"username\": \"$NOVA_USERNAME\", \"password\": \"$NOVA_PASSWORD\"}}}" -H "Content-type: application/json" http://$HOST_IP:5000/v2.0/tokens | python -c "import sys; import json; tok = json.loads(sys.stdin.read()); print tok['access']['token']['id'];"`


    # Export required ENV vars
    export OS_AUTH_USER=$NOVA_USERNAME
    export OS_AUTH_KEY=$NOVA_PASSWORD
    export OS_AUTH_TENANT=$NOVA_PROJECT_ID
    export OS_AUTH_URL=$NOVA_URL
    export OS_AUTH_STRATEGY=keystone

#    export OS_AUTH_TENANT_ID=`curl -s  -H "X-Auth-Token:999888777666" http://$HOST_IP:35357/v2.0/tenants|python -mjson.tool|grep -B1 $OS_AUTH_TENANT|head -1|cut -d'"' -f4`
    export TEST_TENANT="exerTenant"
    export TEST_USER="exerUser"
    export TEST_ROLE="exerRole"
    export TEST_SERVICE="exerService"
    export TEST_USER_PASS="exerPass"
    export TEST_ENDPOINT=""
}

#    catalog             List service catalog, possibly filtered by service.
#    ec2-credentials-create
#                        Create EC2-compatibile credentials for user per tenant
#    ec2-credentials-delete
#                        Delete EC2-compatibile credentials
#    ec2-credentials-get
#                        Display EC2-compatibile credentials
#    ec2-credentials-list
#                        List EC2-compatibile credentials for a user
#    endpoint-create     Create a new endpoint associated with a service
#    endpoint-delete     Delete a service endpoint
#    endpoint-get        Find endpoint filtered by a specific attribute or
#                        service type
#    endpoint-list       List configured service endpoints
#    role-create         Create new role
#    role-delete         Delete role
#    role-get            Display role details
#    role-list           List all roles, or only those granted to a user.
#    service-create      Add service to Service Catalog
#    service-delete      Delete service from Service Catalog
#    service-get         Display service from Service Catalog
#    service-list        List all services in Service Catalog
#    tenant-create       Create new tenant
#    tenant-delete       Delete tenant
#    tenant-get          Display tenant details
#    tenant-list         List all tenants
#    tenant-update       Update tenant name, description, enabled status
#    token-get           Display the current user token
#    user-create         Create new user
#    user-delete         Delete user
#    user-get            Display user details.
#    user-list           List users
#    user-password-update
#                        Update user password
#    user-role-add       Add role to user
#    user-role-remove    Remove role from user
#    user-update         Update user's name, email, and enabled status
#    discover            Discover Keystone servers and show authentication
#                        protocols and
#    help                Display help about this program or one of its
#                        subcommands.


#### tenants ####
function 010_tenant_create() {

    # create a new tenant
    if ! TEST_TENANT_ID=$(keystone tenant-create --name $TEST_TENANT | grep id|awk '{print $4}'); then
        echo "Unable to create tenant $TEST_TENANT"
        return 1
    fi 

    # make sure we can't create the same tenant again
    if keystone tenant-create --name $TEST_TENANT ; then
        echo "we were allowed to create a tenant with the same name"
        return 1
    fi
}

function 020_tenant_list() {
    # list tenants and check our new one is there
    if ! keystone tenant-list|grep $TEST_TENANT_ID; then
        echo "Unable to find tenant \'$TEST_TENANT\' in tenant-list"
        return 1
    fi
}


function 030_tenant_details() {
    # get tenant details
    if ! keystone tenant-get $TEST_TENANT_ID; then
        echo "Unable to get details for tenant \'$OS_AUTH_TENANT\'"
        return 1
    fi
}
    # disable tenant (currently command succeeds but the disable actually fails as of keystone folsom-1) 
#    if keystone tenant-update --enabled false $KEYSTONE_TENANT_ID ; then
#        if keystone tenant-get $TEST_TENANT_ID| grep -i enabled |grep -i true ; then
#            echo "tenant disable command succeeded but tenant was not disabled"
#            return 1
#        fi
#    else
#        echo "tenant disable command failed"
#        return 1
#    fi
    
function 040_tenant_update() {
     # update tenant details
    keystone tenant-update --description "monkeybutler"  $TEST_TENANT_ID
    if ! keystone tenant-get $TEST_TENANT_ID | grep monkeybutler ; then
        echo "could not update metadata properly"
        return 1
    fi
}

#### users ####
function 110_user_create() {
    
    # add a user
    if ! TEST_USER_ID=$(keystone user-create --name $TEST_USER --tenant_id $TEST_TENANT_ID | grep id | awk '{print $4}') ; then
        echo "could not create user $TEST_USER"
        return 1
    fi

    # make sure we can't create the same user again
    if keystone user-create --name $TEST_USER --tenant_id $TEST_TENANT_ID ; then
        echo "we were allowed to create a user with the same name"
        return 1
    fi
}    
    
function 120_user_list() {
    # list users and check our new one is there
    if ! keystone user-list | grep $TEST_USER_ID ; then
        echo "Unable to find user \'$TEST_USER\'"
        return 1
    fi
}

function 130_user_details() {
    # get user details
    if ! keystone user-get $TEST_USER_ID ; then
        echo "unable to get details for user \'$TEST_USER\'"
        return 1
    fi
}
    
function 140_user_password_update() {
    if ! keystone user-password-update --pass $TEST_USER_PASS $TEST_USER_ID; then
        echo "unable to update user password"
        return 1
    fi
}

function 150_user_update() {
    keystone user-update --email 'blah@blah.com' $TEST_USER_ID
    if ! keystone user-get $TEST_USER_ID | grep blah; then
        echo "could not update user details"
        return 1
    fi
}
        
    


#### roles ####

function 210_role_create() {
    if ! TEST_ROLE_ID=$(keystone role-create --name $TEST_ROLE | grep id | awk '{print $4}'); then
        echo "unable to create new role"
        return 1
    fi
}

function 220_role_list() {
    if ! keystone role-list | grep $TEST_ROLE_ID ; then
        echo "unable to find role"
        return 1
    fi
}

function 230_role_details() {
    if ! keystone role-get $TEST_ROLE_ID ; then
        echo "unable to get details for role"
        return 1
    fi
}

function 240_role_user_add() {
    keystone user-role-add --user $TEST_USER_ID  --role $TEST_ROLE_ID --tenant_id $TEST_TENANT_ID;
    if ! keystone role-list --user $TEST_USER_ID --tenant_id $TEST_TENANT_ID| grep $TEST_ROLE_ID; then
        echo "unable to assign role to user"
        return 1
    fi
}

function 250_role_user_remove() {
    keystone user-role-remove --user $TEST_USER_ID  --role $TEST_ROLE_ID --tenant_id $TEST_TENANT_ID
    if keystone role-list --user $TEST_USER_ID --tenant_id $TEST_TENANT_ID| grep $TEST_ROLE_ID; then
        echo "unable to remove role from user"
        return 1
    fi
}


#function 030_manage_ec2_creds() {
#echo
#}
#
#function 040_manage_endpoints() {
#echo
#}
#
#function 050_manage_roles() {
#echo
#}
#
#function 060_manage_services() {
#echo
#}







function teardown() {
echo
    # Remove our test stuff
    # workaround for deleting a user
    mysql -uroot -pnova  -e 'update keystone.user set extra="{}" where name like "%exer%";'
    # for some reason it doesn't always work first time...
    keystone user-delete $TEST_USER_ID
    keystone user-delete $TEST_USER_ID
    keystone user-delete $TEST_USER_ID
    keystone tenant-delete $TEST_TENANT_ID
    keystone role-delete $TEST_ROLE_ID
    
}

