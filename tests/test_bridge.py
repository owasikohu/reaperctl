import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
LUA = os.environ.get('LUA') or shutil.which('lua5.4') or shutil.which('lua')


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.directory = Path(self.temp.name)
        self.host = None

    def tearDown(self):
        if self.host:
            self.host.stdin.close()
            self.host.wait(timeout=5)
            self.host.stdout.close()
            self.host.stderr.close()
        self.temp.cleanup()

    def start_host(self):
        if not LUA:
            self.skipTest('Lua 5.4 required; set LUA=/path/to/lua')
        self.host = subprocess.Popen(
            [LUA, str(ROOT / 'tests/mock_reaper.lua'), str(ROOT / 'bridge.lua')],
            env={**os.environ, 'REAPER_AGENT_DIR': str(self.directory)},
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    def tick(self):
        self.host.stdin.write('|'.join(p.name for p in self.directory.iterdir()) + '\n')
        self.host.stdin.flush()
        self.assertEqual(self.host.stdout.readline(), 'tick\n')

    def run_cli(self, script, timeout='2'):
        return subprocess.Popen(
            [sys.executable, str(ROOT / 'reaperctl.py'), 'exec', str(script),
             '--ipc-dir', str(self.directory), '--timeout', timeout],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    def finish(self, process):
        deadline = time.monotonic() + 5
        while process.poll() is None and time.monotonic() < deadline:
            if self.host:
                self.tick()
            time.sleep(0.01)
        out, err = process.communicate(timeout=2)
        self.assertEqual(err, '')
        return process.returncode, json.loads(out)

    def script(self, source):
        path = self.directory / 'input.lua'
        path.write_text(source, encoding='utf-8')
        return path

    def test_round_trip(self):
        self.start_host()
        results = []
        for name in ['hello', 'inspect_project', 'create_track', 'inspect_project']:
            status, payload = self.finish(self.run_cli(ROOT / f'examples/{name}.lua'))
            self.assertEqual(status, 0, payload)
            results.append(payload['result'])
        self.assertEqual(results[0]['version'], 'MOCK-7')
        self.assertEqual(results[1]['track_count'], 0)
        self.assertEqual(results[3]['track_count'], 1)
        self.assertEqual(results[3]['tracks'][0]['name'], 'Agent Test')
        self.assertEqual(list(self.directory.iterdir()), [])

    def test_errors_and_recovery(self):
        self.start_host()
        for source in ['this is not lua', 'error("boom")', 'return function() end',
                       'local t = {}; t.self=t; return t', 'return 0/0',
                       'return {[2]=1}', 'reaper.defer(function() end)',
                       'return string.char(255)']:
            with self.subTest(source=source):
                status, payload = self.finish(self.run_cli(self.script(source)))
                self.assertEqual(status, 1)
                self.assertFalse(payload['ok'])
                self.assertTrue(payload['error'])
        status, payload = self.finish(self.run_cli(self.script('return {text="日本語\\n\\\"", values={true,false,3}}')))
        self.assertEqual(status, 0, payload)
        self.assertEqual(payload['result']['text'], '日本語\n"')
        self.assertEqual(payload['result']['values'], [True, False, 3])

    def test_concurrent_requests(self):
        self.start_host()
        processes = [self.run_cli(ROOT / 'examples/hello.lua') for _ in range(5)]
        results = [self.finish(p) for p in processes]
        self.assertTrue(all(status == 0 for status, _ in results))
        self.assertEqual(len({p['id'] for _, p in results}), 5)

    def test_scalar_results(self):
        self.start_host()
        for source, expected in [('return', None), ('return false', False),
                                 ('return 42', 42), ('return {}', {}),
                                 ('return {1,2}, "ignored"', [1, 2])]:
            with self.subTest(source=source):
                status, payload = self.finish(self.run_cli(self.script(source)))
                self.assertEqual(status, 0, payload)
                self.assertEqual(payload['result'], expected)

    def test_timeout_cancels_pending(self):
        status, payload = self.finish(self.run_cli(ROOT / 'examples/hello.lua', '0.05'))
        self.assertEqual(status, 124)
        self.assertEqual(payload['error'], 'timeout')
        self.assertEqual(list(self.directory.iterdir()), [])

    def test_missing_file(self):
        status, payload = self.finish(self.run_cli(self.directory / 'missing.lua'))
        self.assertEqual(status, 1)
        self.assertFalse(payload['ok'])

    def test_expired_and_incomplete_requests(self):
        self.start_host()
        request_id = 'a' * 32
        partial = self.directory / f'request-{request_id}.tmp'
        partial.write_text('error("must not run")')
        expired = self.directory / f'request-{request_id}.lua'
        expired.write_text('-- expires: 1\nreaper.InsertTrackAtIndex(0, true)')
        self.tick()
        payload = json.loads((self.directory / f'response-{request_id}.json').read_text())
        self.assertFalse(payload['ok'])
        self.assertIn('expired', payload['error'])
        self.assertTrue(partial.exists())
        _, payload = self.finish(self.run_cli(ROOT / 'examples/inspect_project.lua'))
        self.assertEqual(payload['result']['track_count'], 0)


if __name__ == '__main__':
    unittest.main()
