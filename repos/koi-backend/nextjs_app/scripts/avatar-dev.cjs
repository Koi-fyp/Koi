const path = require('node:path');
const { spawn } = require('node:child_process');

if (process.env.NODE_ENV && process.env.NODE_ENV !== 'development') {
  console.error('The avatar sandbox is available only in development.');
  process.exit(1);
}
const root = path.resolve(__dirname, '..');
const child = spawn(process.execPath, [
  require.resolve('next/dist/bin/next'), 'dev',
  path.join(root, 'dev/avatar-sandbox'), '--hostname', '127.0.0.1', '--port', '3001',
], {
  cwd: root,
  stdio: 'inherit',
  env: { ...process.env, NODE_ENV: 'development',
    KOI_SANDBOX_MODELS_DIR: path.join(root, 'public/models') },
});
child.on('error', (error) => { console.error(error); process.exitCode = 1; });
child.on('exit', (code) => { process.exitCode = code ?? 1; });
for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => child.kill(signal));
}
