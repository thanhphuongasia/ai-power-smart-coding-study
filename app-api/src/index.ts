import crypto from "node:crypto";
import path from "node:path";

import cors from "cors";
import express from "express";

import { ContentStoreRepository } from "./content-store.js";
import {
  applyLearnerEvent,
  buildInitialProjection,
  deriveDashboard,
  deriveReviewQueue,
  type ExerciseDefinition as ProjectionExerciseDefinition,
  type LearnerEventEnvelope,
  type SkillDefinition as ProjectionSkillDefinition,
  type TrackDefinition as ProjectionTrackDefinition,
} from "./projections.js";

type LearnerRecord = {
  learnerId: string;
  installId: string;
  accessToken: string;
  syncCursor: number;
  seenEventIds: Set<string>;
  events: LearnerEventEnvelope[];
};

type PlainObject = Record<string, unknown>;

export function createApp({
  contentStoreRepository = new ContentStoreRepository({
    storePath:
      process.env.CONTENT_STORE_PATH ||
      path.resolve(process.cwd(), "data/content-store.json"),
    bootstrapSnapshotPath:
      process.env.BOOTSTRAP_CATALOG_PATH ||
      path.resolve(process.cwd(), "../strapi/seed/seed_content.json"),
  }),
  adminApiKey = process.env.ADMIN_API_KEY || "local-dev-admin-key",
  previewApiKey = process.env.PREVIEW_API_KEY || adminApiKey,
} = {}) {
  const learnersByToken = new Map<string, LearnerRecord>();
  const learnersByInstallId = new Map<string, LearnerRecord>();

  const app = express();
  app.use(cors());
  app.use(express.json({ limit: "2mb" }));
  app.use("/admin", express.static(path.resolve(process.cwd(), "public/admin")));

  app.get("/health", async (_request, response) => {
    const catalog = await contentStoreRepository.listPublishedCatalog();
    response.json({
      ok: true,
      learners: learnersByInstallId.size,
      catalogTracks: catalog.tracks.length,
      catalogExercises: catalog.exercises.length,
      catalogSkills: catalog.skills.length,
      adminEnabled: true,
      schemaVersion: 2,
    });
  });

  app.post("/v1/anonymous/bootstrap", async (request, response) => {
    const installId = String(request.body?.install_id || "").trim();
    const deviceInfo = request.body?.device_info || {};
    if (!installId) {
      return response.status(400).json({ error: "install_id is required" });
    }

    let learner = learnersByInstallId.get(installId);
    if (!learner) {
      learner = {
        learnerId: crypto.randomUUID(),
        installId,
        accessToken: crypto.randomBytes(24).toString("hex"),
        syncCursor: 0,
        seenEventIds: new Set<string>(),
        events: [],
      };
      learnersByInstallId.set(installId, learner);
      learnersByToken.set(learner.accessToken, learner);
    }

    response.json({
      learner_id: learner.learnerId,
      access_token: learner.accessToken,
      sync_cursor: learner.syncCursor,
      device_info: deviceInfo,
    });
  });

  app.get("/v1/catalog/manifest", async (_request, response) => {
    const manifest = await contentStoreRepository.buildManifest();
    response.json({
      content_version: manifest.contentVersion,
      published_at: manifest.publishedAt,
      checksum: manifest.checksum,
    });
  });

  app.get(
    "/v1/catalog/manifest/preview",
    withPreviewAuth(previewApiKey),
    async (_request, response) => {
      const manifest = await contentStoreRepository.buildDraftManifest();
      response.json({
        content_version: manifest.contentVersion,
        published_at: manifest.publishedAt,
        checksum: manifest.checksum,
      });
    },
  );

  app.get("/v1/catalog", async (_request, response) => {
    response.json(await contentStoreRepository.listPublishedCatalog());
  });

  app.get("/v1/catalog/preview", withPreviewAuth(previewApiKey), async (_request, response) => {
    response.json(await contentStoreRepository.listDraftCatalog());
  });

  app.post("/v1/sync/events", async (request, response) => {
    const learner = requireLearner(learnersByToken, request.headers.authorization);
    if (!learner) {
      return response.status(401).json({ error: "Unauthorized" });
    }

    const catalog = await contentStoreRepository.listPublishedCatalog();
    const skills = catalog.skills.map((skill) => ({
      id: String(skill.id),
      title: String(skill.title ?? skill.id),
      description: String(skill.description ?? ""),
      reviewExerciseId: String(skill.reviewExerciseId ?? ""),
    }));

    let projection = buildInitialProjection(skills);
    for (const event of learner.events) {
      projection = applyLearnerEvent(projection, event);
    }

    const events = Array.isArray(request.body?.events) ? request.body.events : [];
    const acceptedClientEventIds: string[] = [];
    for (const rawEvent of events) {
      const clientEventId = String(rawEvent?.client_event_id || "").trim();
      const type = String(rawEvent?.type || "").trim() as LearnerEventEnvelope["type"];
      if (!clientEventId || !type || learner.seenEventIds.has(clientEventId)) {
        continue;
      }

      const event: LearnerEventEnvelope = {
        clientEventId,
        type,
        occurredAt: String(rawEvent?.occurred_at || new Date().toISOString()),
        payload:
          rawEvent && typeof rawEvent.payload === "object" && rawEvent.payload
            ? (rawEvent.payload as Record<string, unknown>)
            : {},
      };
      learner.events.push(event);
      learner.seenEventIds.add(clientEventId);
      projection = applyLearnerEvent(projection, event);
      learner.syncCursor += 1;
      acceptedClientEventIds.push(clientEventId);
    }

    response.json({
      accepted_client_event_ids: acceptedClientEventIds,
      sync_cursor: learner.syncCursor,
    });
  });

  app.get("/v1/me/progress", async (request, response) => {
    const learner = requireLearner(learnersByToken, request.headers.authorization);
    if (!learner) {
      return response.status(401).json({ error: "Unauthorized" });
    }

    const projection = await deriveLearnerProjection(contentStoreRepository, learner);
    const completedExerciseIds = Array.from(projection.completedExerciseIds);
    response.json({
      completed_exercise_ids: completedExerciseIds,
      completed_milestone_ids: completedExerciseIds,
      sync_cursor: learner.syncCursor,
    });
  });

  app.get("/v1/me/dashboard", async (request, response) => {
    const learner = requireLearner(learnersByToken, request.headers.authorization);
    if (!learner) {
      return response.status(401).json({ error: "Unauthorized" });
    }

    const catalog = await contentStoreRepository.listPublishedCatalog();
    const projection = await deriveLearnerProjection(contentStoreRepository, learner);
    response.json(
      deriveDashboard(
        projection,
        normalizeTracksForProjection(catalog.tracks),
        normalizeExercisesForProjection(catalog.exercises),
      ),
    );
  });

  app.get("/v1/me/review-queue", async (request, response) => {
    const learner = requireLearner(learnersByToken, request.headers.authorization);
    if (!learner) {
      return response.status(401).json({ error: "Unauthorized" });
    }

    const catalog = await contentStoreRepository.listPublishedCatalog();
    const projection = await deriveLearnerProjection(contentStoreRepository, learner);
    response.json({
      review_queue: deriveReviewQueue(
        projection,
        normalizeTracksForProjection(catalog.tracks),
        normalizeExercisesForProjection(catalog.exercises),
        normalizeSkillsForProjection(catalog.skills),
      ),
    });
  });

  app.get("/v1/me/skill-memory", async (request, response) => {
    const learner = requireLearner(learnersByToken, request.headers.authorization);
    if (!learner) {
      return response.status(401).json({ error: "Unauthorized" });
    }

    const projection = await deriveLearnerProjection(contentStoreRepository, learner);
    response.json({
      skill_memory: Object.fromEntries(projection.skillMemory.entries()),
    });
  });

  app.get("/admin/api/session", (_request, response) => {
    response.json({
      ok: true,
      authMode: "x-admin-key",
      schemaVersion: 2,
    });
  });

  app.get("/admin/api/catalog", withAdminAuth(adminApiKey), async (_request, response) => {
    response.json(await contentStoreRepository.listAdminCatalog());
  });

  bindAdminCrudRoutes(app, adminApiKey, "tracks", {
    create: (payload) => contentStoreRepository.createTrack(payload),
    update: (id, payload) => contentStoreRepository.updateTrack(id, payload),
    remove: (id) => contentStoreRepository.deleteTrack(id),
    publish: (id) => contentStoreRepository.publishTrack(id),
    unpublish: (id) => contentStoreRepository.unpublishTrack(id),
    label: "Track",
  });
  bindAdminCrudRoutes(app, adminApiKey, "exercises", {
    create: (payload) => contentStoreRepository.createExercise(payload),
    update: (id, payload) => contentStoreRepository.updateExercise(id, payload),
    remove: (id) => contentStoreRepository.deleteExercise(id),
    publish: (id) => contentStoreRepository.publishExercise(id),
    unpublish: (id) => contentStoreRepository.unpublishExercise(id),
    label: "Exercise",
  });
  bindAdminCrudRoutes(app, adminApiKey, "topics", {
    create: (payload) => contentStoreRepository.createTopic(payload),
    update: (id, payload) => contentStoreRepository.updateTopic(id, payload),
    remove: (id) => contentStoreRepository.deleteTopic(id),
    publish: (id) => contentStoreRepository.publishTopic(id),
    unpublish: (id) => contentStoreRepository.unpublishTopic(id),
    label: "Topic",
  });
  bindAdminCrudRoutes(app, adminApiKey, "domains", {
    create: (payload) => contentStoreRepository.createDomain(payload),
    update: (id, payload) => contentStoreRepository.updateDomain(id, payload),
    remove: (id) => contentStoreRepository.deleteDomain(id),
    publish: (id) => contentStoreRepository.publishDomain(id),
    unpublish: (id) => contentStoreRepository.unpublishDomain(id),
    label: "Domain",
  });
  bindAdminCrudRoutes(app, adminApiKey, "skills", {
    create: (payload) => contentStoreRepository.createSkill(payload),
    update: (id, payload) => contentStoreRepository.updateSkill(id, payload),
    remove: (id) => contentStoreRepository.deleteSkill(id),
    publish: (id) => contentStoreRepository.publishSkill(id),
    unpublish: (id) => contentStoreRepository.unpublishSkill(id),
    label: "Skill",
  });

  return app;
}

async function deriveLearnerProjection(
  contentStoreRepository: ContentStoreRepository,
  learner: LearnerRecord,
) {
  const catalog = await contentStoreRepository.listPublishedCatalog();
  const skills = normalizeSkillsForProjection(catalog.skills);
  let projection = buildInitialProjection(skills);
  for (const event of learner.events) {
    projection = applyLearnerEvent(projection, event);
  }
  return projection;
}

function bindAdminCrudRoutes(
  app: ReturnType<typeof express>,
  adminApiKey: string,
  collection: string,
  handlers: {
    create: (payload: PlainObject) => Promise<unknown>;
    update: (id: string, payload: PlainObject) => Promise<unknown>;
    remove: (id: string) => Promise<boolean>;
    publish: (id: string) => Promise<unknown>;
    unpublish: (id: string) => Promise<unknown>;
    label: string;
  },
) {
  app.post(`/admin/api/${collection}`, withAdminAuth(adminApiKey), async (request, response) => {
    try {
      const entry = await handlers.create(request.body);
      response.status(201).json(entry);
    } catch (error) {
      response.status(400).json({ error: toErrorMessage(error) });
    }
  });

  app.put(
    `/admin/api/${collection}/:entryId`,
    withAdminAuth(adminApiKey),
    async (request, response) => {
      try {
        const entry = await handlers.update(String(request.params.entryId), request.body);
        if (!entry) {
          return response.status(404).json({ error: `${handlers.label} not found` });
        }
        response.json(entry);
      } catch (error) {
        response.status(400).json({ error: toErrorMessage(error) });
      }
    },
  );

  app.delete(
    `/admin/api/${collection}/:entryId`,
    withAdminAuth(adminApiKey),
    async (request, response) => {
      const deleted = await handlers.remove(String(request.params.entryId));
      if (!deleted) {
        return response.status(404).json({ error: `${handlers.label} not found` });
      }
      response.status(204).send();
    },
  );

  app.post(
    `/admin/api/${collection}/:entryId/publish`,
    withAdminAuth(adminApiKey),
    async (request, response) => {
      const entry = await handlers.publish(String(request.params.entryId));
      if (!entry) {
        return response.status(404).json({ error: `${handlers.label} not found` });
      }
      response.json(entry);
    },
  );

  app.post(
    `/admin/api/${collection}/:entryId/unpublish`,
    withAdminAuth(adminApiKey),
    async (request, response) => {
      const entry = await handlers.unpublish(String(request.params.entryId));
      if (!entry) {
        return response.status(404).json({ error: `${handlers.label} not found` });
      }
      response.json(entry);
    },
  );
}

function withAdminAuth(adminApiKey: string) {
  return (
    request: express.Request,
    response: express.Response,
    next: express.NextFunction,
  ) => {
    const provided = String(request.headers["x-admin-key"] || "");
    if (!provided || provided !== adminApiKey) {
      return response.status(401).json({ error: "Unauthorized" });
    }
    next();
  };
}

function withPreviewAuth(previewApiKey: string) {
  return (
    request: express.Request,
    response: express.Response,
    next: express.NextFunction,
  ) => {
    const headerValue = String(request.headers["x-preview-key"] || "");
    const queryValue =
      typeof request.query?.preview_key === "string" ? request.query.preview_key : "";
    const provided = headerValue || queryValue;
    if (!provided || provided !== previewApiKey) {
      return response.status(401).json({ error: "Unauthorized" });
    }
    next();
  };
}

function requireLearner(
  learnersByToken: Map<string, LearnerRecord>,
  authorizationHeader: string | string[] | undefined,
) {
  const rawHeader = Array.isArray(authorizationHeader)
    ? authorizationHeader[0]
    : authorizationHeader;
  const token = String(rawHeader || "").replace(/^Bearer\s+/i, "").trim();
  if (!token) {
    return null;
  }
  return learnersByToken.get(token) ?? null;
}

function normalizeTracksForProjection(
  tracks: Array<Record<string, unknown>>,
): ProjectionTrackDefinition[] {
  return tracks.map((track) => ({
    id: String(track.id ?? ""),
    lane: normalizeLane(track.lane),
    exerciseRefs: Array.isArray(track.exerciseRefs)
      ? track.exerciseRefs
          .filter((item): item is Record<string, unknown> => typeof item === "object" && item !== null)
          .map((item) => ({
            exerciseId: String(item.exerciseId ?? ""),
          }))
      : [],
  }));
}

function normalizeExercisesForProjection(
  exercises: Array<Record<string, unknown>>,
): ProjectionExerciseDefinition[] {
  return exercises.map((exercise) => ({
    id: String(exercise.id ?? ""),
    lane: normalizeLane(exercise.lane),
  }));
}

function normalizeSkillsForProjection(
  skills: Array<Record<string, unknown>>,
): ProjectionSkillDefinition[] {
  return skills.map((skill) => ({
    id: String(skill.id ?? ""),
    title: String(skill.title ?? skill.id ?? ""),
    description: String(skill.description ?? ""),
    reviewExerciseId: String(skill.reviewExerciseId ?? skill.reviewMilestoneId ?? ""),
  }));
}

function normalizeLane(value: unknown): "project" | "dsa" | "leetcode" {
  const normalized = String(value ?? "").trim().toLowerCase();
  if (normalized === "leetcode") {
    return "leetcode";
  }
  if (normalized === "dsa" || normalized === "datastructure") {
    return "dsa";
  }
  return "project";
}

function toErrorMessage(error: unknown) {
  if (error instanceof Error) {
    return error.message;
  }
  return String(error);
}
