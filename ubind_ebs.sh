#!/bin/sh
### BEGIN INIT INFO
# Provides:          ubind_ebs
# Required-Start:
# Required-Stop:
# Should-Stop:       halt
# Default-Start:
# Default-Stop:      0
# Short-Description: Detach AWS Volume.
# Description:       Detach an AWS EBS Volume.
### END INIT INFO

### SETUP
# place in /etc/init.d
# run chmod +x <script_name>
# run update-rc.d <script_name> defaults
###

function get_vol() {
    local VOL_ID=$(aws ec2 describe-volumes \
       --region $1 \
       --filters Name=attachment.instance-id,Values=$2 \
                 Name=tag:Service,Values=$3 \
       --query 'Volumes[0].VolumeId' | tr -d '"')

    echo "$VOL_ID"
}

detach_vol () {
    aws ec2 detach-volume \
       --region $1 \
       --instance-id $2 \
       --volume-id $3

    aws ec2 wait volume-available --volume-ids $3 --region $1
}


do_stop () {

    local SERVICE="kafka-zookeepers"
    local MOUNT_PATH="/evident/kafka-zookeeper/data"
    local REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/.$//')
    local INST=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

    umount $MOUNT_PATH 2> /dev/null

    VOL_ID=$(get_vol $REGION $INST $SERVICE)

    if echo "$VOL_ID" | grep -q "vol-"; then
        detach_vol $REGION $INST $VOL_ID
    fi
}

case "$1" in
  start|status)
	# No-op
	;;
  restart|reload|force-reload)
	echo "Error: argument '$1' not supported" >&2
	exit 3
	;;
  stop)
	do_stop
	;;
  *)
	echo "Usage: $0 start|stop" >&2
	exit 3
	;;
esac

:
