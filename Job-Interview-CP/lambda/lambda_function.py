import json
import boto3
import os
import requests

s3_client = boto3.client('s3')


def lambda_handler(event, context):
    # body = event['body']
    body = json.loads(event['body']) if isinstance(event['body'], str) else event['body']
    commits_url = body['pull_request']['commits_url']
    repo_name = body['repository']['name']

    response = requests.get(commits_url)
    commits = response.json()

    print(f'commits within the pr : {json.dumps(commits)}')

    changed_files = set()

    for commit in commits:
        for file in commit['files']:
            changed_files.add(file['filename'])

    log_entry = {
        'repository': repo_name,
        'files_changed': changed_files
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
