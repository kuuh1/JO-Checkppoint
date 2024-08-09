import json
import boto3
import os

s3_client = boto3.client('s3')

def lambda_handler(event, context):
    body = json.loads(event['body'])
    repo_name = body['repository']['full_name']

    # files_changed = [file['filename'] for file in body['commits'][0]['modified']]
    files_changed = []
    for commit in body['commits']:
        for file in commit['modified']:
            files_changed.append(file)

    unique_files_changed = set(files_changed)

    log_entry = {
        'repository': repo_name,
        'files_changed': unique_files_changed
    }

    print(json.dumps(log_entry))

    s3_client.put_object(
        Bucket=os.environ['LOG_BUCKET'],
        Key=f"{repo_name}_log.json",
        Body=json.dumps(log_entry)
    )

    return {
        'statusCode': 200,
        'body': json.dumps('Log entry created')
    }