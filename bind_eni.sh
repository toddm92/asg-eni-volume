#!/bin/bash

# Arguments from the CFN template
#export REGION="$1"
#export SG="$2"
#export SERVICE="$3"

# For testing
export REGION="us-east-1"
export SG="sg-29330757"
export SERVICE="kafka-zookeepers"

export INST=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
export MAC=$(curl -s http://169.254.169.254/latest/meta-data/mac/)
export SUB=$(curl -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/$MAC/subnet-id/)
export AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)

LOGFILE=/tmp/userdata_eni.log
exec > $LOGFILE 2>&1

function log_it() {
    printf "%s\n" "$*" 
}

function get_eni() {
    local ENI_ID=$(aws ec2 describe-network-interfaces \
       --region $REGION \
       --filters Name=status,Values=available \
                 Name=subnet-id,Values=$SUB \
                 Name=tag:Service,Values=$SERVICE \
       --query 'NetworkInterfaces[0].NetworkInterfaceId' | tr -d '"')

    echo "$ENI_ID"
}

function create_eni() {
    local ENI_ID=$(aws ec2 create-network-interface \
       --subnet-id $SUB \
       --groups $SG \
       --region $REGION \
       --query 'NetworkInterface.NetworkInterfaceId' | tr -d '"')

    aws ec2 wait network-interface-available --network-interface-ids $ENI_ID --region $REGION
    echo "$ENI_ID"
}

function attach_eni() {
    local ATTACH_ID=$(aws ec2 attach-network-interface \
       --network-interface-id $1 \
       --instance-id $INST \
       --device-index 1 \
       --region $REGION \
       --query 'AttachmentId' | tr -d '"')

    echo "$ATTACH_ID"
}

function get_eni_status() {
    local ATTACH_STATUS=$(aws ec2 describe-network-interfaces \
       --network-interface-ids $1 \
       --region $REGION \
       --query 'NetworkInterfaces[0].Status' | tr -d '"')

    echo "$ATTACH_STATUS"
}

function get_gateway() {
    local GATEWAY=$(aws ec2 describe-subnets \
       --subnet-ids $SUB \
       --region $REGION \
       --query 'Subnets[0].Tags[?Key==`Gateway`].Value' | tr -d '\n[]" ')

    echo "$GATEWAY"
}

function tag_it() {
    aws ec2 create-tags --resources $1 --tags Key=Service,Value=$SERVICE --region $REGION
}

# Do the work...
#
ENI_ID=$(get_eni)

if [[ $ENI_ID != eni-* ]]; then
    log_it "No available ENI found. Creating a new network interface..."
    ENI_ID=$(create_eni)
    tag_it "$ENI_ID"
fi

log_it "Network interface: $ENI_ID in Subnet: $SUB"
log_it "Attaching $ENI_ID to instance $INST"

ATTACH_ID=$(attach_eni $ENI_ID)
ENI_STATUS=$(get_eni_status $ENI_ID)

until [ $ENI_STATUS == "in-use" ]; do 
    sleep 2
    ENI_STATUS=$(get_eni_status $ENI_ID)
done

# Second Ethernet interface
ETH_INT="eth1"

log_it "Bringing up $ETH_INT..."
ip link set $ETH_INT up
sleep 5
ifconfig $ETH_INT

while [ $? != "0" ]; do
    sleep 2
    ifconfig $ETH_INT
done

# Grab an IP address
dhclient $ETH_INT

# Create a new route-table
echo "200 out" >> /etc/iproute2/rt_tables

# Setup routing
STATIC_IP=$(ifconfig $ETH_INT | grep 'inet addr:' | cut -d: -f2 | awk '{ print $1}')
GATEWAY=$(get_gateway)

ip rule add from $STATIC_IP table out
ip route add default via $GATEWAY table out

log_it "IP Address: $STATIC_IP Gateway: $GATEWAY"
