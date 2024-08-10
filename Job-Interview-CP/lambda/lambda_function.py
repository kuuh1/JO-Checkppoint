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

    changed_files = set()

    for commit in commits:
        commit_url = commit['url']
        commit_response = requests.get(commit_url)
        commit_json = commit_response.json()

        for file in commit_json['files']:
            changed_files.add(file['filename'])

    log_entry = {
        'repository': repo_name,
        'files_changed': list(changed_files)
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
