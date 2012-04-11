#!/usr/bin/env bash

function setup() {



    # Export required ENV vars
    export OS_AUTH_USER=$NOVA_USERNAME
    export OS_AUTH_KEY=$NOVA_PASSWORD
    export OS_AUTH_TENANT=$NOVA_PROJECT_ID
    export OS_AUTH_URL=$NOVA_URL
    export OS_AUTH_STRATEGY=keystone

    export TEST_TENANT="exerTenant"
    export TEST_USER="exerUser"
    export TEST_ROLE="exerRole"
    export TEST_SERVICE="exerService"
    export TEST_SERVICE_TYPE="exerType"
    export TEST_USER_PASS="exerPass"
    export TEST_ENDPOINT=""
    export TEST_INT_URL="http://int.example.com:9999"
    export TEST_PUB_URL="http://ext.example.com:9999"
    export TEST_ADM_URL="http://adm.example.com:9999"
    
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

function 035_tenant_disable() {
    # bug 976947
    # disable tenant (currently command succeeds but the disable actually fails as of keystone folsom-1) 
    keystone tenant-update --enabled false $TEST_TENANT_ID
    if  keystone tenant-get $TEST_TENANT_ID| grep -i enabled | grep -i true ; then
        echo "tenant disable command succeeded but tenant was not disabled"
        return 1
    fi
}
    
function 040_tenant_update() {
     # update tenant details
    keystone tenant-update --description "monkeybutler"  $TEST_TENANT_ID
    if ! keystone tenant-get $TEST_TENANT_ID | grep monkeybutler ; then
        echo "could not update tenant description"
        return 1
    fi

    keystone tenant-update --name 'exerTenant2' $TEST_TENANT_ID
    if ! keystone tenant-get $TEST_TENANT_ID | grep 'exerTenant2' ; then
        echo "could not update tenant name"
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

    keystone user-update --name 'exerUser2' $TEST_USER_ID
    if ! keystone user-get $TEST_USER_ID | grep exerUser2 ; then
        echo "could not update user name"
        return 1
    fi
}

function 160_user_disable() {
    keystone user-update --enabled false $TEST_USER_ID
    if keystone user-get $TEST_USER_ID | grep -i enabled | grep -i true; then
        echo "could not disable user"
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


#### services ####

function 300_service_create() {
    if ! TEST_SERVICE_ID=$(keystone service-create --name $TEST_SERVICE --type $TEST_SERVICE_TYPE | grep id | awk '{print $4}') ; then
        echo "could not create service"
        return 1
    fi
}

function 310_service_list() {
    if ! keystone service-list | grep $TEST_SERVICE_ID ; then
        echo "could not list services"
        return 1
    fi
}

function 320_service_details() {
    if ! keystone service-get $TEST_SERVICE_ID ; then
        echo "could not get service details"
        return 1
    fi
}


#### endpoints ####

function 400_endpoint_create() {
    if ! TEST_ENDPOINT_ID=$(keystone endpoint-create --service_id $TEST_SERVICE_ID --publicurl $TEST_PUB_URL --adminurl $TEST_ADM_URL --internalurl $TEST_INT_URL | egrep ' id ' | awk '{print $4}'); then
        echo "could not create endpoint"
        return 1
    fi
}


function 410_endpoint_list() {
    if ! keystone endpoint-list | grep $TEST_ENDPOINT_ID ; then
        echo "could not list endpoints"
        echo "TEST_ENDPOINT_ID is \'$TEST_ENDPOINT_ID\'"
        return 1
    fi
}

function 420_endpoint_details() {
# seems to always fail regardless of flags. Will file bug
    if ! keystone endpoint-get --service $TEST_SERVICE_ID ; then
        echo "could not get endpoint details"
        return 1
    fi
}







function teardown() {
echo
    # Remove our test stuff
    # workaround for deleting a user (bug 959294)
    mysql -uroot -pnova  -e 'update keystone.user set extra="{}" where name like "%exer%";'
    # for some reason it doesn't always work first time...
    keystone user-delete $TEST_USER_ID
    keystone user-delete $TEST_USER_ID
    keystone user-delete $TEST_USER_ID

    keystone tenant-delete $TEST_TENANT_ID
    keystone role-delete $TEST_ROLE_ID
    keystone service-delete $TEST_SERVICE_ID
    keystone endpoint-delete $TEST_ENDPOINT_ID
    
}
