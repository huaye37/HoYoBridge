// Bounded disposable SMB test for the user-selected Lucian device directory.
// Does not unmount a share, touch existing files, or claim cold-cache throughput.
import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash, randomFillSync} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {performance} from 'node:perf_hooks';

const mount = '/Volumes/Lucian';
const directory = `${mount}/MacBook-Pro-M5-Pro/Diagnostics/MacGameBridge`;
function requireMount() {
  const mounts = execFileSync('/sbin/mount', {encoding:'utf8'}).split('\n');
  if (!mounts.some(line => line.includes(` on ${mount} (smbfs,`))) {
    throw new Error('Expected Lucian SMB mount missing; no local fallback allowed');
  }
}
requireMount();
if (await fs.realpath(directory) !== directory) throw new Error('Non-canonical test directory');
const disk = await fs.statfs(directory, {bigint:true});
const size = 512 * 1024 * 1024;
if (disk.bavail * disk.bsize < BigInt(size + 1024 * 1024 * 1024)) throw new Error('Insufficient reserve');
const temporary = await fs.mkdtemp(path.join(directory, 'storage-probe-'));
let activeFile = path.join(temporary, 'random-data.bin');
const block = Buffer.alloc(4 * 1024 * 1024);
const expected = createHash('sha256');
const writeStarted = performance.now();
const writer = await fs.open(activeFile, 'wx', 0o600);
try {
  for (let offset = 0; offset < size; offset += block.length) {
    randomFillSync(block);
    expected.update(block);
    for (let done = 0; done < block.length;) {
      const {bytesWritten} = await writer.write(block, done, block.length - done);
      if (!bytesWritten) throw new Error('Short write');
      done += bytesWritten;
    }
  }
  await writer.sync();
} finally { await writer.close(); }
const writeSeconds = (performance.now() - writeStarted) / 1000;
requireMount();
const renamed = path.join(temporary, 'renamed-data.bin');
await fs.rename(activeFile, renamed);
activeFile = renamed;
if ((await fs.stat(activeFile)).size !== size) throw new Error('Wrong stored size');
const actual = createHash('sha256');
let readBytes = 0;
const readStarted = performance.now();
const reader = await fs.open(activeFile, 'r');
try {
  while (true) {
    const {bytesRead} = await reader.read(block, 0, block.length, null);
    if (!bytesRead) break;
    actual.update(block.subarray(0, bytesRead));
    readBytes += bytesRead;
  }
} finally { await reader.close(); }
const readSeconds = (performance.now() - readStarted) / 1000;
const sha256 = expected.digest('hex');
if (readBytes !== size || actual.digest('hex') !== sha256) throw new Error('Readback checksum mismatch');
requireMount();
await fs.unlink(activeFile);
await fs.rmdir(temporary);
console.log(JSON.stringify({
  at: new Date().toISOString(), directory, bytes: size, sha256,
  writeMiBPerSecond: +(size / 1048576 / writeSeconds).toFixed(2),
  readMiBPerSecond: +(size / 1048576 / readSeconds).toFixed(2),
  writeSeconds: +writeSeconds.toFixed(3), readSeconds: +readSeconds.toFixed(3),
  rename: 'passed', checksum: 'passed', temporaryFilesRemoved: true,
  limitation: 'Single sequential SMB test; warm cache possible. Not game performance or durability validation.',
}, null, 2));
