export type LeaveSession = Readonly<{leave(): Promise<void>}>;

export async function cleanupSessions(
  sessions: ReadonlyArray<LeaveSession>,
  attempts = 3,
): Promise<void> {
  let lastError: unknown = null;
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    let failed = false;
    for (const session of sessions) {
      try { await session.leave(); } catch (error) {
        failed = true;
        lastError = error;
      }
    }
    if (!failed) return;
    if (attempt + 1 < attempts) {
      await new Promise((resolve) => setTimeout(resolve, 50 * (attempt + 1)));
    }
  }
  throw lastError ?? new Error('Electron Example cleanup did not complete');
}

export function finishQuit(
  cleanup: Promise<void>,
  quit: () => void,
  fail: (error: unknown) => void,
): void {
  void cleanup.then(quit, fail);
}
