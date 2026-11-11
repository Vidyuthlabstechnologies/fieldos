// account-cleanup: removes the files of deleted companies (issue #139).
// delete_my_account() queues each deleted site's folder; this drains the
// queue through the Storage API, which is the only way Storage allows.

export interface CleanupDeps {
  /** Files still in queued folders, at most [limit]. */
  queuedFiles(limit: number): Promise<{ bucket: string; name: string }[]>;
  /** Removes files from one bucket (at most 100 per call). */
  remove(bucket: string, names: string[]): Promise<void>;
  /** Clears folders with no files left; returns how many. */
  finish(): Promise<number>;
}

export interface CleanupResult {
  removed: number;
  foldersCleared: number;
  done: boolean;
}

/** Drains the queue, up to [maxRounds] lists of [pageSize] files. */
export async function drain(deps: CleanupDeps, pageSize = 1000, maxRounds = 20): Promise<CleanupResult> {
  let removed = 0;
  for (let round = 0; round < maxRounds; round++) {
    const files = await deps.queuedFiles(pageSize);
    if (files.length === 0) return { removed, foldersCleared: await deps.finish(), done: true };
    const byBucket = new Map<string, string[]>();
    for (const f of files) byBucket.set(f.bucket, [...(byBucket.get(f.bucket) ?? []), f.name]);
    for (const [bucket, names] of byBucket) {
      for (let i = 0; i < names.length; i += 100) {
        const batch = names.slice(i, i + 100);
        await deps.remove(bucket, batch);
        removed += batch.length;
      }
    }
  }
  return { removed, foldersCleared: await deps.finish(), done: false };
}
