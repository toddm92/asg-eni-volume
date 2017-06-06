#!/bin/bash

export INST=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
export REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed -e 's/.$//')
export MOUNT_PATH="/evident/kafka-zookeeper/data"

function get_vol() {
    local VOL_ID=$(aws ec2 describe-volumes \
       --region $REGION \
       --filters Name=attachment.instance-id,Values=$INST \
       --query 'Volumes[0].VolumeId' | tr -d '"')

    echo "$VOL_ID";
}

function detach_vol() {
    # Requires one arg, an EBS volume_id
    aws ec2 detach-volume \
       --region $REGION \
       --instance-id $INST \
       --volume-id $1
}


# Do the work...
#
df -k | grep $MOUNT_PATH &> /dev/null

if [ $? -eq 0 ]; then
    umount $MOUNT_PATH
fi

VOL_ID=$(get_vol)

if [[ $VOL_ID == vol-* ]]; then
    detach_vol $VOL_ID
fi

