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
  type LearnerEventEnvelope,
  type TrackDefinition,
} from "./projections.js";

type LearnerRecord = {
  learnerId: string;
  installId: string;
  accessToken: string;
  syncCursor: number;
  seenEventIds: Set<string>;
  events: LearnerEventEnvelope[];
};

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
      catalogSkills: catalog.skills.length,
      adminEnabled: true,
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
      const catalog = await contentStoreRepository.listPublishedCatalog();
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

      for (const skill of catalog.skills) {
        if (!("id" in skill)) {
          continue;
        }
        void skill;
      }
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

  app.get("/v1/catalog", async (_request, response) => {
    const catalog = await contentStoreRepository.listPublishedCatalog();
    response.json(catalog);
  });

  app.post("/v1/sync/events", async (request, response) => {
    const learner = requireLearner(learnersByToken, request.headers.authorization);
    if (!learner) {
      return response.status(401).json({ error: "Unauthorized" });
    }

    const catalog = await contentStoreRepository.listPublishedCatalog();
    const skills = catalog.skills
      .filter((skill) => typeof skill.id === "string")
      .map((skill) => ({
        id: String(skill.id),
        title: String(skill.title ?? skill.id),
        description: String(skill.description ?? ""),
        reviewMilestoneId: String(skill.reviewMilestoneId ?? ""),
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
    response.json({
      completed_milestone_ids: Array.from(projection.completedMilestoneIds),
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
      deriveDashboard(projection, normalizeTracksForProjection(catalog.tracks)),
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
    });
  });

  app.get("/admin/api/catalog", withAdminAuth(adminApiKey), async (_request, response) => {
    response.json(await contentStoreRepository.listAdminCatalog());
  });

  app.post("/admin/api/tracks", withAdminAuth(adminApiKey), async (request, response) => {
    try {
      const entry = await contentStoreRepository.createTrack(request.body);
      response.status(201).json(entry);
    } catch (error) {
      response.status(400).json({ error: toErrorMessage(error) });
    }
  });

  app.put(
    "/admin/api/tracks/:trackId",
    withAdminAuth(adminApiKey),
    async (request, response) => {
      try {
        const entry = await contentStoreRepository.updateTrack(
          String(request.params.trackId),
          request.body,
        );
        if (!entry) {
          return response.status(404).json({ error: "Track not found" });
        }
        response.json(entry);
      } catch (error) {
        response.status(400).json({ error: toErrorMessage(error) });
      }
    },
  );

  app.delete(
    "/admin/api/tracks/:trackId",
    withAdminAuth(adminApiKey),
    async (request, response) => {
      const trackId = String(request.params.trackId);
      const deleted = await contentStoreRepository.deleteTrack(trackId);
      if (!deleted) {
        return response.status(404).json({ error: "Track not found" });
      }
      response.status(204).send();
    },
  );

  app.post(
    "/admin/api/tracks/:trackId/publish",
    withAdminAuth(adminApiKey),
    async (request, response) => {
      const entry = await contentStoreRepository.publishTrack(String(request.params.trackId));
      if (!entry) {
        return response.status(404).json({ error: "Track not found" });
      }
      response.json(entry);
    },
  );

  app.post(
    "/admin/api/tracks/:trackId/unpublish",
    withAdminAuth(adminApiKey),
    async (request, response) => {
      const entry = await contentStoreRepository.unpublishTrack(String(request.params.trackId));
      if (!entry) {
        return response.status(404).json({ error: "Track not found" });
      }
      response.json(entry);
    },
  );

  app.post("/admin/api/skills", withAdminAuth(adminApiKey), async (request, response) => {
    try {
      const entry = await contentStoreRepository.createSkill(request.body);
      response.status(201).json(entry);
    } catch (error) {
      response.status(400).json({ error: toErrorMessage(error) });
    }
  });

  app.put(
    "/admin/api/skills/:skillId",
    withAdminAuth(adminApiKey),
    async (request, response) => {
      try {
        const entry = await contentStoreRepository.updateSkill(
          String(request.params.skillId),
          request.body,
        );
        if (!entry) {
          return response.status(404).json({ error: "Skill not found" });
        }
        response.json(entry);
      } catch (error) {
        response.status(400).json({ error: toErrorMessage(error) });
      }
    },
  );

  app.delete(
    "/admin/api/skills/:skillId",
    withAdminAuth(adminApiKey),
    async (request, response) => {
      const deleted = await contentStoreRepository.deleteSkill(String(request.params.skillId));
      if (!deleted) {
        return response.status(404).json({ error: "Skill not found" });
      }
      response.status(204).send();
    },
  );

  app.post(
    "/admin/api/skills/:skillId/publish",
    withAdminAuth(adminApiKey),
    async (request, response) => {
      const entry = await contentStoreRepository.publishSkill(String(request.params.skillId));
      if (!entry) {
        return response.status(404).json({ error: "Skill not found" });
      }
      response.json(entry);
    },
  );

  app.post(
    "/admin/api/skills/:skillId/unpublish",
    withAdminAuth(adminApiKey),
    async (request, response) => {
      const entry = await contentStoreRepository.unpublishSkill(String(request.params.skillId));
      if (!entry) {
        return response.status(404).json({ error: "Skill not found" });
      }
      response.json(entry);
    },
  );

  return app;
}

async function deriveLearnerProjection(
  contentStoreRepository: ContentStoreRepository,
  learner: LearnerRecord,
) {
  const catalog = await contentStoreRepository.listPublishedCatalog();
  const projection = buildInitialProjection(normalizeSkillsForProjection(catalog.skills));
  return learner.events.reduce(
    (nextProjection, event) => applyLearnerEvent(nextProjection, event),
    projection,
  );
}

function requireLearner(
  learnersByToken: Map<string, LearnerRecord>,
  authorizationHeader: string | undefined,
) {
  const token = authorizationHeader?.replace(/^Bearer\s+/i, "") || "";
  return learnersByToken.get(token) || null;
}

function normalizeTracksForProjection(tracks: Record<string, unknown>[]): TrackDefinition[] {
  return tracks.map((track) => ({
    id: String(track.id ?? ""),
    type: normalizeTrackType(track.type),
    modules: Array.isArray(track.modules)
      ? track.modules.map((module) => ({
          id: String((module as Record<string, unknown>).id ?? ""),
          milestones: Array.isArray((module as Record<string, unknown>).milestones)
            ? ((module as Record<string, unknown>).milestones as Record<string, unknown>[]).map(
                (milestone) => ({
                  id: String(milestone.id ?? ""),
                  skillIds: Array.isArray(milestone.skillIds)
                    ? milestone.skillIds.map((skillId) => String(skillId))
                    : [],
                }),
              )
            : [],
        }))
      : [],
  }));
}

function normalizeSkillsForProjection(skills: Record<string, unknown>[]) {
  return skills.map((skill) => ({
    id: String(skill.id ?? ""),
    title: String(skill.title ?? skill.id ?? ""),
    description: String(skill.description ?? ""),
    reviewMilestoneId: String(skill.reviewMilestoneId ?? ""),
  }));
}

function normalizeTrackType(value: unknown) {
  return value === "dataStructure" || value === "leetcode" ? value : "project";
}

function withAdminAuth(adminApiKey: string) {
  return (
    request: express.Request,
    response: express.Response,
    next: express.NextFunction,
  ) => {
    const candidateKey =
      request.headers["x-admin-key"] ||
      request.headers.authorization?.replace(/^Bearer\s+/i, "");
    if (candidateKey !== adminApiKey) {
      return response.status(401).json({ error: "Invalid admin key" });
    }
    next();
  };
}

function toErrorMessage(error: unknown) {
  return error instanceof Error ? error.message : String(error);
}
