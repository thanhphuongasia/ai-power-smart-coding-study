const DEFAULT_ADMIN_KEY = "local-dev-admin-key";
const ENTITY_KEYS = ["tracks", "exercises", "topics", "domains", "skills"];

const state = {
  adminKey: localStorage.getItem("adminKey") || DEFAULT_ADMIN_KEY,
  catalog: null,
  selectedKind: "tracks",
  selectedId: null,
  searchQuery: "",
  laneFilter: "",
  levelFilter: "",
  statusFilter: "",
};

const dom = {
  adminKey: document.getElementById("admin-key"),
  authStatus: document.getElementById("auth-status"),
  connectionIndicator: document.getElementById("connection-indicator"),
  connectButton: document.getElementById("connect-button"),
  searchInput: document.getElementById("search-input"),
  laneFilter: document.getElementById("lane-filter"),
  levelFilter: document.getElementById("level-filter"),
  statusFilter: document.getElementById("status-filter"),
  entityList: document.getElementById("entity-list"),
  entityCountPill: document.getElementById("entity-count-pill"),
  editorTitle: document.getElementById("editor-title"),
  editorMeta: document.getElementById("editor-meta"),
  editorKindBadge: document.getElementById("editor-kind-badge"),
  editorTextarea: document.getElementById("editor-textarea"),
  saveButton: document.getElementById("save-button"),
  publishButton: document.getElementById("publish-button"),
  unpublishButton: document.getElementById("unpublish-button"),
  deleteButton: document.getElementById("delete-button"),
  refreshButton: document.getElementById("refresh-button"),
  newTrackButton: document.getElementById("new-track-button"),
  newExerciseButton: document.getElementById("new-exercise-button"),
  newTopicButton: document.getElementById("new-topic-button"),
  newDomainButton: document.getElementById("new-domain-button"),
  newSkillButton: document.getElementById("new-skill-button"),
  lastPublishedValue: document.getElementById("last-published-value"),
  contentVersionValue: document.getElementById("content-version-value"),
  pendingCountValue: document.getElementById("pending-count-value"),
  tracksCountValue: document.getElementById("tracks-count-value"),
  exercisesCountValue: document.getElementById("exercises-count-value"),
  taxonomyCountValue: document.getElementById("taxonomy-count-value"),
  publishedCountValue: document.getElementById("published-count-value"),
  selectionStatusPill: document.getElementById("selection-status-pill"),
  selectionHeading: document.getElementById("selection-heading"),
  selectionSummary: document.getElementById("selection-summary"),
  selectionAttributes: document.getElementById("selection-attributes"),
  selectionStructure: document.getElementById("selection-structure"),
  itemTemplate: document.getElementById("entity-item-template"),
  entityTabs: Array.from(document.querySelectorAll("[data-entity-tab]")),
};

dom.adminKey.value = state.adminKey;
dom.editorTextarea.disabled = true;
updateEditorActions();

dom.connectButton.addEventListener("click", () => runAction(connect));
dom.refreshButton.addEventListener("click", () => runAction(refreshCatalog));
dom.newTrackButton.addEventListener("click", () => runAction(() => createEntry("tracks")));
dom.newExerciseButton.addEventListener("click", () => runAction(() => createEntry("exercises")));
dom.newTopicButton.addEventListener("click", () => runAction(() => createEntry("topics")));
dom.newDomainButton.addEventListener("click", () => runAction(() => createEntry("domains")));
dom.newSkillButton.addEventListener("click", () => runAction(() => createEntry("skills")));
dom.saveButton.addEventListener("click", () => runAction(saveSelectedEntry));
dom.publishButton.addEventListener("click", () => runAction(() => publishSelectedEntry("publish")));
dom.unpublishButton.addEventListener("click", () => runAction(() => publishSelectedEntry("unpublish")));
dom.deleteButton.addEventListener("click", () => runAction(deleteSelectedEntry));
dom.searchInput.addEventListener("input", (event) => {
  state.searchQuery = event.target.value.trim().toLowerCase();
  renderLists();
});
dom.laneFilter.addEventListener("change", (event) => {
  state.laneFilter = event.target.value;
  renderLists();
});
dom.levelFilter.addEventListener("change", (event) => {
  state.levelFilter = event.target.value;
  renderLists();
});
dom.statusFilter.addEventListener("change", (event) => {
  state.statusFilter = event.target.value;
  renderLists();
});
dom.adminKey.addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    event.preventDefault();
    void runAction(connect);
  }
});
for (const button of dom.entityTabs) {
  button.addEventListener("click", () => {
    state.selectedKind = button.dataset.entityTab;
    state.selectedId = null;
    updateTabSelection();
    renderLists();
    clearSelection();
    autoSelectFirst();
  });
}

if (state.adminKey) {
  void runAction(connect);
}

async function runAction(action) {
  try {
    await action();
  } catch (error) {
    setStatus(error.message, { tone: "error" });
  }
}

async function connect() {
  state.adminKey = dom.adminKey.value.trim() || DEFAULT_ADMIN_KEY;
  dom.adminKey.value = state.adminKey;
  localStorage.setItem("adminKey", state.adminKey);
  await refreshCatalog();
}

async function refreshCatalog() {
  const catalog = await api("/admin/api/catalog");
  state.catalog = catalog;
  updateTabSelection();
  renderOverview();
  renderLists();
  autoSelectFirst();
  updateEditorActions();
  setStatus(
    `Connected to catalog v${catalog.contentVersion}. ${catalog.tracks.length} tracks, ${catalog.exercises.length} exercises, and ${catalog.skills.length} skills.`,
    { tone: "success" },
  );
}

function renderOverview() {
  const catalog = state.catalog;
  const entries = allEntries();
  const publishedCount = entries.filter((item) => item.workflowStatus === "published").length;
  const pendingCount = entries.filter((item) => item.workflowStatus === "changes_pending").length;

  dom.lastPublishedValue.textContent = formatDateTime(catalog?.lastPublishedAt, "Never");
  dom.contentVersionValue.textContent = catalog ? String(catalog.contentVersion) : "—";
  dom.pendingCountValue.textContent = String(pendingCount);
  dom.tracksCountValue.textContent = String(catalog?.tracks?.length || 0);
  dom.exercisesCountValue.textContent = String(catalog?.exercises?.length || 0);
  dom.taxonomyCountValue.textContent = String(
    (catalog?.topics?.length || 0) + (catalog?.domains?.length || 0) + (catalog?.skills?.length || 0),
  );
  dom.publishedCountValue.textContent = String(publishedCount);
}

function renderLists() {
  const items = currentEntries().filter((item) => matchesFilters(item));
  dom.entityCountPill.textContent = String(items.length);
  dom.entityList.replaceChildren();

  if (items.length === 0) {
    const emptyState = document.createElement("div");
    emptyState.className = "entity-item empty-state";
    emptyState.textContent = "No entries match the current filters.";
    dom.entityList.appendChild(emptyState);
    return;
  }

  for (const item of items) {
    const fragment = dom.itemTemplate.content.cloneNode(true);
    const button = fragment.querySelector(".entity-item");
    const title = fragment.querySelector(".entity-title");
    const summary = fragment.querySelector(".entity-summary");
    const itemKind = fragment.querySelector(".entity-kind");
    const status = fragment.querySelector(".entity-status");

    title.textContent = item.draft.title || item.id;
    summary.textContent = describeItem(state.selectedKind, item);
    itemKind.textContent = entityBadgeForItem(state.selectedKind, item);
    status.textContent = humanizeValue(item.workflowStatus);
    status.classList.add(`status-${item.workflowStatus}`);

    if (state.selectedId === item.id) {
      button.classList.add("active");
    }

    button.addEventListener("click", () => selectEntry(state.selectedKind, item.id));
    dom.entityList.appendChild(fragment);
  }
}

function selectEntry(kind, id) {
  state.selectedKind = kind;
  state.selectedId = id;
  updateTabSelection();
  renderLists();
  const item = findSelectedEntry();
  if (!item) {
    clearSelection();
    return;
  }

  dom.editorTitle.textContent = `${entityLabel(kind)} · ${item.draft.title || item.id}`;
  dom.editorMeta.textContent = [
    `ID: ${item.id}`,
    `Workflow: ${humanizeValue(item.workflowStatus)}`,
    `Updated: ${formatDateTime(item.updatedAt)}`,
    `Published: ${formatDateTime(item.publishedAt, "Not yet")}`,
  ].join(" · ");
  dom.editorKindBadge.textContent = `${entityLabel(kind)} JSON`;
  dom.editorTextarea.value = JSON.stringify(item.draft, null, 2);
  dom.editorTextarea.disabled = false;
  dom.selectionStatusPill.textContent = humanizeValue(item.workflowStatus);
  dom.selectionStatusPill.className = `pill status-${item.workflowStatus}`;
  renderSelectionDetails(kind, item);
  updateEditorActions();
}

function clearSelection() {
  state.selectedId = null;
  dom.editorTitle.textContent = "Select an entry";
  dom.editorMeta.textContent = "Choose an entity to inspect or update.";
  dom.editorKindBadge.textContent = "No selection";
  dom.editorTextarea.value = "";
  dom.editorTextarea.disabled = true;
  dom.selectionStatusPill.textContent = "Idle";
  dom.selectionStatusPill.className = "pill subtle-pill";
  dom.selectionHeading.textContent = "Nothing selected";
  dom.selectionSummary.textContent = "Pick a track, exercise, topic, domain, or skill to inspect the live draft JSON.";
  dom.selectionAttributes.replaceChildren(createAttributeRow("Status", "—"), createAttributeRow("Published", "—"));
  dom.selectionStructure.textContent = "No structure details yet.";
  updateEditorActions();
}

function renderSelectionDetails(kind, item) {
  dom.selectionHeading.textContent = item.draft.title || item.id;
  dom.selectionSummary.textContent =
    item.draft.summary || item.draft.description || "No summary added yet.";

  const attributes = [
    ["Type", entityBadgeForItem(kind, item)],
    ["Workflow", humanizeValue(item.workflowStatus)],
    ["Lane", item.draft.lane || "—"],
    ["Level", item.draft.level || "—"],
    ["Published", formatDateTime(item.publishedAt, "Not yet")],
  ];
  dom.selectionAttributes.replaceChildren(
    ...attributes.map(([label, value]) => createAttributeRow(label, value)),
  );

  dom.selectionStructure.replaceChildren(...buildStructure(kind, item.draft));
}

function buildStructure(kind, draft) {
  if (kind === "tracks") {
    const refs = Array.isArray(draft.exerciseRefs) ? draft.exerciseRefs : [];
    return [
      createStructureChip("Exercise refs", `${refs.length} linked`),
      ...refs.slice(0, 4).map((ref) =>
        createStructureChip(ref.title || ref.exerciseId || "Exercise", ref.milestoneLabel || "Ordered ref"),
      ),
    ];
  }
  if (kind === "exercises") {
    const variants = Array.isArray(draft.languageVariants) ? draft.languageVariants : [];
    return [
      createStructureChip("Variants", `${variants.length} languages`),
      ...variants.slice(0, 4).map((variant) =>
        createStructureChip(variant.languageLabel || variant.languageId || "Language", variant.runCommand || "No run command"),
      ),
    ];
  }
  if (kind === "skills") {
    return [
      createStructureChip("Review exercise", draft.reviewExerciseId || "Not linked"),
      createStructureChip("Category", humanizeValue(draft.category || "skill")),
    ];
  }
  return [createStructureChip("Entry id", draft.id || "—")];
}

async function createEntry(kind) {
  const payload = defaultDraftFor(kind);
  const created = await api(`/admin/api/${kind}`, {
    method: "POST",
    body: JSON.stringify(payload),
  });
  await refreshCatalog();
  selectEntry(kind, created.id);
}

async function saveSelectedEntry() {
  const item = findSelectedEntry();
  if (!item) {
    throw new Error("Pick an entry before saving.");
  }
  const payload = parseEditorJson();
  await api(`/admin/api/${state.selectedKind}/${item.id}`, {
    method: "PUT",
    body: JSON.stringify(payload),
  });
  await refreshCatalog();
  selectEntry(state.selectedKind, payload.id || item.id);
}

async function publishSelectedEntry(action) {
  const item = findSelectedEntry();
  if (!item) {
    throw new Error("Pick an entry before publishing.");
  }
  await api(`/admin/api/${state.selectedKind}/${item.id}/${action}`, {
    method: "POST",
  });
  await refreshCatalog();
  selectEntry(state.selectedKind, item.id);
}

async function deleteSelectedEntry() {
  const item = findSelectedEntry();
  if (!item) {
    throw new Error("Pick an entry before deleting.");
  }
  await api(`/admin/api/${state.selectedKind}/${item.id}`, {
    method: "DELETE",
  });
  await refreshCatalog();
}

function parseEditorJson() {
  try {
    return JSON.parse(dom.editorTextarea.value);
  } catch (error) {
    throw new Error(`Editor JSON is invalid: ${error.message}`);
  }
}

function currentEntries() {
  if (!state.catalog) {
    return [];
  }
  return state.catalog[state.selectedKind] || [];
}

function allEntries() {
  if (!state.catalog) {
    return [];
  }
  return ENTITY_KEYS.flatMap((key) => state.catalog[key] || []);
}

function matchesFilters(item) {
  if (state.statusFilter && item.workflowStatus !== state.statusFilter) {
    return false;
  }
  if (state.laneFilter && String(item.draft.lane || "") !== state.laneFilter) {
    return false;
  }
  if (state.levelFilter && String(item.draft.level || "") !== state.levelFilter) {
    return false;
  }
  if (!state.searchQuery) {
    return true;
  }

  const haystack = JSON.stringify(item.draft).toLowerCase();
  return haystack.includes(state.searchQuery) || String(item.id).toLowerCase().includes(state.searchQuery);
}

function findSelectedEntry() {
  return currentEntries().find((item) => item.id === state.selectedId) || null;
}

function autoSelectFirst() {
  if (state.selectedId) {
    const existing = findSelectedEntry();
    if (existing) {
      selectEntry(state.selectedKind, state.selectedId);
      return;
    }
  }

  const first = currentEntries().find((item) => matchesFilters(item));
  if (first) {
    selectEntry(state.selectedKind, first.id);
  } else {
    clearSelection();
  }
}

function updateTabSelection() {
  for (const button of dom.entityTabs) {
    button.classList.toggle("active", button.dataset.entityTab === state.selectedKind);
  }
}

function updateEditorActions() {
  const item = findSelectedEntry();
  const disabled = !item;
  dom.saveButton.disabled = disabled;
  dom.publishButton.disabled = disabled;
  dom.unpublishButton.disabled = disabled;
  dom.deleteButton.disabled = disabled;
}

function entityLabel(kind) {
  return kind.slice(0, -1).replace(/^./, (value) => value.toUpperCase());
}

function entityBadgeForItem(kind, item) {
  if (kind === "tracks" || kind === "exercises") {
    return humanizeValue(item.draft.contentKind || kind);
  }
  if (kind === "skills") {
    return humanizeValue(item.draft.category || "skill");
  }
  return entityLabel(kind);
}

function describeItem(kind, item) {
  if (kind === "tracks") {
    return [
      item.draft.summary || "Track summary is empty.",
      `${(item.draft.exerciseRefs || []).length || 0} exercise refs`,
    ].join(" · ");
  }
  if (kind === "exercises") {
    const variants = Array.isArray(item.draft.languageVariants) ? item.draft.languageVariants : [];
    return [
      item.draft.summary || "Exercise summary is empty.",
      `${variants.map((variant) => variant.languageLabel).join(", ") || "No languages"}`,
    ].join(" · ");
  }
  if (kind === "skills") {
    return item.draft.description || "Skill description is empty.";
  }
  return item.draft.summary || "No summary yet.";
}

function defaultDraftFor(kind) {
  const stamp = Date.now();
  if (kind === "tracks") {
    return {
      id: `track_${stamp}`,
      title: "New track",
      summary: "",
      lane: "project",
      contentKind: "project_track",
      level: "foundation",
      topicIds: [],
      domainIds: [],
      tags: [],
      skillIds: [],
      exerciseRefs: [],
    };
  }
  if (kind === "exercises") {
    return {
      id: `exercise_${stamp}`,
      title: "New exercise",
      summary: "",
      lane: "project",
      contentKind: "project_exercise",
      level: "foundation",
      topicIds: [],
      domainIds: [],
      tags: [],
      skillIds: [],
      problemStatement: "",
      acceptanceCriteria: [],
      taskSteps: [],
      supportedModes: ["guided"],
      hints: {},
      reflectionPrompts: [],
      requirements: [],
      languageVariants: [
        {
          languageId: "python",
          languageLabel: "Python",
          isDefault: true,
          starterCode: "",
          starterFiles: {},
          solutionCode: null,
          sandboxHarnessTemplate: "{{USER_CODE}}\n\n{{TEST_BODY}}\n",
          runCommand: "python main.py",
          entryFilePath: "main.py",
          demoFilePath: null,
          testCases: [],
        },
      ],
    };
  }
  if (kind === "topics") {
    return { id: `topic_${stamp}`, title: "New topic", summary: "" };
  }
  if (kind === "domains") {
    return { id: `domain_${stamp}`, title: "New domain", summary: "" };
  }
  return {
    id: `skill_${stamp}`,
    title: "New skill",
    category: "languageSyntax",
    description: "",
    reviewExerciseId: "",
  };
}

function createAttributeRow(label, value) {
  const wrapper = document.createElement("div");
  const term = document.createElement("dt");
  const description = document.createElement("dd");
  term.textContent = label;
  description.textContent = value;
  wrapper.append(term, description);
  return wrapper;
}

function createStructureChip(title, description) {
  const chip = document.createElement("div");
  chip.className = "structure-chip";
  const heading = document.createElement("strong");
  heading.textContent = title;
  const detail = document.createElement("span");
  detail.textContent = description;
  chip.append(heading, detail);
  return chip;
}

function setStatus(message, { tone = "info" } = {}) {
  dom.authStatus.textContent = message;
  dom.connectionIndicator.classList.remove("connected", "error");
  if (tone === "success") {
    dom.connectionIndicator.classList.add("connected");
  }
  if (tone === "error") {
    dom.connectionIndicator.classList.add("error");
  }
}

async function api(path, options = {}) {
  const response = await fetch(path, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      "x-admin-key": state.adminKey,
      ...(options.headers || {}),
    },
  });
  if (response.status === 204) {
    return null;
  }
  const payload = await response.json();
  if (!response.ok) {
    throw new Error(payload.error || `Request failed (${response.status})`);
  }
  return payload;
}

function formatDateTime(value, fallback = "—") {
  if (!value) {
    return fallback;
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return fallback;
  }
  return date.toLocaleString();
}

function humanizeValue(value) {
  return String(value || "")
    .replace(/_/g, " ")
    .replace(/^./, (letter) => letter.toUpperCase());
}
