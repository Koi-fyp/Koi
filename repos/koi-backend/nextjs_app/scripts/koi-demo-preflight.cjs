try { require('./koi-demo-guard.cjs').guard(); process.stdout.write('Exact isolated demo configuration verified.\n'); }
catch { process.stderr.write('Refusing non-demo hosts, project or credential environment.\n'); process.exitCode = 1; }
