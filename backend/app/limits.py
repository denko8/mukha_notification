"""Single-worker safety limits. Not a substitute for a distributed edge limiter."""
import asyncio
import re
import time
from collections import OrderedDict

from starlette.responses import JSONResponse


class RequestLimits:
    def __init__(self, app, max_body=131072, auth_per_minute=20,
                 requests_per_minute=300, max_clients=10000):
        self.app = app
        self.max_body = max_body
        self.auth_limit = auth_per_minute
        self.general_limit = requests_per_minute
        self.max_clients = max_clients
        self.clients = OrderedDict()

    async def __call__(self, scope, receive, send):
        if scope['type'] != 'http':
            return await self.app(scope, receive, send)
        # Uses the socket peer. Production Caddy forwards requests from one
        # address: limits are global for that deployment, intentionally fail-safe.
        # Never trust arbitrary X-Forwarded-For supplied by a public client.
        peer = (scope.get('client') or ('unknown', 0))[0]
        auth = scope['path'].startswith('/auth/') or scope['path'].endswith('/invites') or scope['path'] == '/families/join'
        key = (peer, 'auth' if auth else 'general')
        minute = int(time.monotonic() // 60)
        # Expire old windows, bounding memory even under IP churn.
        while self.clients and next(iter(self.clients.values()))[0] != minute:
            self.clients.popitem(last=False)
        window, count = self.clients.get(key, (minute, 0))
        if key not in self.clients and len(self.clients) >= self.max_clients:
            return await JSONResponse({'detail': 'Server busy'}, 429, headers={'Retry-After': '60'})(scope, receive, send)
        count += 1
        self.clients[key] = (minute, count)
        limit = self.auth_limit if auth else self.general_limit
        if count > limit:
            return await JSONResponse({'detail': 'Too many requests'}, 429, headers={'Retry-After': '60'})(scope, receive, send)
        upload = scope['method'] == 'PUT' and re.fullmatch(
            r'/notes/[0-9a-fA-F-]{36}/attachments/[0-9a-fA-F-]{36}', scope['path'])
        body_limit = 5 * 1024 * 1024 if upload else self.max_body
        chunks = []
        size = 0
        # Buffer only up to a strict bound before the endpoint parses JSON.
        # Enforces actual streamed size, including requests without Content-Length.
        try:
            async with asyncio.timeout(15):
                while True:
                    message = await receive()
                    if message['type'] == 'http.disconnect':
                        return
                    body = message.get('body', b'')
                    size += len(body)
                    if size > body_limit:
                        return await JSONResponse({'detail': 'Request body too large'}, 413)(scope, receive, send)
                    chunks.append(body)
                    if not message.get('more_body', False):
                        break
        except TimeoutError:
            return await JSONResponse({'detail': 'Request body timeout'}, 408)(scope, receive, send)
        delivered = False

        async def replay():
            nonlocal delivered
            if not delivered:
                delivered = True
                return {'type': 'http.request', 'body': b''.join(chunks), 'more_body': False}
            return await receive()

        await self.app(scope, replay, send)
