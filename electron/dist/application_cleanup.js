"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.cleanupSessions = cleanupSessions;
exports.finishQuit = finishQuit;
async function cleanupSessions(sessions, attempts = 3) {
    let lastError = null;
    for (let attempt = 0; attempt < attempts; attempt += 1) {
        let failed = false;
        for (const session of sessions) {
            try {
                await session.leave();
            }
            catch (error) {
                failed = true;
                lastError = error;
            }
        }
        if (!failed)
            return;
        if (attempt + 1 < attempts) {
            await new Promise((resolve) => setTimeout(resolve, 50 * (attempt + 1)));
        }
    }
    throw lastError ?? new Error('Electron Example cleanup did not complete');
}
function finishQuit(cleanup, quit, fail) {
    void cleanup.then(quit, fail);
}
