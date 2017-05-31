#!/bin/bash

# Arguments from the CFN template
export REGION="$1"
export KMS_KEY_ARN="$2"
export TOPIC_ARN="$3"
export SERVICE="$4"

# For testing
#export REGION="us-east-1"
#export KMS_KEY_ARN="arn:aws:kms:us-east-1:762160981991:key/4f33efbf-fc46-4807-a021-69289f47fd84"
#export TOPIC_ARN="arn:aws:sns:us-east-1:762160981991:zook-test-env-zookeeper"
#export SERVICE="kafka-zookeepers"

export INST=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
export MAC=$(curl -s http://169.254.169.254/latest/meta-data/mac/)
export SUB=$(curl -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/$MAC/subnet-id/)
export AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)

LOGFILE=/tmp/userdata_ebs.log
exec > $LOGFILE 2>&1

function log_it() {
    printf "%s\n" "$*" 
}

function get_vol() {
    local VOL_ID=$(aws ec2 describe-volumes \
       --region $REGION \
       --filters Name=status,Values=available \
                 Name=availability-zone,Values=$AZ \
                 Name=tag:Service,Values=$SERVICE \
       --query 'Volumes[0].VolumeId' | tr -d '"')

    echo "$VOL_ID"
}

function create_vol() {
    local VOL_ID=$(aws ec2 create-volume \
       --availability-zone $AZ \
       --volume-type gp2 \
       --size 20 \
       --encrypt  \
       --kms-key-id $KMS_KEY_ARN \
       --region $REGION \
       --query 'VolumeId' | tr -d '"')

    aws ec2 wait volume-available --volume-ids $VOL_ID --region $REGION
    echo "$VOL_ID"
}

function attach_vol() {
    # Requires one arg, an EBS volume_id
    aws ec2 attach-volume \
       --region $REGION \
       --instance-id $INST \
       --device /dev/sdf \
       --volume-id $1

    aws ec2 wait volume-in-use --volume-ids $1 --region $REGION
}

function create_alarm() {
    # Requires two args, $FILE_SYS and $MOUNT_PATH 
    aws cloudwatch put-metric-alarm \
       --region $REGION \
       --alarm-name "zookeeper-disk-$INST" \
       --metric-name DiskSpaceUtilization \
       --namespace System/Linux \
       --period 300 \
       --evaluation-periods 2 \
       --threshold 80 \
       --comparison-operator GreaterThanThreshold \
       --dimensions "Name"="MountPath","Value"=$2 \
                    "Name"="InstanceId","Value"="$INST" \
                    "Name"="Filesystem","Value"=$1 \
      --statistic Sum \
      --alarm-actions $TOPIC_ARN 
}

function tag_it() {
    # Requires one arg, an AWS resource_id
    aws ec2 create-tags --resources $1 --tags Key=Service,Value=$SERVICE --region $REGION
}

# Do the work...
#
NEW_VOLUME="false"
VOL_ID=$(get_vol)

if [[ $VOL_ID != vol-* ]]; then
    log_it "No available volume found. Creating a new EBS volume..."
    VOL_ID=$(create_vol)
    tag_it "$VOL_ID"
    NEW_VOLUME="true"
fi

log_it "EBS Volume: $VOL_ID in Availability-Zone: $AZ"
log_it "Attaching $VOL_ID to instance $INST"

attach_vol $VOL_ID

FILE_SYS="/dev/xvdf"
MOUNT_PATH="/evident/kafka-zookeeper/data"

# Wait for it to show up in lsblk
lsblk $FILE_SYS &> /dev/null
while [ $? != "0" ]; do
    sleep 2
    lsblk $FILE_SYS &> /dev/null
done

# If this is a new volume, format it
if [ $NEW_VOLUME == "true" ]; then
    mkfs -t ext4 $FILE_SYS &> /dev/null
fi

# Create a mount point for this volume
mkdir -p $MOUNT_PATH
chown -R ubuntu:ubuntu /evident

# Add an entry to fstab for this volume
echo "$FILE_SYS    $MOUNT_PATH         ext4    noauto,discard  0 0" >> /etc/fstab

# Mount the volume
mount $MOUNT_PATH

# ** These cmds will have to be baked into the AMI if no Public IP is assigned to the instance **
# Install AWS disk monitorig utils
apt-get -y update &> /dev/null
apt-get -y install unzip &> /dev/null
apt-get -y install libwww-perl libdatetime-perl &> /dev/null

cd ~ubuntu
curl http://aws-cloudwatch.s3.amazonaws.com/downloads/CloudWatchMonitoringScripts-1.2.1.zip -O >& /dev/null

unzip CloudWatchMonitoringScripts-1.2.1.zip
rm -f CloudWatchMonitoringScripts-1.2.1.zip
# **

# Update crontab
echo "*/5 * * * * ~/aws-scripts-mon/mon-put-instance-data.pl \
    --disk-space-util --disk-space-used --disk-space-avail --disk-path=$MOUNT_PATH"  > /tmp/crontab.txt
sudo -u ubuntu bash -c 'crontab /tmp/crontab.txt'

# Create CW disk alarm
log_it "Creating disk utilization alarm for $FILE_SYS mounted on $MOUNT_PATH"

create_alarm $FILE_SYS $MOUNT_PATH
