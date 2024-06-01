# import boto3 and grab list of all workflows on account
import boto3
import botocore

client = boto3.client('omics', region_name='us-east-1')
response = client.list_workflows()
# filter response to names only
names = [item['name'] for item in response['items']]
print(names)
