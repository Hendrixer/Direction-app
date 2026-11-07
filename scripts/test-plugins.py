#!/usr/bin/env python3
"""Exercise the plugin's actual launcher and project-independent MCP/CLI/API contract."""
import base64
import json
import os
from pathlib import Path
import select
import subprocess
import sys
import tempfile
import time

root = Path(__file__).resolve().parents[1]
binary, fixture = (Path(p).resolve() for p in sys.argv[1:3])
checks = []

def check(ok, label):
    assert ok, label
    checks.append(label)

class Session:
    def __init__(self, env):
        launch = json.loads((root / 'plugins/direction/.mcp.json').read_text())['mcpServers']['direction']
        self.proc = subprocess.Popen([launch['command'], *launch['args']], env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.buffer = b''
        self.counter = 0
        self.request('initialize', {'protocolVersion': '2025-11-25', 'capabilities': {}, 'clientInfo': {'name': 'Direction plugin test', 'version': '1'}})
        self.send({'jsonrpc': '2.0', 'method': 'notifications/initialized'})
    def send(self, data):
        self.proc.stdin.write(json.dumps(data).encode() + b'\n'); self.proc.stdin.flush()
    def request(self, method, params):
        self.counter += 1
        self.send({'jsonrpc': '2.0', 'id': self.counter, 'method': method, 'params': params})
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            while b'\n' in self.buffer:
                line, self.buffer = self.buffer.split(b'\n', 1)
                result = json.loads(line)
                if result.get('id') == self.counter:
                    assert 'error' not in result, result
                    return result['result']
            if select.select([self.proc.stdout], [], [], 1)[0]:
                chunk = os.read(self.proc.stdout.fileno(), 65536)
                assert chunk, 'Plugin launcher exited: ' + self.proc.stderr.read().decode()
                self.buffer += chunk
        raise TimeoutError(method)
    def tool(self, name, args=None, error=None):
        result = self.request('tools/call', {'name': name, 'arguments': args or {}})
        value = json.loads(result['content'][0]['text'])
        if error:
            assert result.get('isError') and value['code'] == error, result
        else:
            assert not result.get('isError'), result
        return value, result
    def close(self):
        self.proc.stdin.close()
        try: self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired: self.proc.terminate(); self.proc.wait(timeout=5)
        self.proc.stdout.close(); self.proc.stderr.close()

with tempfile.TemporaryDirectory(prefix='Direction plugin test ') as folder:
    folder = Path(folder)
    spaced = folder / 'CLI with spaces'; spaced.symlink_to(binary)
    env = dict(os.environ, DIRECTION_CLI=str(spaced), DIRECTION_LIBRARY_PATH=str(folder/'library.sqlite'))
    a, b = (str(folder / (name + '.direction')) for name in ('A project', 'B project'))
    session = Session(env)
    try:
        tools = session.request('tools/list', {})['tools']
        check(all(name in [t['name'] for t in tools] for name in ('direction_create_project', 'direction_open_project', 'direction_projects')), 'Plugin boots without a project and advertises project tools')
        for path, name in ((a, 'A project'), (b, 'B project')):
            value, _ = session.tool('direction_create_project', {'path': path, 'name': name})
            check(value['projectPath'] == path and value['project']['name'] == name, 'Create ' + name + ' through MCP')
        session.tool('direction_inspect', error='project_required')
        check(True, 'Unbound calls cannot accidentally use the last opened project')
        session.tool('direction_create_project', {'path': a, 'name': 'Overwrite'}, error='project_exists')
        check(True, 'Existing project cannot be overwritten')
        imported, _ = session.tool('direction_import', {'projectPath': a, 'path': str(fixture), 'append': True})
        check(len(imported['asset']['audio']) == 2, 'Explicitly routed import preserves both embedded audio streams')
        other, _ = session.tool('direction_inspect', {'projectPath': b})
        check(other['project']['editRevision'] == 0 and not other['project']['assets'], 'Mutating A leaves B untouched')
        note, _ = session.tool('direction_add_comment', {'projectPath': a, 'text': 'Keep this beat', 'start': .4, 'end': .9})
        _, context = session.tool('direction_feedback_context', {'projectPath': a, 'commentID': note['id']})
        check(any(c['type'] == 'image' and base64.b64decode(c['data']).startswith(b'\x89PNG') for c in context['content']), 'Plugin returns real inline review frames')
        check(any(c['type'] == 'audio' and base64.b64decode(c['data']).startswith(b'RIFF') for c in context['content']), 'Plugin returns real inline review audio')
        session.tool('direction_edit', {'projectPath': a, 'baseEditRevision': 1, 'idempotencyKey': 'plugin-cut', 'operations': [{'op': 'removeRange', 'range': {'start': 0, 'end': .2}, 'ripple': True}]})
        session.tool('direction_open_project', {'path': b})
        changed, _ = session.tool('direction_inspect', {'projectPath': a})
        check(changed['project']['editRevision'] == 2, 'Opening B does not redirect subsequent explicit A edits')
        value, _ = session.tool('direction_projects')
        check(len(value['projects']) == 2, 'Library registers both projects without duplicates')
    finally: session.close()
    session = Session(env)
    try:
        value, _ = session.tool('direction_projects')
        check(len(value['projects']) == 2, 'Projects persist across plugin restarts')
        feedback, _ = session.tool('direction_feedback', {'projectPath': a})
        check('Keep this beat' in json.dumps(feedback), 'Feedback survives plugin restarts')
    finally: session.close()
    cli = subprocess.run([str(binary), 'call', 'direction_open_project', '--json', json.dumps({'path': a})], env=env, capture_output=True, text=True, timeout=30)
    check(cli.returncode == 0 and json.loads(cli.stdout)['project']['editRevision'] == 2, 'CLI call can open a project without --project')
    request = {'id': 1, 'method': 'direction_inspect', 'params': {'projectPath': b}}
    api = subprocess.run([str(binary), 'api'], input=json.dumps(request)+'\n', env=env, capture_output=True, text=True, timeout=30)
    check(api.returncode == 0 and json.loads(api.stdout)['result']['project']['name'] == 'B project', 'JSON API supports explicit project routing without --project')

report = root / 'build/verification/plugin-report.json'
report.parent.mkdir(parents=True, exist_ok=True)
report.write_text(json.dumps({'passed': len(checks), 'checks': checks}, indent=2)+'\n')
print(f'PASS: {len(checks)} plugin / project lifecycle checks. Report: {report}')
