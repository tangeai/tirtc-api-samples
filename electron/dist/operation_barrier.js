"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.OperationBarrier = void 0;
exports.settlesWithin = settlesWithin;
async function settlesWithin(operation, timeoutMs) {
    let timer = null;
    try {
        return await Promise.race([
            operation.then(() => true, () => true),
            new Promise((resolve) => { timer = setTimeout(() => resolve(false), timeoutMs); }),
        ]);
    }
    finally {
        if (timer !== null)
            clearTimeout(timer);
    }
}
class OperationBarrier {
    #accepted = new Set();
    track(operation, ...owners) {
        let accepted;
        let tracked;
        tracked = operation.finally(() => { this.#accepted.delete(accepted); });
        accepted = { promise: tracked, owners: new Set(owners) };
        this.#accepted.add(accepted);
        return tracked;
    }
    async drain(timeoutMs) {
        while (this.#accepted.size !== 0) {
            const current = Promise.allSettled([...this.#accepted].map((operation) => operation.promise));
            if (!await settlesWithin(current, timeoutMs))
                return false;
        }
        return true;
    }
    busy(owner) {
        return [...this.#accepted].some((operation) => operation.owners.has(owner));
    }
}
exports.OperationBarrier = OperationBarrier;
