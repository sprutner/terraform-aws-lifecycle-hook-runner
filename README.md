# terraform-aws-lifecycle-hook-runner

## Overview

This module will add lifecycle hooks to run commands on autoscaling group instances before they terminate, so that you can easily run pre-termination tasks or shutdown scripts before the instance is removed.

Queuing is used to ensure commands are run one at a time in the case you are doing a rolling deployment of infrastructure, such as is used in the create_before_destroy lifecycle.

It uses SSM, Lifecycle hooks, SNS topics,
The module will create the IAM policies, SNS topics, Lambda function, and lifecycle hooks. It will create a list in Consul for queuing at /kv/asg/${name} so ensure this is accessible.

## Requirements

- A Consul KV store that lambda can write to from your AWS environment
- The AWS SSM agent is installed on your instances
- An Autoscaling Group name to attach this to
- A subnet with a NAT Gateway (for Lambda to reach out to SSM)
- A security group that will allow Lambda to make HTTP requests to consul

## Usage

Call this module like below.
Take note of the 'commands' format. The commands will be run in the order you place them, one by one.

`name` Required value to prevent overlap/duplicates if called multiple times

`environment` Required value you can set to whatever you wish

`subnet_ids` An array of subnets to put the Lambda function in.

`security_group_ids` Security group for Lambda to communicate with consul

`commands` A comma separated string with commands to run on instance termination

`consul_url` The base consul URL like shown below. It will append the path to this.

`autoscaling_group_name` Name of your autoscaling group

### TF

```hcl
module "lifecycle_hook" {
  source                      = "github.com/sprutner/tf_aws_lifecycle_hook_runner"
  name                        = "test"
  environment                 = "${var.environment}"
  subnet_ids                  = "${module.vpc.app_subnets}"
  security_group_ids          = "${aws_security_group.docker.id}"
  commands                    = <<EOF
echo 'test',
echo 'hola'
EOF
  consul_url                  = "http://consul.companyxyz${var.environment}.dev"
  autoscaling_group_name      = "${module.nomad_client.asg_name}"
}
```
