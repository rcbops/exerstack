#!/usr/bin/env bash

function setup() {
export NETWORK_NAME='exerstack_test_network'
export NETWORK_NAME2='a_new_network_name'
export SUBNET_NAME='exerstack_test_subnet'
export SUBNET_NAME2='a_new_subnet_name'
export SUBNET_CIDR='192.168.57.0/24'
export PORT_NAME='exerstack_test_port'
export PORT_NAME2='a_new_port_name'
export Q_SECGROUP_NAME='exerstack_test_security_group'
}

#  agent-delete                   Delete a given agent.
####  agent-list                     List agents.
####  agent-show                     Show information of a given agent.
#  agent-update                   Update a given agent.
####  dhcp-agent-list-hosting-net    List DHCP agents hosting a network.
####  dhcp-agent-network-add         Add a network to a DHCP agent.
####  dhcp-agent-network-remove      Remove a network from a DHCP agent.
####  ext-list                       List all exts.
####  ext-show                       Show information of a given resource
#  floatingip-associate           Create a mapping between a floating ip and a fixed ip.
#  floatingip-create              Create a floating ip for a given tenant.
#  floatingip-delete              Delete a given floating ip.
#  floatingip-disassociate        Remove a mapping from a floating ip to a fixed ip.
#  floatingip-list                List floating ips that belong to a given tenant.
#  floatingip-show                Show information of a given floating ip.
#  l3-agent-list-hosting-router   List L3 agents hosting a router.
#  l3-agent-router-add            Add a router to a L3 agent.
#  l3-agent-router-remove         Remove a router from a L3 agent.
####  net-create                     Create a network for a given tenant.
####  net-delete                     Delete a given network.
#  net-external-list              List external networks that belong to a given tenant
#  net-gateway-connect            Add an internal network interface to a router.
#  net-gateway-create             Create a network gateway.
#  net-gateway-delete             Delete a given network gateway.
#  net-gateway-disconnect         Remove a network from a network gateway.
#  net-gateway-list               List network gateways for a given tenant.
#  net-gateway-show               Show information of a given network gateway.
#  net-gateway-update             Update the name for a network gateway.
####  net-list                       List networks that belong to a given tenant.
####  net-list-on-dhcp-agent         List the networks on a DHCP agent.
####  net-show                       Show information of a given network.
####  net-update                     Update network's information.
####  port-create                    Create a port for a given tenant.
####  port-delete                    Delete a given port.
####  port-list                      List ports that belong to a given tenant.
####  port-show                      Show information of a given port.
####  port-update                    Update port's information.
####  quota-delete                   Delete defined quotas of a given tenant.
####  quota-list                     List defined quotas of all tenants.
####  quota-show                     Show quotas of a given tenant
####  quota-update                   Define tenant's quotas not to use defaults.
#  router-create                  Create a router for a given tenant.
#  router-delete                  Delete a given router.
#  router-gateway-clear           Remove an external network gateway from a router.
#  router-gateway-set             Set the external network gateway for a router.
#  router-interface-add           Add an internal network interface to a router.
#  router-interface-delete        Remove an internal network interface from a router.
#  router-list                    List routers that belong to a given tenant.
#  router-list-on-l3-agent        List the routers on a L3 agent.
#  router-port-list               List ports that belong to a given tenant, with specified router
#  router-show                    Show information of a given router.
#  router-update                  Update router's information.
####  security-group-create          Create a security group.
####  security-group-delete          Delete a given security group.
####  security-group-list            List security groups that belong to a given tenant.
####  security-group-rule-create     Create a security group rule.
####  security-group-rule-delete     Delete a given security group rule.
####  security-group-rule-list       List security group rules that belong to a given tenant.
####  security-group-rule-show       Show information of a given security group rule.
####  security-group-show            Show information of a given security group.
####  subnet-create                  Create a subnet for a given tenant.
####  subnet-delete                  Delete a given subnet.
####  subnet-list                    List networks that belong to a given tenant.
####  subnet-show                    Show information of a given subnet.
####  subnet-update                  Update subnet's information.

function 010_agent-list() {
    if ! neutron agent-list; then
        echo "could not list neutron agents"
        return 1
    fi
}

function 020_agent-show() {
    AGENT_ID=$(neutron agent-list -f csv | tail -n 1 | cut -d '"' -f2)
    if ! neutron agent-show ${AGENT_ID}; then
        echo "could not get detailed information about agent ${AGENT_ID}"
        return 1
    fi

}

function 025_ext-list() {
    if ! neutron ext-list; then
        echo "could not list neutron extensions"
        return 1
    fi
}

function 028_ext-show() {
    if ! neutron ext-show 'agent'; then
        echo "could not get detailed information about agent extension "
        return 1
    fi
}

function 030_net-list() {
    if ! neutron net-list; then
        echo "could not list networks"
        return 1
    fi
}

function 040_net-list-on-dhcp-agent() {
    if DHCP_AGENT_ID=$(neutron agent-list -f csv | grep -i dhcp | tail -1 | cut -d'"' -f2); then
        if ! neutron net-list-on-dhcp-agent ${DHCP_AGENT_ID}; then
            echo "could not list networks on dhcp agent ${DHCP_AGENT_ID}"
            return 1
        fi
    else
        SKIP_TEST=1
        SKIP_MSG="no dhcp agents to list networks for"
        return 1
    fi
}

function 050_net-create() {
    if ! neutron net-create  ${NETWORK_NAME}; then
        echo "could not create network"
        return 1
    fi

    if ! neutron net-list | grep ${NETWORK_NAME}; then
        echo "subnet was added, but does not show in subnet list output"
        return 1
    fi
}

function 060_net-show() {
    NETWORK_ID=$(neutron net-show ${NETWORK_NAME} -f shell |grep '^id=' | cut -d'"' -f2)
    if ! neutron net-show  ${NETWORK_ID}; then
        echo "could not show network"
        return 1
    fi

}

function 070_net-update() {
    NETWORK_ID=$(neutron net-show ${NETWORK_NAME} -f shell |grep '^id=' | cut -d'"' -f2)
    if ! neutron net-update ${NETWORK_ID} --name ${NETWORK_NAME2}; then
        echo "could not update network name"
        return 1
    fi

    if ! [ "${NETWORK_NAME2}" = "$(neutron net-show -f shell ${NETWORK_ID} | grep '^name=' | cut -d'"' -f2)" ]; then
        echo "network was not updated properly"
        return 1
    fi

    neutron net-update ${NETWORK_ID} --name ${NETWORK_NAME}
}

function 080_dhcp-agent-network-add() {
    if DHCP_AGENT_ID=$(neutron agent-list -f csv |grep -i dhcp | tail -1 | cut -d'"' -f2); then
        NETWORK_ID=$(neutron net-show ${NETWORK_NAME} -f shell |grep '^id=' | cut -d'"' -f2)
        if ! neutron dhcp-agent-network-add ${DHCP_AGENT_ID} ${NETWORK_ID}; then
            echo "could not add network ${NETWORK_ID} to dhcp agent ${DHCP_AGENT_ID}"
            return 1
        fi
        if ! neutron net-list-on-dhcp-agent ${DHCP_AGENT_ID} | grep ${NETWORK_ID}; then
            echo "network was added to dhcp agent, but does not show in it's listing"
            return 1
        fi
        if ! neutron dhcp-agent-list-hosting-net ${NETWORK_ID} | grep ${DHCP_AGENT_ID}; then
            echo "network was added to dhcp agent, but does not show in list of agents hosting this network"
        return 1
        fi

    else
        SKIP_TEST=1
        SKIP_MSG="no dhcp agents to list networks for"
        return 1
    fi
}

function 090_subnet-create() {
    NETWORK_ID=$(neutron net-show ${NETWORK_NAME} -f shell |grep '^id=' | cut -d'"' -f2)

    if ! neutron subnet-create --name ${SUBNET_NAME} ${NETWORK_ID} ${SUBNET_CIDR}; then
        echo "could not create subnet"
        return 1
    fi

    if ! neutron subnet-list | grep ${SUBNET_NAME}; then
        echo "subnet was added, but does not show in subnet list output"
        return 1
    fi
}

function 100_subnet-show() {
    SUBNET_ID=$(neutron subnet-show ${SUBNET_NAME} -f shell | grep '^id=' | cut -d'"' -f2)
    if ! neutron subnet-show  ${SUBNET_ID}; then
        echo "could not show subnet"
        return 1
    fi
}

function 110_subnet-update() {
    SUBNET_ID=$(neutron subnet-show ${SUBNET_NAME} -f shell | grep '^id=' | cut -d'"' -f2)
    if ! neutron subnet-update ${SUBNET_ID} --name ${SUBNET_NAME2}; then
        echo "could not update subnet name"
        return 1
    fi

    if ! [ "${SUBNET_NAME2}" = "$(neutron subnet-show -f shell ${SUBNET_ID} | grep '^name=' | cut -d'"' -f2)" ]; then
        echo "subnet was not updated properly"
        return 1
    fi

    neutron subnet-update ${SUBNET_ID} --name ${SUBNET_NAME}
}

function 120_port-create() {
    NETWORK_ID=$(neutron net-show ${NETWORK_NAME} -f shell |grep '^id=' | cut -d'"' -f2)

    if ! neutron port-create --name ${PORT_NAME} ${NETWORK_ID}; then
        echo "could not create port"
        return 1
    fi

    if ! neutron port-list | grep ${PORT_NAME}; then
        echo "port was added, but does not show in port list output"
        return 1
    fi
}

function 130_port-show() {
    PORT_ID=$(neutron port-show ${PORT_NAME} -f shell | grep '^id=' | cut -d'"' -f2)
    if ! neutron port-show  ${PORT_ID}; then
        echo "could not show port"
        return 1
    fi
}

function 140_port-update() {
    PORT_ID=$(neutron port-show ${PORT_NAME} -f shell | grep '^id=' | cut -d'"' -f2)
    if ! neutron port-update ${PORT_ID} --name ${PORT_NAME2}; then
        echo "could not update port name"
        return 1
    fi

    if ! [ "${PORT_NAME2}" = "$(neutron port-show -f shell ${PORT_ID} | grep '^name=' | cut -d'"' -f2)" ]; then
        echo "port was not updated properly"
        return 1
    fi

    neutron port-update ${PORT_ID} --name ${PORT_NAME}
}

function 150_quota-update() {
    CURRENT_SUBNET_QUOTA=$(neutron quota-show -f shell | grep '^subnet=' | cut -d'"' -f2)
    TARGET_SUBNET_QUOTA=$(( CURRENT_SUBNET_QUOTA +1 ))
    neutron quota-update --subnet ${TARGET_SUBNET_QUOTA}
    NEW_SUBNET_QUOTA=$(neutron quota-show -f shell |  grep '^subnet=' | cut -d'"' -f2)

    if [ ${NEW_SUBNET_QUOTA} != ${TARGET_SUBNET_QUOTA} ]; then
        echo "could not update quotas for tenant"
        return 1
    fi
}

function 160_quota-list() {
    # separate quota for this tenant should now exist after changing a value above
    if ! neutron quota-list ; then
        echo "could not list quotas for tenants"
        return 1
    fi
}

function 170_quota-show() {
    if ! neutron quota-show; then
        echo "could not show quotas for this tenant"
        return 1
    fi
}

function 180_security-group-create() {
    if ! neutron security-group-create $Q_SECGROUP_NAME; then
        echo "could not create security group"
        return 1
    fi
    if ! neutron security-group-list | grep ${Q_SECGROUP_NAME}; then
        echo "security group was created but does not show in list output"
        return 1
    fi
}

function 190_security-group-show() {
    if ! neutron security-group-show ${Q_SECGROUP_NAME}; then
        echo "could not show details of security group ${Q_SECGROUP_NAME}"
        return 1
    fi
}

function 200_security-group-rule-create() {
    if ! neutron security-group-rule-create --protocol icmp ${Q_SECGROUP_NAME}; then
        echo "could not create security group rule"
        return 1
    fi
    if ! neutron security-group-rule-list | grep ${Q_SECGROUP_NAME} | grep icmp; then
        echo "created security group rule but can't see it in list output"
        return 1
    fi
}

function 210_security-group-rule-show() {
    Q_SECGROUP_RULE_ID=$(neutron security-group-rule-list -f csv | grep ${Q_SECGROUP_NAME} | grep icmp | cut -d'"' -f2)
    if ! neutron security-group-rule-show ${Q_SECGROUP_RULE_ID}; then
        echo "could not show security group rule details"
        return 1
    fi
}

function 220_security-group-rule-delete() {
    Q_SECGROUP_RULE_ID=$(neutron security-group-rule-list -f csv | grep ${Q_SECGROUP_NAME} | grep icmp | cut -d'"' -f2)
    if ! neutron security-group-rule-delete ${Q_SECGROUP_RULE_ID}; then
        echo "could not delete security group rule"
        return 1
    fi

    if neutron security-group-rule-show ${Q_SECGROUP_RULE_ID}; then
        echo "security group rule was deleted but still shows in output"
        return 1
    fi
}

function 300_security-group-delete() {
    if ! neutron security-group-delete ${Q_SECGROUP_NAME}; then
        echo "could not delete security group rule"
        return 1
    fi

    if neutron security-group--show ${Q_SECGROUP_NAME}; then
        echo "security group was deleted but still shows in output"
        return 1
    fi
}

function 310_quota-delete() {
    if ! neutron quota-delete; then
        echo "could not delete the quotas for this tenant"
        return 1
    fi
    if neutron quota-list | grep 'subnet'; then
        echo "quota was deleted, but is still showing in in list output"
        return 1
    fi
}

function 320_port-delete() {
    PORT_ID=$(neutron port-show ${PORT_NAME} -f shell | grep '^id=' | cut -d'"' -f2)
    if ! neutron port-delete ${PORT_ID}; then
        echo "could not delete port ${PORT_ID}"
        return 1
    fi
}

function 330_subnet-delete() {
    SUBNET_ID=$(neutron subnet-show ${SUBNET_NAME} -f shell | grep '^id=' | cut -d'"' -f2)
    if ! neutron subnet-delete ${SUBNET_ID}; then
        echo "could not delete subnet"
        return 1
    fi
}

function 340_dhcp-agent-network-remove() {
    if DHCP_AGENT_ID=$(neutron agent-list -f csv |grep -i dhcp | tail -1 | cut -d'"' -f2); then
        NETWORK_ID=$(neutron net-show ${NETWORK_NAME} -f shell |grep '^id=' | cut -d'"' -f2)
        if ! neutron dhcp-agent-network-remove ${DHCP_AGENT_ID} ${NETWORK_ID}; then
            echo "could not remove network from dhcp agent"
        fi
        if neutron dhcp-agent-list-hosting-net ${NETWORK_ID} | grep ${DHCP_AGENT_ID}; then
            echo "network was removed from dhcp agent but still shows in network's listing"
        fi
        if neutron net-list-on-dhcp-agent ${DHCP_AGENT_ID} | grep ${NETWORK_ID}; then
            echo "network was removed from dhcp agent but still shows in agent'slisting"
        fi
    else
        SKIP_TEST=1
        SKIP_MSG="no dhcp agents to remove networks from"
        return 1
    fi
}

function 350_net-delete() {
    NETWORK_ID=$(neutron net-show ${NETWORK_NAME} -f shell |grep '^id=' | cut -d'"' -f2)
    if ! neutron net-delete  ${NETWORK_ID}; then
        echo "could not delete network"
        return 1
    fi

}
