"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.checkRateLimit = checkRateLimit;
exports.incrementCount = incrementCount;
exports.isApproachingLimit = isApproachingLimit;
exports.getTimeUntilWindowReset = getTimeUntilWindowReset;
exports.forceSetCount = forceSetCount;
exports.clearAllLimits = clearAllLimits;
const WINDOW_MS = 60000;
const HARD_LIMIT = 15;
const SOFT_LIMIT = 12;
const store = new Map();
function getState(userId) {
    const now = Date.now();
    const existing = store.get(userId);
    if (!existing || now - existing.windowStart >= WINDOW_MS) {
        const fresh = { count: 0, windowStart: now };
        store.set(userId, fresh);
        return fresh;
    }
    return existing;
}
function checkRateLimit(userId) {
    const state = getState(userId);
    if (state.count >= HARD_LIMIT) {
        const retryAfterMs = WINDOW_MS - (Date.now() - state.windowStart);
        return { allowed: false, currentCount: state.count, retryAfterMs };
    }
    return { allowed: true, currentCount: state.count };
}
function incrementCount(userId) {
    const state = getState(userId);
    state.count += 1;
}
function isApproachingLimit(userId) {
    const state = getState(userId);
    return state.count >= SOFT_LIMIT;
}
function getTimeUntilWindowReset(userId) {
    const state = getState(userId);
    const elapsed = Date.now() - state.windowStart;
    return Math.max(0, WINDOW_MS - elapsed);
}
function forceSetCount(userId, count) {
    const state = getState(userId);
    state.count = count;
}
function clearAllLimits() {
    store.clear();
}
//# sourceMappingURL=rateLimit.js.map