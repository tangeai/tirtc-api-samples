export type AcceptedOperation<Owner extends string> = Readonly<{
  promise: Promise<unknown>;
  owners: ReadonlySet<Owner>;
}>;

export async function settlesWithin(
  operation: Promise<unknown>,
  timeoutMs: number,
): Promise<boolean> {
  let timer: ReturnType<typeof setTimeout> | null = null;
  try {
    return await Promise.race([
      operation.then(() => true, () => true),
      new Promise<false>((resolve) => { timer = setTimeout(() => resolve(false), timeoutMs); }),
    ]);
  } finally {
    if (timer !== null) clearTimeout(timer);
  }
}

export class OperationBarrier<Owner extends string> {
  readonly #accepted = new Set<AcceptedOperation<Owner>>();

  track<T>(operation: Promise<T>, ...owners: Owner[]): Promise<T> {
    let accepted!: AcceptedOperation<Owner>;
    let tracked!: Promise<T>;
    tracked = operation.finally(() => { this.#accepted.delete(accepted); });
    accepted = {promise: tracked, owners: new Set(owners)};
    this.#accepted.add(accepted);
    return tracked;
  }

  async drain(timeoutMs: number): Promise<boolean> {
    while (this.#accepted.size !== 0) {
      const current = Promise.allSettled([...this.#accepted].map((operation) => operation.promise));
      if (!await settlesWithin(current, timeoutMs)) return false;
    }
    return true;
  }

  busy(owner: Owner): boolean {
    return [...this.#accepted].some((operation) => operation.owners.has(owner));
  }
}
