# Testing Environment (for Zookeeper)


Autoscale ubuntu instances with a second network interface and EBS volume.  Three (and only 3) instances should be running, one per Availability-Zone.  This can be expaned to run more instances per AZ in groups of 3.

### Repo

Resource | Description
-------- | ------------
bind_eni.sh | Locates an existing network interface or creates one if one doesn't already exist matching our criteria.
bind_ebs.sh | Locates an existing volume or creates one if one doesn't already exist matching our criteria. Sets up disk utilization CloudWatch monitors and alerts.
ubind_ebs.sh | /ete/init.d script to detach EBS volumes on shutdown.
zook-asg-template.json | CFN template that creates an ASG and runs the above bash scripts from UserData.
zook-iam-template.json | CFN template that creates a KMS encryption key and IAM instance profile.
zook-vpc-template.json | CFN template that creates the infrastructure and VPC.
test-asg-template.json | (Experimental) ASG template that creates network interfaces and volume resources via the CFN template.

Note: Launch the VPC and IAM stacks first, followed by the ASG stack last.

### Tests

- [x] **Shutdown an instance** ASG should launch and replace the terminated instance in the same availability-zone. The new instance should attach the ENI and EBS volume previously attached to the terminated instance.

- [x] **Perform a rolling update**  Update the CloudFormation stack with a new AMI. Each instance should be replaced, a single instance at a time, leaving two running instances at all times throughout the process. Like the previous test, each new instance should be deployed into the same availability-zone as the instance being replaced. The new instance should attach the ENI and EBS volume previously attached to the terminated instance.

### Considerations

- [ ] Specifiy how many instances must signal success for an update to succeed. The creation policy snippet below should succeed if a success signal is received from 2 of the 3 instances. Two instances are required to bring up the service. This needs to be tested.

```
"CreationPolicy" : {
   "AutoScalingCreationPolicy" : {
   "MinSuccessfulInstancesPercent" : 66
 }
}
```

- [ ] Clean up unused CloudWatch disk alarms.

### References

* http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/mon-scripts.html
* http://docs.aws.amazon.com/kms/latest/developerguide/services-ebs.html
* http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ebs-io-characteristics.html
* http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/monitoring-volume-status.html

