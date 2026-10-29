from io import BytesIO
from urllib.parse import parse_qs, urlparse
from botocore.stub import Stubber
from botocore.response import StreamingBody
from app.objects import S3Objects


def test_s3_uses_private_objects_and_short_lived_download_grants(monkeypatch):
    monkeypatch.setenv('S3_BUCKET', 'smartnotes-private')
    monkeypatch.setenv('S3_ENDPOINT_URL', 'https://objects.example.test')
    monkeypatch.setenv('S3_ACCESS_KEY_ID', 'test-access-key')
    monkeypatch.setenv('S3_SECRET_ACCESS_KEY', 'test-secret-key')
    objects = S3Objects()
    with Stubber(objects.client) as stub:
        stub.add_response('put_object', {}, {'Bucket': 'smartnotes-private', 'Key': 'opaque-key',
            'Body': b'pdf', 'ContentType': 'application/pdf', 'ContentDisposition': 'attachment'})
        objects.put('opaque-key', b'pdf', 'application/pdf')  # No public-read ACL
        stub.add_response('get_object', {'Body': StreamingBody(BytesIO(b'pdf'), 3)},
                          {'Bucket': 'smartnotes-private', 'Key': 'opaque-key'})
        assert objects.get('opaque-key') == b'pdf'
        stub.add_response('delete_object', {}, {'Bucket': 'smartnotes-private', 'Key': 'opaque-key'})
        objects.delete('opaque-key')
    grant = objects.download_url('opaque-key')
    parsed = urlparse(grant)
    assert parsed.scheme == 'https'
    assert parse_qs(parsed.query)['X-Amz-Expires'] == ['60']
    assert 'test-secret-key' not in grant


def test_inventory_measures_object_metadata_without_getting_originals(monkeypatch):
    monkeypatch.setenv('S3_BUCKET', 'smartnotes-private')
    monkeypatch.setenv('S3_ENDPOINT_URL', 'https://objects.example.test')
    monkeypatch.setenv('S3_ACCESS_KEY_ID', 'test-access-key')
    monkeypatch.setenv('S3_SECRET_ACCESS_KEY', 'test-secret-key')
    objects = S3Objects()
    with Stubber(objects.client) as stub:
        stub.add_response('list_objects_v2', {'Contents': [{'Key': 'attachments/a', 'Size': 123},
            {'Key': 'attachments/b', 'Size': 456}], 'IsTruncated': False},
            {'Bucket': 'smartnotes-private', 'Prefix': 'attachments/', 'MaxKeys': 1000})
        assert objects.inventory() == {'objects': 2, 'bytes': 579, 'list_requests': 1, 'complete': True}
