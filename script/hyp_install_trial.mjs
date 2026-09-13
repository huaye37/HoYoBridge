// Local official-launcher experiment, NOT a production/headless integration.
// The caller starts the isolated HYP prefix with a loopback-only debugging port.
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';

const games = {
  bh3_cn: 'HonkaiImpact3', nap_cn: 'ZenlessZoneZero',
  hkrpg_cn: 'StarRail', hk4e_cn: 'GenshinImpact',
};
const [command = 'status', gameBiz = 'bh3_cn'] = process.argv.slice(2);
if (!['info', 'status', 'install', 'pause', 'resume', 'continue-install', 'observe', 'watch', 'monitor', 'uninstall'].includes(command) || !games[gameBiz]) {
  throw new Error('Use info/status/install/pause/resume/continue-install/observe/watch/monitor/uninstall and a supported CN gameBiz');
}
const root = process.env.MGB_TRIAL_ROOT || path.join(os.homedir(), 'Games/MacGameBridge/Trials');
// An explicit existing root lets the same bounded trial target user-selected storage.
// Refuse a missing /Volumes mount instead of accidentally filling the local disk.
if (process.env.MGB_TRIAL_ROOT) {
  if (!path.isAbsolute(root) || root === '/' || root === os.homedir() ||
      await fs.realpath(root) !== root || !(await fs.stat(root)).isDirectory()) {
    throw new Error('MGB_TRIAL_ROOT must be an existing canonical dedicated directory');
  }
  if (root.startsWith('/Volumes/')) {
    const mount = root.split('/').slice(0, 3).join('/');
    const {stdout} = await promisify(execFile)('/sbin/mount', []);
    if (!stdout.split('\n').some(line => line.includes(` on ${mount} (smbfs,`)) ||
        (await fs.stat(root)).dev !== (await fs.stat(mount)).dev) {
      throw new Error('Expected SMB volume missing; no local fallback allowed');
    }
  }
}
// Genshin is restored to the original app-selected location only after verification.
// Keeping incomplete files here prevents the current app mistaking an early exe for an installed game.
const destination = path.join(root, games[gameBiz]);
const windowsPath = 'Z:' + destination.replaceAll('/', '\\');
const pages = await (await fetch('http://127.0.0.1:19222/json/list')).json();
const page = pages.find(p => p.type === 'page' && p.url.startsWith('https://hyp-api.mihoyo.com/hypfe/'));
if (!page || new URL(page.webSocketDebuggerUrl).hostname !== '127.0.0.1') {
  throw new Error('Expected isolated loopback official-launcher page missing');
}
const socket = new WebSocket(page.webSocketDebuggerUrl);
await new Promise((resolve, reject) => { socket.onopen = resolve; socket.onerror = reject; });
let requestID = 0;
const pending = new Map();
socket.onmessage = event => {
  const response = JSON.parse(event.data);
  pending.get(response.id)?.(response);
};
socket.onerror = () => { process.exitCode = 1; };
async function evaluate(expression, timeoutMs = 20000) {
  const id = ++requestID;
  return await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => { pending.delete(id); reject(new Error('Native query timed out; inspect status before retrying a write')); }, timeoutMs);
    pending.set(id, response => {
      clearTimeout(timeout); pending.delete(id);
      if (response.error || response.result?.exceptionDetails) reject(new Error('Native evaluation failed'));
      else resolve(response.result?.result?.value);
    });
    socket.send(JSON.stringify({id, method: 'Runtime.evaluate', params: {expression, awaitPromise: true, returnByValue: true}}));
  });
}
function query(action, data) {
  const request = JSON.stringify({action, data});
  // NAS package scanning can outlive a short callback window; Sophon logs prove
  // the work continues. Keep one request alive instead of queuing retries.
  const timeoutMs = action === 'getGameInstallInfo' ? 180000 : 12000;
  return evaluate(`Promise.race([
    new Promise((resolve,reject)=>window.CefViewQuery({
      request:${JSON.stringify(request)},onSuccess:r=>resolve(r?JSON.parse(r):null),
      onFailure:(code)=>reject(new Error(String(code)))})),
    new Promise(resolve=>setTimeout(()=>resolve({callbackPending:true}),${timeoutMs}))
  ])`, timeoutMs + 2000);
}
function sanitize(value, key = '') {
  if (/token|password|secret|appkey|device|cookie|authorization|session|account|uid|guid/i.test(key)) return '[redacted]';
  if (typeof value === 'string') return value.replace(/https?:\/\/[^\s"<>]+/g, '[URL]');
  if (Array.isArray(value)) return value.map(v => sanitize(v));
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([k,v]) => [k,sanitize(v,k)]));
  return value;
}
function report(value) { console.log(JSON.stringify(sanitize(value))); }

try {
  await evaluate(`(()=>{
    if (!window.__mgbInstallTrial) {
      window.__mgbInstallTrial={downloads:{},games:{}};
      for (const [event,key] of [['updateDownloadStatus','downloads'],['updateGameInfo','games']]) {
        window.HYPClient.addEventListener(event,data=>{
          if(typeof data==='string') {try{data=JSON.parse(data)}catch{return}}
          if(data?.gameBiz) window.__mgbInstallTrial[key][data.gameBiz]={at:Date.now(),...data};
        });
      }
    }
    return true;
  })()`);
  if (command === 'info') {
    report(await query('getGameInstallInfo', {gameBiz, dir: windowsPath}));
  } else if (command === 'status') {
    report({local: await query('getLocalGameInfo', {gameBiz}), events: await evaluate(`window.__mgbInstallTrial`)});
  } else if (command === 'install') {
    await fs.mkdir(root, {recursive:true});
    if ((await fs.lstat(root)).isSymbolicLink()) throw new Error('Trial root must not be a symlink');
    const existing = await fs.lstat(destination).catch(e => { if(e.code!=='ENOENT')throw e; return null; });
    if (existing && (existing.isSymbolicLink() || !existing.isDirectory() || (await fs.readdir(destination)).length)) {
      throw new Error('Fresh install requires an absent or empty dedicated trial directory; use resume for an existing task');
    }
    const local = await query('getLocalGameInfo', {gameBiz});
    const installed = Array.isArray(local) ? local.find(g=>g.gameBiz===gameBiz) : local;
    if (installed?.installPath) throw new Error('Game is already linked; inspect its path before starting another installation');
    const info = await query('getGameInstallInfo', {gameBiz, dir: windowsPath});
    if (info?.result !== 'success') throw new Error('Official install preflight did not succeed');
    const voices = (info.voicePackages || []).filter(v=>v.lang==='zh-cn');
    const download = BigInt(info.gamePackage.size) + voices.reduce((n,v)=>n+BigInt(v.size),0n);
    const installedBytes = BigInt(info.gamePackage.unzipSpace) + voices.reduce((n,v)=>n+BigInt(v.unzipSpace),0n);
    // Match the observed official install dialog: game/selected voice unzipSpace
    // plus extraStagingSize, not download bytes added a second time. Keep 10 GB reserve.
    const required = installedBytes + BigInt(info.extraStagingSize||0) + 10000000000n;
    const disk = await fs.statfs(root, {bigint:true});
    const available = disk.bavail * disk.bsize;
    report({gameBiz, destination, downloadBytes:String(download), officialSpaceWithReserve:String(required), availableBytes:String(available)});
    if (available < required) throw new Error('Insufficient space for isolated install with reserve; no download started');
    report(await query('startDownload', {
      gameBiz, package:info.package||'', path:windowsPath, voiceLangList:voices.map(v=>v.lang),
      packageType:'FULL', createShortcut:false, createShortcutInStartMenu:false,
    }));
  } else if (command === 'uninstall') {
    if (gameBiz==='hk4e_cn') throw new Error('The final Genshin installation must be preserved');
    // Explicit cleanup only, after the caller has stopped the game's isolated prefix.
    // Never remove arbitrary user paths or another installation linked by the launcher.
    const local = await query('getLocalGameInfo', {gameBiz});
    const game = Array.isArray(local) ? local.find(g=>g.gameBiz===gameBiz) : local;
    if (game?.installPath?.replace(/\\+$/,'') !== windowsPath || game.status !== 'ready') {
      throw new Error('Cleanup requires the completed, exact trial installation');
    }
    if (await fs.realpath(destination) !== destination || !(await fs.lstat(destination)).isDirectory()) {
      throw new Error('Refusing cleanup through a symlink or non-directory');
    }
    // HYP cannot see games launched in another Wine prefix; check macOS as well.
    const executable = {bh3_cn:'bh3.exe',nap_cn:'zenlesszonezero.exe',hkrpg_cn:'starrail.exe'}[gameBiz];
    const processes = await promisify(execFile)('/bin/ps', ['-axo','comm']);
    if (processes.stdout.toLowerCase().split('\n').some(p=>p.trim().split(/[\\/]/).at(-1)===executable)) {
      throw new Error('Game is still running in a Wine prefix; stop it before cleanup');
    }
    report({operation:'uninstall', gameBiz, destination});
    report(await query('uninstallGame', {gameBiz, package:'', path:windowsPath, killProcess:false}));
    const remains = await fs.lstat(destination).catch(e=>{if(e.code!=='ENOENT')throw e;return null;});
    report({directoryRemoved:!remains, local:await query('getLocalGameInfo',{gameBiz})});
    if (remains) throw new Error('Official uninstall left the directory in place; inspect before any cleanup or retry');
  } else if (command === 'pause' || command === 'resume' || command === 'continue-install') {
    const local = await query('getLocalGameInfo', {gameBiz});
    const game = Array.isArray(local) ? local.find(g=>g.gameBiz===gameBiz) : local;
    if (game?.installPath?.replace(/\\+$/,'') !== windowsPath) throw new Error('Refusing to control a game outside its dedicated trial directory');
    if (command==='continue-install') {
      const download = await evaluate(`window.__mgbInstallTrial.downloads[${JSON.stringify(gameBiz)}]`);
      if (game.status!=='need_install' || (download && !['cancelled','failed'].includes(download.status))) {
        throw new Error('Cold continuation requires an incomplete installation without an active download');
      }
      if (await fs.realpath(destination) !== destination) throw new Error('Refusing continuation through a symlink');
      // Official startInstall path rebuilds the task after a backend restart;
      // resumeDownload only resumes a task still present in the running backend.
      report(await query('startDownload', {gameBiz, package:'', isInterrupted:true}));
    } else {
      report(await query(command==='pause'?'pauseDownload':'resumeDownload', {gameBiz, package:''}));
    }
  } else {
    const samples = command==='monitor' ? Infinity : command==='watch' ? 120 : 6;
    const interval = command==='monitor' ? 30000 : command==='watch' ? 15000 : 5000;
    for (let i=0; i<samples; i++) {
      const snapshot = await evaluate(`({game:window.__mgbInstallTrial.games[${JSON.stringify(gameBiz)}],download:window.__mgbInstallTrial.downloads[${JSON.stringify(gameBiz)}]})`);
      if (command==='monitor') {
        const d = snapshot?.download;
        const age = d?.at ? Math.round((Date.now()-d.at)/1000) : null;
        console.log(`${new Date().toLocaleTimeString('zh-CN')} ${gameBiz} ${d?.status||'等待状态'} ${Number(d?.percent||0).toFixed(2)}% ${(Number(d?.processedBytes||0)/1e9).toFixed(2)}/${(Number(d?.totalBytes||0)/1e9).toFixed(2)} GB ${(Number(d?.downloadSpeed||0)/1e6).toFixed(2)} MB/s${age===null||age>90?' [状态未更新，请检查后台]':''}`);
      } else report(snapshot);
      if (['watch','monitor'].includes(command) && ['success','failed','cancelled'].includes(snapshot?.download?.status)) break;
      if(i<samples-1) await new Promise(resolve=>setTimeout(resolve,interval));
    }
  }
} finally {
  socket.onerror = () => {};
  socket.close();
}
