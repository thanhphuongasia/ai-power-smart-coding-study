export type SkillRecord = {
  skillId: string;
  masteryScore: number;
  confidenceScore: number;
  hintDependence: number;
  failureCount: number;
  lastOutcome: string;
};

export type LearnerProjection = {
  completedMilestoneIds: Set<string>;
  skillMemory: Map<string, SkillRecord>;
};

export type LearnerEventEnvelope = {
  clientEventId: string;
  type:
    | "sessionStarted"
    | "hintRevealed"
    | "checkPassed"
    | "checkFailed"
    | "sandboxBuild"
    | "sandboxRun"
    | "milestoneCompleted";
  occurredAt: string;
  payload: Record<string, unknown>;
};

export type SkillDefinition = {
  id: string;
  title: string;
  description: string;
  reviewMilestoneId: string;
};

export type TrackDefinition = {
  id: string;
  type: "project" | "dataStructure" | "leetcode";
  modules: Array<{
    id: string;
    milestones: Array<{
      id: string;
      skillIds: string[];
    }>;
  }>;
};

export function buildInitialProjection(skills: SkillDefinition[]): LearnerProjection {
  return {
    completedMilestoneIds: new Set<string>(),
    skillMemory: new Map<string, SkillRecord>(
      skills.map((skill) => [
        skill.id,
        {
          skillId: skill.id,
          masteryScore: 0.5,
          confidenceScore: 0.5,
          hintDependence: 0,
          failureCount: 0,
          lastOutcome: "Waiting for the first synced attempt.",
        },
      ]),
    ),
  };
}

export function applyLearnerEvent(
  projection: LearnerProjection,
  event: LearnerEventEnvelope,
): LearnerProjection {
  const next: LearnerProjection = {
    completedMilestoneIds: new Set(projection.completedMilestoneIds),
    skillMemory: new Map(
      Array.from(projection.skillMemory.entries()).map(([skillId, record]) => [
        skillId,
        { ...record },
      ]),
    ),
  };

  const skillIds = readStringList(event.payload["skill_ids"]);
  if (event.type === "hintRevealed") {
    for (const skillId of skillIds) {
      const record = next.skillMemory.get(skillId);
      if (!record) {
        continue;
      }
      record.hintDependence = clamp(record.hintDependence + 0.05);
      record.lastOutcome = `Needed ${String(event.payload["hint_level"] || "hint")}`;
    }
    return next;
  }

  if (event.type === "checkPassed") {
    const milestoneId = String(event.payload["milestone_id"] || "");
    if (milestoneId) {
      next.completedMilestoneIds.add(milestoneId);
    }
    for (const skillId of skillIds) {
      const record = next.skillMemory.get(skillId);
      if (!record) {
        continue;
      }
      record.masteryScore = clamp(record.masteryScore + 0.08);
      record.confidenceScore = clamp(record.confidenceScore + 0.07);
      record.hintDependence = clamp(record.hintDependence - 0.04);
      record.lastOutcome = `Passed ${milestoneId}`;
    }
    return next;
  }

  if (event.type === "checkFailed") {
    const milestoneId = String(event.payload["milestone_id"] || "");
    for (const skillId of skillIds) {
      const record = next.skillMemory.get(skillId);
      if (!record) {
        continue;
      }
      record.masteryScore = clamp(record.masteryScore - 0.03);
      record.confidenceScore = clamp(record.confidenceScore - 0.02);
      record.failureCount += 1;
      record.lastOutcome = `Missed part of ${milestoneId}`;
    }
  }

  if (event.type === "milestoneCompleted") {
    const milestoneId = String(event.payload["milestone_id"] || "");
    if (milestoneId) {
      next.completedMilestoneIds.add(milestoneId);
    }
  }

  return next;
}

export function deriveDashboard(
  projection: LearnerProjection,
  tracks: TrackDefinition[],
) {
  const averageMastery =
    projection.skillMemory.size === 0
      ? 0
      : Array.from(projection.skillMemory.values()).reduce(
          (sum, record) => sum + record.masteryScore,
          0,
        ) / projection.skillMemory.size;

  const projectMilestones = new Set<string>();
  for (const track of tracks) {
    if (track.type !== "project") {
      continue;
    }
    for (const module of track.modules) {
      for (const milestone of module.milestones) {
        projectMilestones.add(milestone.id);
      }
    }
  }

  let completedProjects = 0;
  for (const milestoneId of projection.completedMilestoneIds) {
    if (projectMilestones.has(milestoneId)) {
      completedProjects += 1;
    }
  }

  return {
    completedProjects,
    completedDsAlgo: projection.completedMilestoneIds.size - completedProjects,
    reviewQueueCount: deriveReviewQueue(projection, tracks).length,
    averageMastery,
  };
}

export function deriveReviewQueue(
  projection: LearnerProjection,
  tracks: TrackDefinition[],
  skills: SkillDefinition[] = [],
) {
  const milestoneLane = new Map<string, string>();
  for (const track of tracks) {
    for (const module of track.modules) {
      for (const milestone of module.milestones) {
        milestoneLane.set(milestone.id, track.type);
      }
    }
  }

  return skills
    .map((skill) => {
      const record = projection.skillMemory.get(skill.id);
      if (!record) {
        return null;
      }
      if (record.masteryScore >= 0.58 && record.failureCount < 3) {
        return null;
      }
      return {
        id: `review_${skill.id}`,
        title: `Review ${skill.title}`,
        description: `${skill.description} ${record.lastOutcome}`,
        skillIds: [skill.id],
        milestoneId: skill.reviewMilestoneId,
        laneLabel: milestoneLane.get(skill.reviewMilestoneId) || "project",
      };
    })
    .filter(Boolean);
}

function clamp(value: number) {
  return Math.min(1, Math.max(0, value));
}

function readStringList(value: unknown): string[] {
  return Array.isArray(value) ? value.map((item) => String(item)) : [];
}
