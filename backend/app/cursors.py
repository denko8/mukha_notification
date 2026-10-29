import base64
import hashlib
import hmac
import json
import time


def scope_hash(scopes):
    return hashlib.sha256(json.dumps(sorted(scopes)).encode()).hexdigest()


def encode(secret, user_id, position, scopes):
    data = json.dumps([user_id, position, scope_hash(scopes), int(time.time()) + 30 * 86400],
                      separators=(',', ':')).encode()
    payload = base64.urlsafe_b64encode(data).decode().rstrip('=')
    signature = hmac.new(secret.encode(), payload.encode(), hashlib.sha256).hexdigest()
    return payload + '.' + signature


def decode(secret, token, user_id, scopes):
    try:
        if len(token) > 2048:
            raise ValueError()
        payload, signature = token.split('.')
        expected = hmac.new(secret.encode(), payload.encode(), hashlib.sha256).hexdigest()
        if not hmac.compare_digest(signature, expected):
            raise ValueError()
        owner, position, fingerprint, expires = json.loads(base64.urlsafe_b64decode(payload + '=' * (-len(payload) % 4)))
        if owner != user_id or not isinstance(position, int) or position < 0:
            raise ValueError()
        if expires <= time.time() or fingerprint != scope_hash(scopes):
            raise LookupError('scope_or_expiry')
        return position
    except LookupError:
        raise
    except Exception as error:
        raise ValueError('invalid_cursor') from error
