"""Private S3 objects. No public ACLs; use a dedicated bucket and least-privilege key."""
import os


class S3Objects:
    def __init__(self):
        import boto3
        from botocore.config import Config
        self.bucket = os.environ['S3_BUCKET']
        self.client = boto3.client('s3', endpoint_url=os.environ.get('S3_ENDPOINT_URL') or None,
            region_name=os.environ.get('S3_REGION', 'us-east-1'),
            aws_access_key_id=os.environ['S3_ACCESS_KEY_ID'],
            aws_secret_access_key=os.environ['S3_SECRET_ACCESS_KEY'],
            config=Config(signature_version='s3v4', connect_timeout=5, read_timeout=30,
                          retries={'max_attempts': 2}, s3={'addressing_style': 'path'}))

    def put(self, key, data, mime):
        self.client.put_object(Bucket=self.bucket, Key=key, Body=data,
                               ContentType=mime, ContentDisposition='attachment')

    def get(self, key):
        response = self.client.get_object(Bucket=self.bucket, Key=key)
        with response['Body'] as body:
            data = body.read(5 * 1024 * 1024 + 1)
        if len(data) > 5 * 1024 * 1024:
            raise ValueError('Object exceeds size limit')
        return data

    def delete(self, key):
        self.client.delete_object(Bucket=self.bucket, Key=key)

    def inventory(self):
        # Metadata-only inventory; never downloads object bodies. Bound LIST cost.
        count, size, requests, token = 0, 0, 0, None
        for _ in range(100):
            args = dict(Bucket=self.bucket, Prefix='attachments/', MaxKeys=1000)
            if token: args['ContinuationToken'] = token
            page = self.client.list_objects_v2(**args)
            requests += 1
            for item in page.get('Contents', []):
                count += 1
                size += item['Size']
            if not page.get('IsTruncated'):
                return dict(objects=count, bytes=size, list_requests=requests, complete=True)
            token = page['NextContinuationToken']
        return dict(objects=count, bytes=size, list_requests=requests, complete=False)

    def download_url(self, key):
        return self.client.generate_presigned_url('get_object', Params={
            'Bucket': self.bucket, 'Key': key, 'ResponseContentDisposition': 'attachment'}, ExpiresIn=60)


def configured_objects():
    required = ['S3_BUCKET', 'S3_ACCESS_KEY_ID', 'S3_SECRET_ACCESS_KEY']
    return S3Objects() if all(os.environ.get(k) for k in required) else None
