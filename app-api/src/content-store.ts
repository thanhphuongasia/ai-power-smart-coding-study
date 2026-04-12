import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";

import {
  deriveTagSuggestions,
  toPlainObject,
  validateDomainDefinition,
  validateExerciseDefinition,
  validateSkillDefinition,
  validateTopicDefinition,
  validateTrackDefinition,
  type DomainDefinition,
  type ExerciseDefinition,
  type PublishedCatalogSnapshot,
  type SkillDefinition,
  type TopicDefinition,
  type TrackDefinition,
} from "./content-schema.js";

type PlainObject = Record<string, unknown>;
type CollectionKey = "tracks" | "exercises" | "topics" | "domains" | "skills";
type ValidationResultByCollection = {
  tracks: TrackDefinition;
  exercises: ExerciseDefinition;
  topics: TopicDefinition;
  domains: DomainDefinition;
  skills: SkillDefinition;
};

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
  tracks: ManagedEntry<TrackDefinition>[];
  exercises: ManagedEntry<ExerciseDefinition>[];
  topics: ManagedEntry<TopicDefinition>[];
  domains: ManagedEntry<DomainDefinition>[];
  skills: ManagedEntry<SkillDefinition>[];
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
    const publishedCatalog = toPublishedCatalog(store);
    return {
      schemaVersion: store.schemaVersion,
      contentVersion: store.contentVersion,
      lastPublishedAt: store.lastPublishedAt,
      tagSuggestions: publishedCatalog.tagSuggestions,
      tracks: store.tracks.map(withWorkflowStatus),
      exercises: store.exercises.map(withWorkflowStatus),
      topics: store.topics.map(withWorkflowStatus),
      domains: store.domains.map(withWorkflowStatus),
      skills: store.skills.map(withWorkflowStatus),
    };
  }

  async createTrack(track: PlainObject) {
    return this.createEntry("tracks", track);
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

  async createExercise(exercise: PlainObject) {
    return this.createEntry("exercises", exercise);
  }

  async updateExercise(exerciseId: string, exercise: PlainObject) {
    return this.updateEntry("exercises", exerciseId, exercise);
  }

  async deleteExercise(exerciseId: string) {
    return this.deleteEntry("exercises", exerciseId);
  }

  async publishExercise(exerciseId: string) {
    return this.publishEntry("exercises", exerciseId);
  }

  async unpublishExercise(exerciseId: string) {
    return this.unpublishEntry("exercises", exerciseId);
  }

  async createTopic(topic: PlainObject) {
    return this.createEntry("topics", topic);
  }

  async updateTopic(topicId: string, topic: PlainObject) {
    return this.updateEntry("topics", topicId, topic);
  }

  async deleteTopic(topicId: string) {
    return this.deleteEntry("topics", topicId);
  }

  async publishTopic(topicId: string) {
    return this.publishEntry("topics", topicId);
  }

  async unpublishTopic(topicId: string) {
    return this.unpublishEntry("topics", topicId);
  }

  async createDomain(domain: PlainObject) {
    return this.createEntry("domains", domain);
  }

  async updateDomain(domainId: string, domain: PlainObject) {
    return this.updateEntry("domains", domainId, domain);
  }

  async deleteDomain(domainId: string) {
    return this.deleteEntry("domains", domainId);
  }

  async publishDomain(domainId: string) {
    return this.publishEntry("domains", domainId);
  }

  async unpublishDomain(domainId: string) {
    return this.unpublishEntry("domains", domainId);
  }

  async createSkill(skill: PlainObject) {
    return this.createEntry("skills", skill);
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

  private async createEntry<K extends CollectionKey>(key: K, payload: PlainObject) {
    const store = await this.load();
    const entry = createDraftEntry(key, payload);
    store[key].push(entry as ContentStore[K][number]);
    await this.save(store);
    return withWorkflowStatus(entry);
  }

  private async updateEntry<K extends CollectionKey>(
    key: K,
    entryId: string,
    nextDraft: PlainObject,
  ) {
    const store = await this.load();
    const entry = store[key].find((item) => item.id === entryId);
    if (!entry) {
      return null;
    }
    entry.draft = sanitizePayload(key, nextDraft) as ValidationResultByCollection[K];
    entry.updatedAt = new Date().toISOString();
    await this.save(store);
    return withWorkflowStatus(entry);
  }

  private async deleteEntry(key: CollectionKey, entryId: string) {
    const store = await this.load();
    const before = store[key].length;
    store[key] = store[key].filter((item) => item.id !== entryId) as ContentStore[typeof key];
    if (store[key].length === before) {
      return false;
    }
    await this.save(store);
    return true;
  }

  private async publishEntry(key: CollectionKey, entryId: string) {
    const store = await this.load();
    const entry = store[key].find((item) => item.id === entryId);
    if (!entry) {
      return null;
    }
    const now = new Date().toISOString();
    entry.published = toPlainObject(entry.draft) as typeof entry.published;
    entry.publishedAt = now;
    entry.updatedAt = now;
    store.lastPublishedAt = now;
    store.contentVersion += 1;
    await this.save(store);
    return withWorkflowStatus(entry);
  }

  private async unpublishEntry(key: CollectionKey, entryId: string) {
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
      const payload = JSON.parse(raw) as Record<string, unknown>;
      return createStoreFromBootstrap(payload);
    } catch (error) {
      if (isMissingFileError(error)) {
        return emptyStore();
      }
      throw error;
    }
  }
}

export function toPublishedCatalog(store: ContentStore): PublishedCatalogSnapshot {
  const snapshot = {
    tracks: publishedEntries(store.tracks),
    exercises: publishedEntries(store.exercises),
    topics: publishedEntries(store.topics),
    domains: publishedEntries(store.domains),
    skills: publishedEntries(store.skills),
  };

  return {
    ...snapshot,
    tagSuggestions: deriveTagSuggestions(snapshot),
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

function createDraftEntry<K extends CollectionKey>(
  key: K,
  payload: PlainObject,
): ManagedEntry<ValidationResultByCollection[K]> {
  const draft = sanitizePayload(key, payload);
  const now = new Date().toISOString();
  return {
    id: draft.id,
    draft,
    published: null,
    updatedAt: now,
    publishedAt: null,
  };
}

function createPublishedEntry<K extends CollectionKey>(
  key: K,
  payload: PlainObject,
  publishedAt: string,
): ManagedEntry<ValidationResultByCollection[K]> {
  const sanitized = sanitizePayload(key, payload);
  return {
    id: sanitized.id,
    draft: toPlainObject(sanitized),
    published: toPlainObject(sanitized),
    updatedAt: publishedAt,
    publishedAt,
  };
}

function sanitizePayload<K extends CollectionKey>(
  key: K,
  payload: PlainObject,
): ValidationResultByCollection[K] {
  const cloned = toPlainObject(payload);
  switch (key) {
    case "tracks":
      return validateTrackDefinition(cloned) as ValidationResultByCollection[K];
    case "exercises":
      return validateExerciseDefinition(cloned) as ValidationResultByCollection[K];
    case "topics":
      return validateTopicDefinition(cloned) as ValidationResultByCollection[K];
    case "domains":
      return validateDomainDefinition(cloned) as ValidationResultByCollection[K];
    case "skills":
      return validateSkillDefinition(cloned) as ValidationResultByCollection[K];
  }
}

function normalizeStore(raw: Partial<ContentStore>): ContentStore {
  if ((raw.schemaVersion ?? 0) < 2) {
    return createStoreFromBootstrap(raw as Record<string, unknown>);
  }

  return {
    schemaVersion: 2,
    contentVersion: Number(raw.contentVersion ?? 1),
    lastPublishedAt: raw.lastPublishedAt ?? null,
    tracks: normalizeEntries("tracks", raw.tracks),
    exercises: normalizeEntries("exercises", raw.exercises),
    topics: normalizeEntries("topics", raw.topics),
    domains: normalizeEntries("domains", raw.domains),
    skills: normalizeEntries("skills", raw.skills),
  };
}

function normalizeEntries<K extends CollectionKey>(
  key: K,
  entries: Partial<ManagedEntry<ValidationResultByCollection[K]>>[] | undefined,
): ManagedEntry<ValidationResultByCollection[K]>[] {
  return (entries ?? []).map((entry) => ({
    id: String(entry.id ?? entry.draft?.id ?? entry.published?.id ?? ""),
    draft: sanitizePayload(
      key,
      (entry.draft ?? entry.published ?? {}) as PlainObject,
    ) as ValidationResultByCollection[K],
    published: entry.published
      ? (sanitizePayload(key, entry.published as PlainObject) as ValidationResultByCollection[K])
      : null,
    updatedAt: entry.updatedAt ?? new Date().toISOString(),
    publishedAt: entry.publishedAt ?? null,
  }));
}

function createStoreFromBootstrap(payload: Record<string, unknown>): ContentStore {
  const migrated = migrateBootstrapPayload(payload);
  const exportedAt = String(migrated.exportedAt ?? new Date().toISOString());
  return {
    schemaVersion: 2,
    contentVersion: Number(migrated.contentVersion ?? 1),
    lastPublishedAt: exportedAt,
    tracks: migrated.tracks.map((item) => createPublishedEntry("tracks", item, exportedAt)),
    exercises: migrated.exercises.map((item) =>
      createPublishedEntry("exercises", item, exportedAt),
    ),
    topics: migrated.topics.map((item) => createPublishedEntry("topics", item, exportedAt)),
    domains: migrated.domains.map((item) => createPublishedEntry("domains", item, exportedAt)),
    skills: migrated.skills.map((item) => createPublishedEntry("skills", item, exportedAt)),
  };
}

function migrateBootstrapPayload(payload: Record<string, unknown>) {
  const tracks = asPlainObjectArray(payload.tracks);
  const exercises = asPlainObjectArray(payload.exercises);
  const topics = asPlainObjectArray(payload.topics);
  const domains = asPlainObjectArray(payload.domains);
  const skills = asPlainObjectArray(payload.skills);

  if (exercises.length > 0 || topics.length > 0 || domains.length > 0) {
    return {
      exportedAt: payload.exportedAt ?? new Date().toISOString(),
      contentVersion: payload.contentVersion ?? 1,
      tracks,
      exercises,
      topics,
      domains,
      skills,
    };
  }

  return migrateLegacyV1Payload(payload);
}

function migrateLegacyV1Payload(payload: Record<string, unknown>) {
  const exportedAt = payload.exportedAt ?? new Date().toISOString();
  const skills = asPlainObjectArray(payload.skills).map((skill) => ({
    ...skill,
    reviewExerciseId: String(skill.reviewMilestoneId ?? skill.reviewExerciseId ?? ""),
  }));

  const exercises: PlainObject[] = [];
  const tracks: PlainObject[] = asPlainObjectArray(payload.tracks).map((track) => {
    const lane =
      String(track.type ?? "").toLowerCase() === "leetcode"
        ? "leetcode"
        : String(track.type ?? "").toLowerCase() === "datastructure"
          ? "dsa"
          : "project";
    const refs: PlainObject[] = [];
    const modules = Array.isArray(track.modules) ? track.modules : [];
    for (const module of modules) {
      if (typeof module !== "object" || module === null || !Array.isArray(module.milestones)) {
        continue;
      }
      for (const rawMilestone of module.milestones) {
        if (typeof rawMilestone !== "object" || rawMilestone === null) {
          continue;
        }
        const milestone = rawMilestone as PlainObject;
        const exerciseId = String(milestone.id ?? crypto.randomUUID());
        exercises.push({
          id: exerciseId,
          title: String(milestone.title ?? exerciseId),
          summary: String(milestone.objective ?? ""),
          lane,
          contentKind: lane === "leetcode" ? "leetcode_exercise" : lane === "dsa" ? "dsa_exercise" : "project_exercise",
          level: legacyDifficultyToLevel(track.difficultyLabel),
          topicIds: [],
          domainIds: [],
          tags: [],
          skillIds: Array.isArray(milestone.skillIds) ? milestone.skillIds : [],
          problemStatement: String(milestone.problemStatement ?? ""),
          acceptanceCriteria: Array.isArray(milestone.acceptanceCriteria)
            ? milestone.acceptanceCriteria
            : [],
          taskSteps: Array.isArray(milestone.taskSteps) ? milestone.taskSteps : [],
          supportedModes: Array.isArray(milestone.supportedModes) ? milestone.supportedModes : [],
          hints:
            typeof milestone.hints === "object" && milestone.hints !== null ? milestone.hints : {},
          reflectionPrompts: Array.isArray(milestone.reflectionPrompts)
            ? milestone.reflectionPrompts
            : [],
          requirements: Array.isArray(milestone.requirements) ? milestone.requirements : [],
          languageVariants: [
            {
              languageId: legacyLanguageId(milestone.languageLabel),
              languageLabel: String(milestone.languageLabel ?? "Python"),
              isDefault: true,
              starterCode: String(milestone.starterCode ?? ""),
              starterFiles:
                typeof milestone.starterFiles === "object" && milestone.starterFiles !== null
                  ? milestone.starterFiles
                  : {},
              solutionCode:
                milestone.solutionCode == null ? null : String(milestone.solutionCode),
              sandboxHarnessTemplate: String(
                milestone.sandboxHarnessTemplate ?? "{{USER_CODE}}\n\n{{TEST_BODY}}\n",
              ),
              runCommand: String(milestone.runCommand ?? "python main.py"),
              entryFilePath:
                String(milestone.sandboxEntryFilePath ?? "") ||
                firstRelatedFile(milestone.relatedFiles) ||
                "main.py",
              demoFilePath:
                milestone.demoFilePath == null ? null : String(milestone.demoFilePath),
              testCases: Array.isArray(milestone.testCases) ? milestone.testCases : [],
            },
          ],
        });
        refs.push({
          exerciseId,
          title: String(milestone.title ?? exerciseId),
          summary: String(milestone.objective ?? ""),
          milestoneLabel: String(module.title ?? ""),
        });
      }
    }

    return {
      id: String(track.id ?? crypto.randomUUID()),
      title: String(track.title ?? "Migrated track"),
      summary: String(track.summary ?? ""),
      lane,
      contentKind: lane === "leetcode" ? "leetcode_set" : lane === "dsa" ? "dsa_track" : "project_track",
      level: legacyDifficultyToLevel(track.difficultyLabel),
      topicIds: [],
      domainIds: [],
      tags: [],
      skillIds: [],
      exerciseRefs: refs,
    };
  });

  return {
    exportedAt,
    contentVersion: 1,
    tracks,
    exercises,
    topics: [],
    domains: [],
    skills,
  };
}

function publishedEntries<T extends PlainObject>(entries: ManagedEntry<T>[]) {
  return entries
    .filter((entry) => entry.published)
    .map((entry) => toPlainObject(entry.published!));
}

function asPlainObjectArray(value: unknown): PlainObject[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value.filter((item): item is PlainObject => typeof item === "object" && item !== null);
}

function legacyDifficultyToLevel(value: unknown) {
  const normalized = String(value ?? "").toLowerCase();
  if (normalized.includes("advanced")) {
    return "advanced";
  }
  if (normalized.includes("intermediate") || normalized.includes("interview")) {
    return "intermediate";
  }
  return "foundation";
}

function legacyLanguageId(value: unknown) {
  const normalized = String(value ?? "python").trim().toLowerCase();
  if (normalized === "c#" || normalized === "csharp") {
    return "csharp";
  }
  if (normalized === "typescript") {
    return "typescript";
  }
  if (normalized === "java") {
    return "java";
  }
  return normalized || "python";
}

function firstRelatedFile(value: unknown) {
  if (!Array.isArray(value) || value.length === 0) {
    return "";
  }
  return String(value[0] ?? "");
}

function emptyStore(): ContentStore {
  return {
    schemaVersion: 2,
    contentVersion: 1,
    lastPublishedAt: null,
    tracks: [],
    exercises: [],
    topics: [],
    domains: [],
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
