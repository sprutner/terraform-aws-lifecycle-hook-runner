import boto3
import time
import json
import os
import requests
import time

 #The lambda_handler Python function gets called when you run your AWS Lambda function.
def lambda_handler(event, context):

    ssmClient = boto3.client('ssm')
    s3Client = boto3.client('s3')
    snsClient = boto3.client('sns')
    autoscalingClient = boto3.client('autoscaling')
    CONSUL_URL = os.environ['CONSUL_URL']
    SNS_ARN = os.environ['SNS_ARN']
    ENVIRONMENT = os.environ['ENVIRONMENT']
    COMMANDSTRING = os.environ['COMMANDS']
    COMMANDS = COMMANDSTRING.split(",")
    NAME = os.environ['NAME']
    drainQueueUrl = CONSUL_URL + "/v1/kv/asg/" + NAME + "/queue?raw"


    # Create Queue if not present
    queueResponse = requests.get(drainQueueUrl)
    if queueResponse.status_code == 404:
        newQueuePayload = {"Node": [], "Errors": 0}
        newQueuePut = requests.put(drainQueueUrl, data=json.dumps(newQueuePayload))

    # Desconstruct the message from the SNS object
    message = json.loads(event['Records'][0]['Sns']['Message'])
    print message

    # Pull out what we need for the lifecycle hook
    InstanceId = message['EC2InstanceId']
    LifecycleActionToken = message['LifecycleActionToken']
    LifecycleHookName = message['LifecycleHookName']
    AutoScalingGroupName = message['AutoScalingGroupName']

    # Check Consul to see if another node is Draining
    queueResponse = requests.get(drainQueueUrl)
    queue = queueResponse.json()['Node']
    queueErrors = queueResponse.json()['Errors']

    # Join the queue
    queue.append(InstanceId)
    payload = {"Node": queue, "Errors": queueErrors}
    drainPut = requests.put(drainQueueUrl, data=json.dumps(payload))

    # Check queue to see if it's our turn
    while queue[0] != InstanceId:
      print 'Node: ' + queue[0] + ' is draining, waiting 15s'
      time.sleep(15)
      queueResponse = requests.get(drainQueueUrl)
      queue = queueResponse.json()['Node']

    # Free to run the SSM commands.
    if queue[0] == InstanceId:
      print 'Node: ' + queue[0] + ' is at index 0, draining'

    # Send SSM Command to instance
    ssmCommand = ssmClient.send_command(
        InstanceIds = [
            InstanceId
        ],
        DocumentName = 'AWS-RunShellScript',
        TimeoutSeconds = 240,
        Comment = 'Run Shutdown Actions',
        Parameters = {
            'commands': COMMANDS
        }
    )
    #poll SSM until EC2 Run Command completes
    status = 'Pending'
    while status == 'Pending' or status == 'InProgress':
        time.sleep(3)
        status = (ssmClient.list_commands(CommandId=ssmCommand['Command']['CommandId']))['Commands'][0]['Status']

    if(status != 'Success'):
        print "test failed with status " + status
        # Remove self from drain queue
        queueResponse = requests.get(drainQueueUrl)
        queue = queueResponse.json()['Node']
        queue.pop(0)
        queueErrors = 1 + queueResponse.json()['Errors']
        payload = {"Node": queue, "Errors": queueErrors}
        drainPut = requests.put(drainQueueUrl, data=json.dumps(payload))
        print "Removed self from queue"
        snsResponse = snsClient.publish(
            TargetArn=SNS_ARN,
            Message='%s Roll-over error count is %s.' %(ENVIRONMENT, queueErrors)
        )
        return

    response = autoscalingClient.complete_lifecycle_action(
        LifecycleHookName=LifecycleHookName,
        AutoScalingGroupName=AutoScalingGroupName,
        LifecycleActionToken=LifecycleActionToken,
        LifecycleActionResult='CONTINUE',
        InstanceId=InstanceId
    )

    print "Completed."

    # Remove self from drain queue
    queueResponse = requests.get(drainQueueUrl)
    queue = queueResponse.json()['Node']
    queueErrors = queueResponse.json()['Errors']
    queue.pop(0)
    payload = {"Node": queue, "Errors": queueErrors}
    drainPut = requests.put(drainQueueUrl, data=json.dumps(payload))
