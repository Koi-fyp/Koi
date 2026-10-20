// Test/build process only. Never import into the application or cloud operator tools.
// Deny before DNS/socket creation; inherited by Node child processes via NODE_OPTIONS.
const net = require('node:net');
const dns = require('node:dns');
const local = host => ['localhost', '127.0.0.1', '::1', '[::1]'].includes(host);
const denied = () => { const e = new Error('WEB5_OFFLINE_NETWORK_DENIED'); e.code = 'WEB5_OFFLINE_NETWORK_DENIED'; throw e; };
const connect = net.Socket.prototype.connect;
net.Socket.prototype.connect = function (...args) {
  const options = args[0];
  if (typeof options === 'object' && options !== null) {
    if (!options.path && !local(options.host ?? options.hostname ?? 'localhost')) denied();
  } else if (typeof options === 'number' || /^\d+$/.test(String(options))) {
    if (typeof args[1] === 'string' && !local(args[1])) denied();
  } else if (typeof options !== 'string' || !/^(\\\\\.\\pipe\\|\/)/.test(options)) denied();
  return connect.apply(this, args);
};
const lookup = dns.lookup;
dns.lookup = function (host, ...args) { if (!local(host)) denied(); return lookup.call(this, host, ...args); };
if (dns.promises) { const p = dns.promises.lookup; dns.promises.lookup = async function (host, ...args) { if (!local(host)) denied(); return p.call(this, host, ...args); }; }
for (const name of ['node:http', 'node:https']) {
  const module = require(name);
  for (const method of ['request', 'get']) {
    const original = module[method];
    module[method] = function (input, ...args) {
      const u = typeof input === 'string' || input instanceof URL ? new URL(input) : input;
      if (!local(u.hostname ?? u.host ?? 'localhost')) denied();
      if (/^\/api\/v1\/(chat|crisis)(?:[/?]|$)/.test(u.pathname ?? u.path ?? '')) denied();
      return original.call(this, input, ...args);
    };
  }
}
if (globalThis.fetch) {
  const fetch = globalThis.fetch;
  globalThis.fetch = function (input, ...args) {
    const u = new URL(typeof input === 'string' || input instanceof URL ? input : input.url);
    if (!local(u.hostname) || /^\/api\/v1\/(chat|crisis)(?:[/?]|$)/.test(u.pathname)) denied();
    return fetch.call(this, input, ...args);
  };
}
