"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.sendMessage = void 0;
const app_1 = require("firebase-admin/app");
(0, app_1.initializeApp)();
var chat_1 = require("./functions/chat");
Object.defineProperty(exports, "sendMessage", { enumerable: true, get: function () { return chat_1.sendMessage; } });
//# sourceMappingURL=index.js.map