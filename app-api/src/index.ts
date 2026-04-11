import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";

import cors from "cors";
import express from "express";

import {
  applyLearnerEvent,
  buildInitialProjection,
  deriveDashboard,
  deriveReviewQueue,
  type LearnerEventEnvelope,
  type LearnerProjection,
  type SkillDefinition,
  type TrackDefinition,
} from "./projections.js";

type CatalogSnapshot = {
  tracks: TrackDefinition[];
  skills: SkillDefinition[];
};

type LearnerRecord = {
  learnerId: string;
  installId: string;
  accessToken: string;
  syncCursor: number;
  seenEventIds: Set<string>;
  events: LearnerEventEnvelope[];
  projection: LearnerProjection;
};

const port = Number(process.env.PORT || 8788);
const catalogSnapshotPath =
  process.env.CATALOG_SNAPSHOT_PATH ||
  path.resolve(process.cwd(), "../strapi/seed/seed_content.json");

const learnersByToken = new Map<string, LearnerRecord>();
const learnersByInstallId = new Map<string, LearnerRecord>();

const app = express();
app.use(cors());
app.use(express.json({ limit: "1mb" }));

app.get("/health", async (_request, response) => {
  const catalog = await loadCatalogSnapshot();
  response.json({
    ok: true,
    learners: learnersByInstallId.size,
    catalogTracks: catalog.tracks.length,
    catalogSkills: catalog.skills.length,
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
    const catalog = await loadCatalogSnapshot();
    learner = {
      learnerId: crypto.randomUUID(),
      installId,
      accessToken: crypto.randomBytes(24).toString("hex"),
      syncCursor: 0,
      seenEventIds: new Set<string>(),
      events: [],
      projection: buildInitialProjection(catalog.skills),
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
  const rawCatalog = await fs.readFile(catalogSnapshotPath, "utf8");
  const payload = JSON.parse(rawCatalog) as Record<string, unknown>;
  response.json({
    content_version: String(payload.exportedAt || "0"),
    published_at: String(payload.exportedAt || new Date(0).toISOString()),
    checksum: crypto.createHash("sha256").update(rawCatalog).digest("hex"),
  });
});

app.get("/v1/catalog", async (_request, response) => {
  const catalog = await loadCatalogSnapshot();
  response.json({
    tracks: catalog.tracks,
    skills: catalog.skills,
  });
});

app.post("/v1/sync/events", async (request, response) => {
  const learner = requireLearner(request.headers.authorization);
  if (!learner) {
    return response.status(401).json({ error: "Unauthorized" });
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
    learner.projection = applyLearnerEvent(learner.projection, event);
    learner.syncCursor += 1;
    acceptedClientEventIds.push(clientEventId);
  }

  response.json({
    accepted_client_event_ids: acceptedClientEventIds,
    sync_cursor: learner.syncCursor,
  });
});

app.get("/v1/me/progress", async (request, response) => {
  const learner = requireLearner(request.headers.authorization);
  if (!learner) {
    return response.status(401).json({ error: "Unauthorized" });
  }

  response.json({
    completed_milestone_ids: Array.from(learner.projection.completedMilestoneIds),
    sync_cursor: learner.syncCursor,
  });
});

app.get("/v1/me/dashboard", async (request, response) => {
  const learner = requireLearner(request.headers.authorization);
  if (!learner) {
    return response.status(401).json({ error: "Unauthorized" });
  }

  const catalog = await loadCatalogSnapshot();
  response.json(deriveDashboard(learner.projection, catalog.tracks));
});

app.get("/v1/me/review-queue", async (request, response) => {
  const learner = requireLearner(request.headers.authorization);
  if (!learner) {
    return response.status(401).json({ error: "Unauthorized" });
  }

  const catalog = await loadCatalogSnapshot();
  response.json({
    review_queue: deriveReviewQueue(
      learner.projection,
      catalog.tracks,
      catalog.skills,
    ),
  });
});

app.get("/v1/me/skill-memory", async (request, response) => {
  const learner = requireLearner(request.headers.authorization);
  if (!learner) {
    return response.status(401).json({ error: "Unauthorized" });
  }

  response.json({
    skill_memory: Object.fromEntries(learner.projection.skillMemory.entries()),
  });
});

app.listen(port, () => {
  console.log(`App API listening on http://127.0.0.1:${port}`);
});

function requireLearner(authorizationHeader: string | undefined) {
  const token = authorizationHeader?.replace(/^Bearer\s+/i, "") || "";
  return learnersByToken.get(token) || null;
}

async function loadCatalogSnapshot(): Promise<CatalogSnapshot> {
  const rawCatalog = await fs.readFile(catalogSnapshotPath, "utf8");
  const payload = JSON.parse(rawCatalog) as Record<string, unknown>;
  return {
    tracks: Array.isArray(payload.tracks) ? (payload.tracks as TrackDefinition[]) : [],
    skills: Array.isArray(payload.skills) ? (payload.skills as SkillDefinition[]) : [],
  };
}
