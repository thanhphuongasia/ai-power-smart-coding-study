import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";

type PlainObject = Record<string, unknown>;

export type ManagedEntry<T extends PlainObject> = {
  id: string;
  draft: T;
  published: T | null;
  updatedAt: string;
  publishedAt: string | null;
};

export type ContentStore = {
  schemaVersion: number;
  contentVersion: number;
  lastPublishedAt: string | null;
  tracks: ManagedEntry<PlainObject>[];
  skills: ManagedEntry<PlainObject>[];
};

export type PublishedCatalogSnapshot = {
  tracks: PlainObject[];
  skills: PlainObject[];
};

export class ContentStoreRepository {
  constructor({
    storePath,
    bootstrapSnapshotPath,
  }: {
    storePath: string;
    bootstrapSnapshotPath?: string;
  }) {
    this.storePath = storePath;
    this.bootstrapSnapshotPath = bootstrapSnapshotPath;
  }

  readonly storePath: string;
  readonly bootstrapSnapshotPath?: string;

  async load(): Promise<ContentStore> {
    try {
      const raw = await fs.readFile(this.storePath, "utf8");
      return normalizeStore(JSON.parse(raw) as Partial<ContentStore>);
    } catch (error) {
      if (!isMissingFileError(error)) {
        throw error;
      }
    }

    const initialStore = await this.createInitialStore();
    await this.save(initialStore);
    return initialStore;
  }

  async save(store: ContentStore) {
    await fs.mkdir(path.dirname(this.storePath), { recursive: true });
    await fs.writeFile(this.storePath, JSON.stringify(store, null, 2));
  }

  async listPublishedCatalog(): Promise<PublishedCatalogSnapshot> {
    const store = await this.load();
    return toPublishedCatalog(store);
  }

  async buildManifest() {
    const store = await this.load();
    const publishedCatalog = toPublishedCatalog(store);
    const checksum = crypto
      .createHash("sha256")
      .update(JSON.stringify(publishedCatalog))
      .digest("hex");

    return {
      contentVersion: String(store.contentVersion),
      publishedAt: store.lastPublishedAt ?? new Date(0).toISOString(),
      checksum,
    };
  }

  async listAdminCatalog() {
    const store = await this.load();
    return {
      schemaVersion: store.schemaVersion,
      contentVersion: store.contentVersion,
      lastPublishedAt: store.lastPublishedAt,
      tracks: store.tracks.map(withWorkflowStatus),
      skills: store.skills.map(withWorkflowStatus),
    };
  }

  async createTrack(track: PlainObject) {
    const store = await this.load();
    const entry = createDraftEntry(track);
    store.tracks.push(entry);
    await this.save(store);
    return withWorkflowStatus(entry);
  }

  async updateTrack(trackId: string, track: PlainObject) {
    return this.updateEntry("tracks", trackId, track);
  }

  async deleteTrack(trackId: string) {
    return this.deleteEntry("tracks", trackId);
  }

  async publishTrack(trackId: string) {
    return this.publishEntry("tracks", trackId);
  }

  async unpublishTrack(trackId: string) {
    return this.unpublishEntry("tracks", trackId);
  }

  async createSkill(skill: PlainObject) {
    const store = await this.load();
    const entry = createDraftEntry(skill);
    store.skills.push(entry);
    await this.save(store);
    return withWorkflowStatus(entry);
  }

  async updateSkill(skillId: string, skill: PlainObject) {
    return this.updateEntry("skills", skillId, skill);
  }

  async deleteSkill(skillId: string) {
    return this.deleteEntry("skills", skillId);
  }

  async publishSkill(skillId: string) {
    return this.publishEntry("skills", skillId);
  }

  async unpublishSkill(skillId: string) {
    return this.unpublishEntry("skills", skillId);
  }

  private async updateEntry(
    key: "tracks" | "skills",
    entryId: string,
    nextDraft: PlainObject,
  ) {
    const store = await this.load();
    const entry = store[key].find((item) => item.id === entryId);
    if (!entry) {
      return null;
    }
    entry.draft = sanitizePayload(nextDraft);
    entry.updatedAt = new Date().toISOString();
    await this.save(store);
    return withWorkflowStatus(entry);
  }

  private async deleteEntry(key: "tracks" | "skills", entryId: string) {
    const store = await this.load();
    const before = store[key].length;
    store[key] = store[key].filter((item) => item.id !== entryId);
    if (store[key].length == before) {
      return false;
    }
    await this.save(store);
    return true;
  }

  private async publishEntry(key: "tracks" | "skills", entryId: string) {
    const store = await this.load();
    const entry = store[key].find((item) => item.id === entryId);
    if (!entry) {
      return null;
    }
    const now = new Date().toISOString();
    entry.published = structuredClone(entry.draft);
    entry.publishedAt = now;
    entry.updatedAt = now;
    store.lastPublishedAt = now;
    store.contentVersion += 1;
    await this.save(store);
    return withWorkflowStatus(entry);
  }

  private async unpublishEntry(key: "tracks" | "skills", entryId: string) {
    const store = await this.load();
    const entry = store[key].find((item) => item.id === entryId);
    if (!entry) {
      return null;
    }
    const now = new Date().toISOString();
    entry.published = null;
    entry.publishedAt = null;
    entry.updatedAt = now;
    store.lastPublishedAt = now;
    store.contentVersion += 1;
    await this.save(store);
    return withWorkflowStatus(entry);
  }

  private async createInitialStore(): Promise<ContentStore> {
    if (!this.bootstrapSnapshotPath) {
      return emptyStore();
    }

    try {
      const raw = await fs.readFile(this.bootstrapSnapshotPath, "utf8");
      const payload = JSON.parse(raw) as {
        exportedAt?: string;
        tracks?: PlainObject[];
        skills?: PlainObject[];
      };
      const exportedAt = payload.exportedAt ?? new Date().toISOString();
      return {
        schemaVersion: 1,
        contentVersion: 1,
        lastPublishedAt: exportedAt,
        tracks: (payload.tracks ?? []).map((track) =>
          createPublishedEntry(track, exportedAt),
        ),
        skills: (payload.skills ?? []).map((skill) =>
          createPublishedEntry(skill, exportedAt),
        ),
      };
    } catch (error) {
      if (isMissingFileError(error)) {
        return emptyStore();
      }
      throw error;
    }
  }
}

export function toPublishedCatalog(
  store: ContentStore,
): PublishedCatalogSnapshot {
  return {
    tracks: store.tracks
      .filter((entry) => entry.published)
      .map((entry) => structuredClone(entry.published!)),
    skills: store.skills
      .filter((entry) => entry.published)
      .map((entry) => structuredClone(entry.published!)),
  };
}

export function withWorkflowStatus<T extends PlainObject>(entry: ManagedEntry<T>) {
  const draftChecksum = stableChecksum(entry.draft);
  const publishedChecksum = entry.published ? stableChecksum(entry.published) : "";
  const workflowStatus = !entry.published
    ? "draft"
    : draftChecksum === publishedChecksum
      ? "published"
      : "changes_pending";

  return {
    ...entry,
    workflowStatus,
  };
}

function createDraftEntry(payload: PlainObject): ManagedEntry<PlainObject> {
  const draft = sanitizePayload(payload);
  const now = new Date().toISOString();
  return {
    id: String(draft.id),
    draft,
    published: null,
    updatedAt: now,
    publishedAt: null,
  };
}

function createPublishedEntry(
  payload: PlainObject,
  publishedAt: string,
): ManagedEntry<PlainObject> {
  const sanitized = sanitizePayload(payload);
  return {
    id: String(sanitized.id),
    draft: structuredClone(sanitized),
    published: structuredClone(sanitized),
    updatedAt: publishedAt,
    publishedAt,
  };
}

function sanitizePayload(payload: PlainObject): PlainObject {
  if (!payload.id || String(payload.id).trim().length === 0) {
    throw new Error("Content entry must include a stable id.");
  }
  return JSON.parse(JSON.stringify(payload)) as PlainObject;
}

function normalizeStore(raw: Partial<ContentStore>): ContentStore {
  return {
    schemaVersion: 1,
    contentVersion: Number(raw.contentVersion ?? 1),
    lastPublishedAt: raw.lastPublishedAt ?? null,
    tracks: normalizeEntries(raw.tracks),
    skills: normalizeEntries(raw.skills),
  };
}

function normalizeEntries(
  entries: Partial<ManagedEntry<PlainObject>>[] | undefined,
): ManagedEntry<PlainObject>[] {
  return (entries ?? []).map((entry) => ({
    id: String(entry.id ?? entry.draft?.id ?? entry.published?.id ?? ""),
    draft: sanitizePayload((entry.draft ?? entry.published ?? {}) as PlainObject),
    published: entry.published ? sanitizePayload(entry.published as PlainObject) : null,
    updatedAt: entry.updatedAt ?? new Date().toISOString(),
    publishedAt: entry.publishedAt ?? null,
  }));
}

function emptyStore(): ContentStore {
  return {
    schemaVersion: 1,
    contentVersion: 1,
    lastPublishedAt: null,
    tracks: [],
    skills: [],
  };
}

function isMissingFileError(error: unknown) {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    (error as { code?: string }).code === "ENOENT"
  );
}

function stableChecksum(value: unknown) {
  return crypto.createHash("sha1").update(JSON.stringify(value)).digest("hex");
}
