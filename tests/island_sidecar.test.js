import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';

test('island sidecar responds to requests without leaking non-JSON output', async () => {
  const child = spawn(process.execPath, ['src/island/sidecar.js'], {
    cwd: process.cwd(),
    env: { ...process.env, TV_CDP_PORT: '1' },
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  child.stdin.write('{"id":1,"action":"unknown"}\n');
  child.stdin.write('{"id":2,"action":"health"}\n');
  child.stdin.end();
  let output = '';
  child.stdout.setEncoding('utf8');
  child.stdout.on('data', chunk => output += chunk);
  const [code] = await once(child, 'exit');
  assert.equal(code, 0);
  const lines = output.trim().split('\n').map(JSON.parse);
  assert.equal(lines.length, 2);
  assert.deepEqual(lines.map(x => x.id), [1, 2]);
  assert.match(lines[0].error, /Unknown action/);
  assert.match(lines[1].error, /TradingView CDP is unavailable/);
});
