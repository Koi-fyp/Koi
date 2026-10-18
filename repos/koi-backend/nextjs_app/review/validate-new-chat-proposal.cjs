// Review validation only: reconstructs candidates in memory; never writes/applies source.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const ts = require('../node_modules/typescript');
const root = path.resolve(__dirname, '../../../..');
const app = path.resolve(__dirname, '..');
const baseline = JSON.parse(fs.readFileSync(path.join(__dirname, 'new-chat-source-baseline.json'), 'utf8'));
let failed = false;
let baselineUnchanged = true;
const overlay = new Map();
const overlayPaths = [];
for (const [file, expected] of Object.entries(baseline.files)) {
  const actual = crypto.createHash('sha256').update(fs.readFileSync(path.join(app, file))).digest('hex');
  if (actual !== expected) { failed = true; baselineUnchanged = false; console.log(JSON.stringify({ file, baselineUnchanged: false })); }
}
for (const name of ['new-chat-session.proposed.diff', 'new-chat-consumers.proposed.diff', 'new-chat-tests.proposed.diff']) {
  const patch = fs.readFileSync(path.join(__dirname, name), 'utf8').replace(/\r\n/g, '\n');
  for (const section of patch.split('diff --git ').slice(1)) {
    const lines = section.split('\n');
    const file = lines[0].split(' b/')[1];
    const full = path.join(root, file);
    if (!full.startsWith(root + path.sep)) throw Error('Invalid review path');
    const original = fs.existsSync(full) ? fs.readFileSync(full, 'utf8').replace(/\r\n/g, '\n').split('\n') : [];
    let cursor = 0;
    const output = [];
    for (let i = 0; i < lines.length; i++) {
      const hunk = /^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/.exec(lines[i]);
      if (!hunk) continue;
      const start = Math.max(0, Number(hunk[1]) - 1);
      output.push(...original.slice(cursor, start)); cursor = start;
      for (i++; i < lines.length && !lines[i].startsWith('@@ '); i++) {
        const line = lines[i], tag = line[0];
        if (![' ', '+', '-'].includes(tag)) continue;
        if (tag !== '+') {
          if (original[cursor] !== line.slice(1)) throw Error(`Review context changed: ${file}`);
          cursor++;
        }
        if (tag !== '-') output.push(line.slice(1));
      }
      i--;
    }
    output.push(...original.slice(cursor));
    const candidate = output.join('\n');
    overlay.set(path.resolve(full).toLowerCase(), candidate);
    overlayPaths.push(path.resolve(full));
    const parsed = ts.createSourceFile(file, candidate, ts.ScriptTarget.Latest, true, file.endsWith('.tsx') ? ts.ScriptKind.TSX : ts.ScriptKind.TS);
    const count = parsed.parseDiagnostics.length;
    if (count) failed = true;
    console.log(JSON.stringify({ file, syntaxDiagnostics: count, applied: false }));
  }
}
if (process.argv.includes('--semantic')) {
  const configFile = path.join(app, 'tsconfig.json');
  const config = ts.readConfigFile(configFile, ts.sys.readFile);
  const parsed = ts.parseJsonConfigFileContent(config.config, ts.sys, app);
  const options = { ...parsed.options, configFilePath: configFile, noEmit: true, incremental: false };
  const host = ts.createCompilerHost(options);
  host.getCurrentDirectory = () => app;
  const read = host.readFile.bind(host), exists = host.fileExists.bind(host);
  const source = host.getSourceFile.bind(host);
  host.readFile = file => overlay.get(path.resolve(file).toLowerCase()) ?? read(file);
  host.fileExists = file => overlay.has(path.resolve(file).toLowerCase()) || exists(file);
  host.getSourceFile = (file, languageVersion, onError, fresh) => overlay.has(path.resolve(file).toLowerCase())
    ? ts.createSourceFile(file, overlay.get(path.resolve(file).toLowerCase()), languageVersion, true)
    : source(file, languageVersion, onError, fresh);
  const files = [...new Map([...parsed.fileNames, ...overlayPaths].map(file => [file.toLowerCase(), file])).values()];
  const program = ts.createProgram(files, options, host);
  const diagnostics = ts.getPreEmitDiagnostics(program);
  if (diagnostics.length) failed = true;
  for (const diagnostic of diagnostics.slice(0, 20)) console.log(JSON.stringify({
    file: diagnostic.file ? path.relative(root, diagnostic.file.fileName) : null,
    code: diagnostic.code,
    message: ts.flattenDiagnosticMessageText(diagnostic.messageText, ' '),
  }));
  console.log(JSON.stringify({ proposedSemanticDiagnostics: diagnostics.length, applied: false, emitted: false }));
}
console.log(JSON.stringify({ baselineUnchanged, validation: process.argv.includes('--semantic') ? 'in-memory syntax/TypeScript only; tests/browser NOT RUN' : 'syntax/context only; not semantic tests or browser acceptance', applied: false }));
process.exitCode = failed ? 1 : 0;
