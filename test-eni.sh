#!/bin/bash -ex
#
export TAG='todd-test'
export REGION='us-east-1'

export MAC=`curl -s http://169.254.169.254/latest/meta-data/mac/`
export SUB=`curl -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/$MAC/subnet-id/`
export INST=`curl -s http://169.254.169.254/latest/meta-data/instance-id`

export ENI=`aws ec2 describe-network-interfaces \
      --region $REGION \
      --filters Name=status,Values=available \
                Name=subnet-id,Values=$SUB \
                Name=tag:Name,Values=$TAG \
      --query "NetworkInterfaces[0].NetworkInterfaceId" | sed -e s/\"//g`

if [ $ENI != null ]; then
  aws ec2 attach-network-interface \
      --region $REGION \
      --instance-id $INST \
      --device-index 2 \
      --network-interface-id $ENI
fi
