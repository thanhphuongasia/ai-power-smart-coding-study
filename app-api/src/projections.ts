export type SkillRecord = {
  skillId: string;
  masteryScore: number;
  confidenceScore: number;
  hintDependence: number;
  failureCount: number;
  lastOutcome: string;
};

export type LearnerProjection = {
  completedExerciseIds: Set<string>;
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
  reviewExerciseId: string;
};

export type TrackDefinition = {
  id: string;
  lane: "project" | "dsa" | "leetcode";
  exerciseRefs: Array<{
    exerciseId: string;
  }>;
};

export type ExerciseDefinition = {
  id: string;
  lane: "project" | "dsa" | "leetcode";
};

export function buildInitialProjection(skills: SkillDefinition[]): LearnerProjection {
  return {
    completedExerciseIds: new Set<string>(),
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
    completedExerciseIds: new Set(projection.completedExerciseIds),
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
    const exerciseId = readExerciseId(event.payload);
    if (exerciseId) {
      next.completedExerciseIds.add(exerciseId);
    }
    for (const skillId of skillIds) {
      const record = next.skillMemory.get(skillId);
      if (!record) {
        continue;
      }
      record.masteryScore = clamp(record.masteryScore + 0.08);
      record.confidenceScore = clamp(record.confidenceScore + 0.07);
      record.hintDependence = clamp(record.hintDependence - 0.04);
      record.lastOutcome = `Passed ${exerciseId}`;
    }
    return next;
  }

  if (event.type === "checkFailed") {
    const exerciseId = readExerciseId(event.payload);
    for (const skillId of skillIds) {
      const record = next.skillMemory.get(skillId);
      if (!record) {
        continue;
      }
      record.masteryScore = clamp(record.masteryScore - 0.03);
      record.confidenceScore = clamp(record.confidenceScore - 0.02);
      record.failureCount += 1;
      record.lastOutcome = `Missed part of ${exerciseId}`;
    }
  }

  if (event.type === "milestoneCompleted") {
    const exerciseId = readExerciseId(event.payload);
    if (exerciseId) {
      next.completedExerciseIds.add(exerciseId);
    }
  }

  return next;
}

export function deriveDashboard(
  projection: LearnerProjection,
  tracks: TrackDefinition[],
  exercises: ExerciseDefinition[],
) {
  const averageMastery =
    projection.skillMemory.size === 0
      ? 0
      : Array.from(projection.skillMemory.values()).reduce(
          (sum, record) => sum + record.masteryScore,
          0,
        ) / projection.skillMemory.size;

  const exerciseLane = new Map(exercises.map((exercise) => [exercise.id, exercise.lane]));
  let completedProjects = 0;
  for (const exerciseId of projection.completedExerciseIds) {
    if (exerciseLane.get(exerciseId) === "project") {
      completedProjects += 1;
    }
  }

  void tracks;

  return {
    completedProjects,
    completedDsAlgo: projection.completedExerciseIds.size - completedProjects,
    reviewQueueCount: deriveReviewQueue(projection, tracks, exercises).length,
    averageMastery,
  };
}

export function deriveReviewQueue(
  projection: LearnerProjection,
  tracks: TrackDefinition[],
  exercises: ExerciseDefinition[],
  skills: SkillDefinition[] = [],
) {
  const exerciseLane = new Map(exercises.map((exercise) => [exercise.id, exercise.lane]));
  void tracks;

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
        exerciseId: skill.reviewExerciseId,
        laneLabel: exerciseLane.get(skill.reviewExerciseId) || "project",
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

function readExerciseId(payload: Record<string, unknown>) {
  return String(payload["exercise_id"] || payload["milestone_id"] || "");
}
