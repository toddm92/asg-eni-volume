#!/bin/bash

# Arguments from the CFN template
export REGION="$1"
export SERVICE="$2"
export ALARM_NAME_PREFIX="zookeeper-disk"

# For testing
#export REGION="us-east-1"
#export SERVICE="kafka-zookeepers"

LOGFILE=/tmp/userdata_cleanup.log
exec > $LOGFILE 2>&1

function log_it() {
    printf "%s\n" "$*" 
}

function find_instances() {
    local INST_LIST=$(aws ec2 describe-instances \
       --region $REGION \
       --filters Name=instance-state-name,Values=shutting-down,terminated \
                 Name=tag:Service,Values=$SERVICE \
       --query 'Reservations[].Instances[].InstanceId' | tr -d '[]",')

    echo "$INST_LIST"
}


DEAD_LIST=$(find_instances)

if [ -z $DEAD_LIST ]; then
    log_it "Clean up alarms: No matching instances found"
    exit 0
fi

# Delete unused (leftover) disk alarms
#
for i in $DEAD_LIST; do
    alarm_name="${ALARM_NAME_PREFIX}-$i"
    aws cloudwatch delete-alarms --alarm-names $alarm_name --region $REGION &> /dev/null
    log_it "Clean up alarms: Deleted alarm $alarm_name"
done
