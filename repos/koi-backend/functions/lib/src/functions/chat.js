"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.sendMessage = void 0;
const https_1 = require("firebase-functions/v2/https");
const geminiClient_1 = require("../lib/geminiClient");
const geminiClient = new geminiClient_1.GeminiClient(process.env.GEMINI_API_KEY ?? '');
function validateInput(data) {
    if (!data || typeof data !== 'object') {
        throw new https_1.HttpsError('invalid-argument', 'Request data must be an object');
    }
    const d = data;
    if (typeof d.message !== 'string' || d.message.trim().length === 0) {
        throw new https_1.HttpsError('invalid-argument', 'message must be a non-empty string');
    }
    if (typeof d.conversationId !== 'string' || !d.conversationId) {
        throw new https_1.HttpsError('invalid-argument', 'conversationId is required');
    }
    if (typeof d.userId !== 'string' || !d.userId) {
        throw new https_1.HttpsError('invalid-argument', 'userId is required');
    }
    if (!Array.isArray(d.context)) {
        throw new https_1.HttpsError('invalid-argument', 'context must be an array');
    }
    if (!d.userProfile || typeof d.userProfile !== 'object') {
        throw new https_1.HttpsError('invalid-argument', 'userProfile is required');
    }
    return d;
}
exports.sendMessage = (0, https_1.onCall)({
    cors: true,
    enforceAppCheck: false,
    timeoutSeconds: 30,
    memory: '256MiB',
}, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError('unauthenticated', 'Request must be authenticated');
    }
    const input = validateInput(request.data);
    // Trust userId from input but double-check it matches auth token
    if (request.auth.uid !== input.userId) {
        throw new https_1.HttpsError('permission-denied', 'userId does not match authenticated user');
    }
    try {
        const geminiResult = await geminiClient.sendMessage(input.message.trim(), input.context.slice(-5), input.userProfile, input.userId);
        return {
            ...geminiResult,
            conversationId: input.conversationId,
        };
    }
    catch (err) {
        console.error('[KOI] Cloud Function internal error:', err);
        throw new https_1.HttpsError('internal', `Gemini call failed: ${err?.message}`);
    }
});
//# sourceMappingURL=chat.js.map