# Lifecycle hook to run commands before terminating instance

# Lambda Policy for autoscaling
resource "aws_iam_role" "lifecycle_trust" {
  name                = "${var.environment}-${var.name}-tf-iam-role-lifecycle-trust"
  assume_role_policy  = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    },
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "autoscaling.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

# Lambda Policy for autoscaling

resource "aws_iam_policy" "lifecycle" {
    name   = "tf_lambda_vpc_policy_${var.name}"
    path   = "/"
    policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "autoscaling:CompleteLifecycleAction"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Resource": "${aws_sns_topic.lifecycle.arn}",
            "Action": "sns:Publish"
        },
        {
            "Effect": "Allow",
            "Resource": "arn:aws:logs:*:*:*",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "logs:DescribeLogStreams"
            ]
        },
        {
            "Effect": "Allow",
            "Resource": "*",
            "Action": [
                "ssm:SendCommand",
                "ssm:*",
                "ssm:CancelCommand",
                "ssm:ListCommands",
                "ssm:ListCommandInvocations",
                "ssm:ListDocuments",
                "ssm:DescribeDocument*",
                "ssm:GetDocument",
                "ssm:DescribeInstance*",
                "ec2:CreateNetworkInterface",
                "ec2:DescribeNetworkInterfaces",
                "ec2:DeleteNetworkInterface"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_policy_attachment" "lifecycle" {
  name       = "tf-iam-role-attachment-${var.name}-lifecycle"
  roles      = ["${aws_iam_role.lifecycle_trust.name}"]
  policy_arn = "${aws_iam_policy.lifecycle.arn}"
}

# SNS for operator notification on Errors
resource "aws_sns_topic" "operator" {
  name = "${var.name}-operator"
}

# Lambda function
resource "aws_lambda_function" "lifecycle" {
    filename          = "${path.module}/lifecycle.py.zip"
    function_name     = "${var.environment}-${var.name}-lifecycle"
    runtime           = "python2.7"
    timeout           = "240"
    role              = "${aws_iam_role.lifecycle_trust.arn}"
    handler           = "lifecycle.lambda_handler"
    source_code_hash  = "${base64sha256(file("${path.module}/lifecycle.py.zip"))}"
    vpc_config        = {
      subnet_ids = ["${var.subnet_ids}"]
      security_group_ids = ["${var.security_group_ids}"]
      }

    environment {
      variables = {
        CONSUL_URL  = "${var.consul_url}"
        ENVIRONMENT = "${var.environment}"
        SNS_ARN     = "${aws_sns_topic.operator.arn}"
        COMMANDS    = "${var.commands}"
        NAME        = "${var.name}"
      }
    }
  }

# Permission for SNS to trigger function
resource "aws_lambda_permission" "allow_lifecycle" {
  statement_id   = 45
  action         = "lambda:InvokeFunction"
  function_name  = "${aws_lambda_function.lifecycle.function_name}"
  principal      = "sns.amazonaws.com"
  source_arn     = "${aws_sns_topic.lifecycle.arn}"
}

# SNS Topic for the lifecycle hook
resource "aws_sns_topic" "lifecycle" {
  name = "${var.name}-lifecycle"
}

# Subscribe Lambda to the SNS Topic
resource "aws_sns_topic_subscription" "lifecycle" {
  topic_arn = "${aws_sns_topic.lifecycle.arn}"
  protocol  = "lambda"
  endpoint  = "${aws_lambda_function.lifecycle.arn}"
}

resource "aws_autoscaling_lifecycle_hook" "lifecycle" {
  depends_on              = ["aws_iam_policy_attachment.lifecycle"]
  name                    = "${var.environment}-${var.name}-lifecycle"
  autoscaling_group_name  = "${var.autoscaling_group_name}"
  default_result          = "ABANDON"
  heartbeat_timeout       = 300
  lifecycle_transition    = "autoscaling:EC2_INSTANCE_TERMINATING"
  notification_target_arn = "${aws_sns_topic.lifecycle.arn}"
  role_arn                = "${aws_iam_role.lifecycle_trust.arn}"
}
