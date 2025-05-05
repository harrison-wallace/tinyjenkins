import json
import boto3 # type: ignore
import os

def lambda_handler(event, context):
    route53 = boto3.client('route53')
    ec2 = boto3.client('ec2')
    zone_id = os.environ['ZONE_ID']
    record_name = os.environ['RECORD_NAME']
    
    # Parse SNS message
    message = json.loads(event['Records'][0]['Sns']['Message'])
    event_name = message['Event']
    
    if event_name in ['autoscaling:EC2_INSTANCE_LAUNCH', 'autoscaling:EC2_INSTANCE_TERMINATE']:
        # Get current instance in ASG
        response = ec2.describe_instances(
            Filters=[
                {'Name': 'tag:Name', 'Values': ['Jenkins-Spot']},
                {'Name': 'instance-state-name', 'Values': ['running']}
            ]
        )
        
        if len(response['Reservations']) > 0 and len(response['Reservations'][0]['Instances']) > 0:
            instance = response['Reservations'][0]['Instances'][0]
            public_ip = instance.get('PublicIpAddress', None)
            
            if public_ip:
                # Update Route 53 record
                change_batch = {
                    'Changes': [{
                        'Action': 'UPSERT',
                        'ResourceRecordSet': {
                            'Name': record_name,
                            'Type': 'A',
                            'TTL': 300,
                            'ResourceRecords': [{'Value': public_ip}]
                        }
                    }]
                }
                
                route53.change_resource_record_sets(
                    HostedZoneId=zone_id,
                    ChangeBatch=change_batch
                )
                return {
                    'statusCode': 200,
                    'body': json.dumps(f'Updated Route 53 record for {record_name} to {public_ip}')
                }
            else:
                return {
                    'statusCode': 400,
                    'body': json.dumps('No public IP found for running instance')
                }
        else:
            return {
                'statusCode': 400,
                'body': json.dumps('No running instances found in ASG')
            }
    
    return {
        'statusCode': 200,
        'body': json.dumps('No action taken')
    }