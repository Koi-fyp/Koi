module.exports = async function attachAvatarAudit(page, origin, { allowMicrophone = false } = {}) {
  const errors = [], consoleErrors = [], warnings = [], external = [];
    page.on('pageerror', (error) => errors.push(error.message));
    page.on('console', (message) => { if (message.type() === 'warning') warnings.push(message.text()); if (message.type() === 'error' && !/Failed to load resource.*404/.test(message.text())) consoleErrors.push(message.text()); });
    page.on('request', (request) => { if (!request.url().startsWith(origin) && !request.url().startsWith('blob:')) external.push(request.url()); });
    await page.addInitScript((allowMicrophone) => {
      window.__avatarAudit = { pending: new Set(), contexts: [], observers: new Set(), mediaCalls: 0, streams: [], mediaConstraints: [] };
      if (navigator.mediaDevices) { const capture = navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices); Object.defineProperty(navigator.mediaDevices, 'getUserMedia', { value: async (constraints) => { window.__avatarAudit.mediaCalls++; window.__avatarAudit.mediaConstraints.push(constraints); if (!allowMicrophone) throw new Error('Media permissions must never be requested by this preview.'); if (constraints.video !== false || constraints.audio !== true) throw new Error('Only explicit audio capture is allowed.'); const stream = await capture(constraints); window.__avatarAudit.streams.push(stream); return stream; } }); }
      const request = window.requestAnimationFrame.bind(window);
      const cancel = window.cancelAnimationFrame.bind(window);
      window.requestAnimationFrame = (callback) => {
        const id = request((time) => { window.__avatarAudit.pending.delete(id); callback(time); });
        window.__avatarAudit.pending.add(id); return id;
      };
      window.cancelAnimationFrame = (id) => { window.__avatarAudit.pending.delete(id); cancel(id); };
      const getContext = HTMLCanvasElement.prototype.getContext;
      HTMLCanvasElement.prototype.getContext = function (...args) {
        const context = getContext.apply(this, args);
        if (context && args[0] === 'webgl2' && !window.__avatarAudit.contexts.includes(context)) window.__avatarAudit.contexts.push(context);
        return context;
      };
      const Observer = window.ResizeObserver;
      window.ResizeObserver = class extends Observer {
        observe(...args) { window.__avatarAudit.observers.add(this); return super.observe(...args); }
        disconnect() { window.__avatarAudit.observers.delete(this); return super.disconnect(); }
      };
    }, allowMicrophone);
  return { errors, consoleErrors, warnings, external };
};
