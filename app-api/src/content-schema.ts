type PlainObject = Record<string, unknown>;

export type LearningLane = "project" | "dsa" | "leetcode";
export type ContentLevel = "foundation" | "intermediate" | "advanced";
export type ContentKind =
  | "project_track"
  | "project_exercise"
  | "dsa_track"
  | "dsa_exercise"
  | "leetcode_set"
  | "leetcode_exercise";

export type WorkflowStatus = "draft" | "published" | "changes_pending";

export type ExecutionTestCase = {
  id: string;
  label: string;
  body: string;
  expectedOutput: string;
};

export type TaskStep = {
  id: string;
  title: string;
  description: string;
};

export type RequirementCheck = {
  label: string;
  pattern: string;
  feedback: string;
};

export type ExerciseLanguageVariant = {
  languageId: string;
  languageLabel: string;
  isDefault: boolean;
  starterCode: string;
  starterFiles: Record<string, string>;
  solutionCode: string | null;
  sandboxHarnessTemplate: string;
  runCommand: string;
  entryFilePath: string;
  demoFilePath: string | null;
  testCases: ExecutionTestCase[];
};

export type ExerciseDefinition = {
  id: string;
  title: string;
  summary: string;
  lane: LearningLane;
  contentKind: ContentKind;
  level: ContentLevel;
  topicIds: string[];
  domainIds: string[];
  tags: string[];
  skillIds: string[];
  problemStatement: string;
  acceptanceCriteria: string[];
  taskSteps: TaskStep[];
  supportedModes: string[];
  hints: Record<string, string>;
  reflectionPrompts: string[];
  requirements: RequirementCheck[];
  languageVariants: ExerciseLanguageVariant[];
};

export type TrackExerciseRef = {
  exerciseId: string;
  title?: string;
  summary?: string;
  milestoneLabel?: string;
};

export type TrackDefinition = {
  id: string;
  title: string;
  summary: string;
  lane: LearningLane;
  contentKind: ContentKind;
  level: ContentLevel;
  topicIds: string[];
  domainIds: string[];
  tags: string[];
  skillIds: string[];
  exerciseRefs: TrackExerciseRef[];
};

export type TopicDefinition = {
  id: string;
  title: string;
  summary: string;
};

export type DomainDefinition = {
  id: string;
  title: string;
  summary: string;
};

export type SkillDefinition = {
  id: string;
  title: string;
  category: string;
  description: string;
  reviewExerciseId: string;
};

export type PublishedCatalogSnapshot = {
  tracks: TrackDefinition[];
  exercises: ExerciseDefinition[];
  topics: TopicDefinition[];
  domains: DomainDefinition[];
  skills: SkillDefinition[];
  tagSuggestions: string[];
};

const laneKinds: Record<LearningLane, ContentKind[]> = {
  project: ["project_track", "project_exercise"],
  dsa: ["dsa_track", "dsa_exercise"],
  leetcode: ["leetcode_set", "leetcode_exercise"],
};

export const defaultSandboxHarnessTemplate = `{{USER_CODE}}

{{TEST_BODY}}
`;

export function validateTrackDefinition(input: PlainObject): TrackDefinition {
  const track = {
    id: readRequiredString(input.id, "Track id"),
    title: readRequiredString(input.title, "Track title"),
    summary: readString(input.summary),
    lane: readLane(input.lane),
    contentKind: readContentKind(input.contentKind),
    level: readLevel(input.level),
    topicIds: readStringList(input.topicIds),
    domainIds: readStringList(input.domainIds),
    tags: uniqueStrings(input.tags),
    skillIds: readStringList(input.skillIds),
    exerciseRefs: readTrackExerciseRefs(input.exerciseRefs),
  } satisfies TrackDefinition;

  ensureLaneMatchesKind(track.lane, track.contentKind);
  if (track.contentKind === "project_track" && track.exerciseRefs.length === 0) {
    throw new Error("Project tracks must include at least one ordered exercise ref.");
  }

  return track;
}

export function validateExerciseDefinition(input: PlainObject): ExerciseDefinition {
  const exercise = {
    id: readRequiredString(input.id, "Exercise id"),
    title: readRequiredString(input.title, "Exercise title"),
    summary: readString(input.summary),
    lane: readLane(input.lane),
    contentKind: readContentKind(input.contentKind),
    level: readLevel(input.level),
    topicIds: readStringList(input.topicIds),
    domainIds: readStringList(input.domainIds),
    tags: uniqueStrings(input.tags),
    skillIds: readStringList(input.skillIds),
    problemStatement: readString(input.problemStatement),
    acceptanceCriteria: readStringList(input.acceptanceCriteria),
    taskSteps: readTaskSteps(input.taskSteps),
    supportedModes: readStringList(input.supportedModes),
    hints: readStringRecord(input.hints),
    reflectionPrompts: readStringList(input.reflectionPrompts),
    requirements: readRequirementChecks(input.requirements),
    languageVariants: readLanguageVariants(input.languageVariants),
  } satisfies ExerciseDefinition;

  ensureLaneMatchesKind(exercise.lane, exercise.contentKind);
  if (exercise.languageVariants.length === 0) {
    throw new Error("Exercises must include at least one language variant.");
  }

  const defaultCount = exercise.languageVariants.filter((item) => item.isDefault).length;
  if (defaultCount !== 1) {
    throw new Error("Exercises must declare exactly one default language variant.");
  }

  if (
    exercise.lane === "leetcode" &&
    exercise.languageVariants.some((variant) => variant.testCases.length === 0)
  ) {
    throw new Error("LeetCode exercises must include testcase/judge config for every variant.");
  }

  return exercise;
}

export function validateTopicDefinition(input: PlainObject): TopicDefinition {
  return {
    id: readRequiredString(input.id, "Topic id"),
    title: readRequiredString(input.title, "Topic title"),
    summary: readString(input.summary),
  };
}

export function validateDomainDefinition(input: PlainObject): DomainDefinition {
  return {
    id: readRequiredString(input.id, "Domain id"),
    title: readRequiredString(input.title, "Domain title"),
    summary: readString(input.summary),
  };
}

export function validateSkillDefinition(input: PlainObject): SkillDefinition {
  return {
    id: readRequiredString(input.id, "Skill id"),
    title: readRequiredString(input.title, "Skill title"),
    category: readString(input.category),
    description: readString(input.description),
    reviewExerciseId: readRequiredString(
      input.reviewExerciseId ?? input.reviewMilestoneId,
      "Skill reviewExerciseId",
    ),
  };
}

export function deriveTagSuggestions(snapshot: Omit<PublishedCatalogSnapshot, "tagSuggestions">) {
  const values = new Set<string>();
  for (const track of snapshot.tracks) {
    for (const tag of track.tags) {
      values.add(tag);
    }
  }
  for (const exercise of snapshot.exercises) {
    for (const tag of exercise.tags) {
      values.add(tag);
    }
  }
  return Array.from(values).sort((left, right) => left.localeCompare(right));
}

export function readLane(value: unknown): LearningLane {
  const normalized = String(value ?? "")
    .trim()
    .toLowerCase();
  if (normalized === "project") {
    return "project";
  }
  if (normalized === "dsa" || normalized === "datastructure" || normalized === "datastructure") {
    return "dsa";
  }
  if (normalized === "leetcode") {
    return "leetcode";
  }
  throw new Error(`Unsupported lane "${String(value ?? "")}".`);
}

export function readContentKind(value: unknown): ContentKind {
  const normalized = String(value ?? "")
    .trim()
    .toLowerCase();
  const allowed: ContentKind[] = [
    "project_track",
    "project_exercise",
    "dsa_track",
    "dsa_exercise",
    "leetcode_set",
    "leetcode_exercise",
  ];
  if (allowed.includes(normalized as ContentKind)) {
    return normalized as ContentKind;
  }
  throw new Error(`Unsupported contentKind "${String(value ?? "")}".`);
}

export function readLevel(value: unknown): ContentLevel {
  const normalized = String(value ?? "")
    .trim()
    .toLowerCase();
  if (normalized === "foundation" || normalized === "intermediate" || normalized === "advanced") {
    return normalized;
  }
  throw new Error(`Unsupported level "${String(value ?? "")}".`);
}

export function toPlainObject<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

function ensureLaneMatchesKind(lane: LearningLane, kind: ContentKind) {
  if (!laneKinds[lane].includes(kind)) {
    throw new Error(`contentKind "${kind}" does not belong to lane "${lane}".`);
  }
}

function readLanguageVariants(value: unknown): ExerciseLanguageVariant[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value
    .filter(isPlainObject)
    .map((variant) => ({
      languageId: readRequiredString(variant.languageId, "languageId"),
      languageLabel: readRequiredString(variant.languageLabel, "languageLabel"),
      isDefault: variant.isDefault === true,
      starterCode: readString(variant.starterCode),
      starterFiles: readStringRecord(variant.starterFiles),
      solutionCode:
        variant.solutionCode == null ? null : String(variant.solutionCode),
      sandboxHarnessTemplate:
        readString(variant.sandboxHarnessTemplate) || defaultSandboxHarnessTemplate,
      runCommand: readString(variant.runCommand),
      entryFilePath: readRequiredString(variant.entryFilePath, "entryFilePath"),
      demoFilePath:
        variant.demoFilePath == null || String(variant.demoFilePath).trim().length === 0
          ? null
          : String(variant.demoFilePath),
      testCases: readExecutionTestCases(variant.testCases),
    }))
    .map((variant) => ({
      ...variant,
      starterFiles: {
        ...variant.starterFiles,
        [variant.entryFilePath]:
          variant.starterFiles[variant.entryFilePath] ?? variant.starterCode,
      },
    }));
}

function readExecutionTestCases(value: unknown): ExecutionTestCase[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value.filter(isPlainObject).map((item) => ({
    id: readRequiredString(item.id, "testCase id"),
    label: readRequiredString(item.label, "testCase label"),
    body: readString(item.body),
    expectedOutput: readString(item.expectedOutput),
  }));
}

function readTaskSteps(value: unknown): TaskStep[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value.filter(isPlainObject).map((item) => ({
    id: readRequiredString(item.id, "taskStep id"),
    title: readRequiredString(item.title, "taskStep title"),
    description: readString(item.description),
  }));
}

function readRequirementChecks(value: unknown): RequirementCheck[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value.filter(isPlainObject).map((item) => ({
    label: readRequiredString(item.label, "requirement label"),
    pattern: readRequiredString(item.pattern, "requirement pattern"),
    feedback: readString(item.feedback),
  }));
}

function readTrackExerciseRefs(value: unknown): TrackExerciseRef[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value.filter(isPlainObject).map((item) => ({
    exerciseId: readRequiredString(item.exerciseId, "track exerciseId"),
    title: readOptionalString(item.title),
    summary: readOptionalString(item.summary),
    milestoneLabel: readOptionalString(item.milestoneLabel),
  }));
}

function readStringRecord(value: unknown): Record<string, string> {
  if (!isPlainObject(value)) {
    return {};
  }
  return Object.fromEntries(
    Object.entries(value).map(([key, item]) => [key, String(item ?? "")]),
  );
}

function uniqueStrings(value: unknown) {
  return Array.from(new Set(readStringList(value)));
}

function readStringList(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return value.map((item) => String(item ?? "")).filter((item) => item.trim().length > 0);
}

function readRequiredString(value: unknown, label: string): string {
  const normalized = String(value ?? "").trim();
  if (normalized.length === 0) {
    throw new Error(`${label} is required.`);
  }
  return normalized;
}

function readString(value: unknown): string {
  return String(value ?? "");
}

function readOptionalString(value: unknown): string | undefined {
  const normalized = String(value ?? "").trim();
  return normalized.length === 0 ? undefined : normalized;
}

function isPlainObject(value: unknown): value is PlainObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
