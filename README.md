# Testing Environment (for Zookeeper)

---

Autoscale ubuntu instances with a second network interface and EBS volume.  Three (and only 3) instances should be running, one per Availability-Zone.

---

* bind_ebs.sh - finds/creates a volume and sets up disk utilization CloudWatch monitors
* bind_eni.sh - finds/creates a second network interface and assigns it an IPv4 IP address
* test-asg-template.json - (Experimental) ASG template that creates resources via CFN
* zook-env-template.json - CFN template that creates, the VPC, ASG and launches the bash scripts from UserData
* zook-iam-template.json - CFN template that creates the KMS encryption key and IAM instance profile

