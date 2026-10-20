// Restricted local operator tooling only. Compile existing trusted server modules
// in memory, preserving their real file locations and authorization implementations.
const fs = require('node:fs'), path = require('node:path'), ts = require('typescript');
function loadPlatform() {
  const previous = require.extensions['.ts'], root = path.resolve(__dirname, '../src/lib/platform') + path.sep;
  require.extensions['.ts'] = (module, filename) => {
    if (!filename.startsWith(root)) { if (previous) return previous(module, filename); throw new Error('Operator loader scope denied'); }
    const originalRequire = module.require.bind(module);
    module.require = name => name === 'server-only' ? {} : originalRequire(name);
    const result = ts.transpileModule(fs.readFileSync(filename, 'utf8'), { compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS, esModuleInterop: true } });
    module._compile(result.outputText, filename);
  };
  try {
    return { CommunityService: require('../src/lib/platform/server/community.ts').CommunityService, firestoreStore: require('../src/lib/platform/server/firestore-store.ts').firestoreStore, hash: require('../src/lib/platform/server/contract.ts').hash };
  } finally { if (previous) require.extensions['.ts'] = previous; else delete require.extensions['.ts']; }
}
module.exports = { loadPlatform };
