const DEFAULT_ADMIN_KEY = "local-dev-admin-key";
const ENTITY_KEYS = ["tracks", "exercises", "topics", "domains", "skills"];
const LANE_ORDER = ["project", "dsa", "leetcode"];

const state = {
  adminKey: localStorage.getItem("adminKey") || DEFAULT_ADMIN_KEY,
  catalog: null,
  selectedKind: "tracks",
  selectedId: null,
  searchQuery: "",
  laneFilter: "",
  levelFilter: "",
  languageFilter: "",
  statusFilter: "",
  topicFilter: "",
  domainFilter: "",
  tagFilter: "",
  view: "list",
  selectedVariantIndex: 0,
  editorMode: "idle",
  editorInputMode: "form",
  editorKind: "tracks",
  editorSourceId: null,
  editorDraft: null,
  editorStepIndex: 0,
  editorVariantIndex: 0,
  editorJsonText: "",
  sidebarVisible: true,
  detailMenuOpen: false,
  createMenuOpen: false,
};

const dom = {
  adminKey: document.getElementById("admin-key"),
  authStatus: document.getElementById("auth-status"),
  connectionIndicator: document.getElementById("connection-indicator"),
  connectButton: document.getElementById("connect-button"),
  refreshButton: document.getElementById("refresh-button"),
  sidebar: document.getElementById("sidebar"),
  sidebarToggle: document.getElementById("sidebar-toggle"),
  clearFiltersButton: document.getElementById("clear-filters-button"),
  createEntryShell: document.getElementById("create-entry-shell"),
  createEntryButton: document.getElementById("create-entry-button"),
  createEntryMenu: document.getElementById("create-entry-menu"),
  searchInput: document.getElementById("search-input"),
  laneFilter: document.getElementById("lane-filter"),
  levelFilter: document.getElementById("level-filter"),
  languageFilter: document.getElementById("language-filter"),
  statusFilter: document.getElementById("status-filter"),
  topicFilter: document.getElementById("topic-filter"),
  domainFilter: document.getElementById("domain-filter"),
  tagFilter: document.getElementById("tag-filter"),
  tagSuggestions: document.getElementById("tag-suggestions"),
  laneFilterShell: document.getElementById("lane-filter")?.closest(".field-shell"),
  levelFilterShell: document.getElementById("level-filter")?.closest(".field-shell"),
  languageFilterShell: document.getElementById("language-filter")?.closest(".field-shell"),
  topicFilterShell: document.getElementById("topic-filter")?.closest(".field-shell"),
  domainFilterShell: document.getElementById("domain-filter")?.closest(".field-shell"),
  tagFilterShell: document.getElementById("tag-filter")?.closest(".field-shell"),
  listScreen: document.getElementById("list-screen"),
  detailScreen: document.getElementById("detail-screen"),
  variantScreen: document.getElementById("variant-screen"),
  editorScreen: document.getElementById("editor-screen"),
  listTitle: document.getElementById("list-title"),
  listSubtitle: document.getElementById("list-subtitle"),
  entityCountPill: document.getElementById("entity-count-pill"),
  entityGroups: document.getElementById("entity-groups"),
  backToListButton: document.getElementById("back-to-list-button"),
  detailTitle: document.getElementById("detail-title"),
  detailSubtitle: document.getElementById("detail-subtitle"),
  detailSummary: document.getElementById("detail-summary"),
  detailPublishButton: document.getElementById("detail-publish-button"),
  detailMenuShell: document.getElementById("detail-menu-shell"),
  detailMenuButton: document.getElementById("detail-menu-button"),
  detailMenu: document.getElementById("detail-menu"),
  detailEditButton: document.getElementById("detail-edit-button"),
  detailDeleteButton: document.getElementById("detail-delete-button"),
  selectionStatusPill: document.getElementById("selection-status-pill"),
  selectionAttributes: document.getElementById("selection-attributes"),
  selectionStructure: document.getElementById("selection-structure"),
  selectionRelated: document.getElementById("selection-related"),
  exerciseContentSection: document.getElementById("exercise-content-section"),
  exerciseProblem: document.getElementById("exercise-problem"),
  exerciseGuidanceSection: document.getElementById("exercise-guidance-section"),
  exerciseGuidance: document.getElementById("exercise-guidance"),
  exerciseHintsSection: document.getElementById("exercise-hints-section"),
  exerciseHints: document.getElementById("exercise-hints"),
  exerciseVariantSection: document.getElementById("exercise-variant-section"),
  exerciseVariant: document.getElementById("exercise-variant"),
  variantBackButton: document.getElementById("variant-back-button"),
  variantEditButton: document.getElementById("variant-edit-button"),
  variantTitle: document.getElementById("variant-title"),
  variantSubtitle: document.getElementById("variant-subtitle"),
  variantProblem: document.getElementById("variant-problem"),
  variantGuidance: document.getElementById("variant-guidance"),
  variantHints: document.getElementById("variant-hints"),
  variantConfig: document.getElementById("variant-config"),
  variantStarter: document.getElementById("variant-starter"),
  variantSolution: document.getElementById("variant-solution"),
  editorBackButton: document.getElementById("editor-back-button"),
  cancelEditorButton: document.getElementById("cancel-editor-button"),
  editorModeToggle: document.getElementById("editor-mode-toggle"),
  editorTitle: document.getElementById("editor-title"),
  editorSubtitle: document.getElementById("editor-subtitle"),
  editorMeta: document.getElementById("editor-meta"),
  editorKindBadge: document.getElementById("editor-kind-badge"),
  editorError: document.getElementById("editor-error"),
  editorFormShell: document.getElementById("editor-form-shell"),
  editorJsonShell: document.getElementById("editor-json-shell"),
  editorTextarea: document.getElementById("editor-textarea"),
  saveButton: document.getElementById("save-button"),
  deleteButton: document.getElementById("delete-button"),
  lastPublishedValue: document.getElementById("last-published-value"),
  contentVersionValue: document.getElementById("content-version-value"),
  overviewTracksCountValue: document.getElementById("overview-tracks-count-value"),
  overviewExercisesCountValue: document.getElementById("overview-exercises-count-value"),
  overviewTaxonomyCountValue: document.getElementById("overview-taxonomy-count-value"),
  pendingCountValue: document.getElementById("pending-count-value"),
  tracksCountValue: document.getElementById("tracks-count-value"),
  entityExercisesCount: document.getElementById("entity-exercises-count"),
  entityTopicsCount: document.getElementById("entity-topics-count"),
  entityDomainsCount: document.getElementById("entity-domains-count"),
  entitySkillsCount: document.getElementById("entity-skills-count"),
  itemTemplate: document.getElementById("entity-item-template"),
  entityTabs: Array.from(document.querySelectorAll("[data-entity-tab]")),
};

dom.adminKey.value = state.adminKey;

bindEvents();
renderStaticState();

if (state.adminKey) {
  void runAction(connect);
}

function bindEvents() {
  dom.connectButton.addEventListener("click", () => runAction(connect));
  dom.refreshButton.addEventListener("click", () => runAction(refreshCatalog));
  dom.sidebarToggle?.addEventListener("click", () => toggleSidebarVisibility());
  dom.clearFiltersButton?.addEventListener("click", () => clearListFilters());
  dom.createEntryButton.addEventListener("click", (event) => {
    event.stopPropagation();
    toggleCreateMenu();
  });
  dom.backToListButton.addEventListener("click", () => switchView("list"));
  dom.variantBackButton?.addEventListener("click", () => switchView("detail"));
  dom.variantEditButton?.addEventListener("click", () => runAction(editSelectedExerciseVariant));
  dom.detailPublishButton.addEventListener("click", () => runAction(toggleSelectedPublishState));
  dom.detailMenuButton.addEventListener("click", (event) => {
    event.stopPropagation();
    toggleDetailMenu();
  });
  dom.detailEditButton.addEventListener("click", () => runAction(loadSelectedDraft));
  dom.detailDeleteButton.addEventListener("click", () => runAction(deleteSelectedEntry));
  dom.editorBackButton.addEventListener("click", handleEditorBack);
  dom.cancelEditorButton.addEventListener("click", handleEditorBack);
  dom.editorModeToggle.addEventListener("click", () => runAction(toggleEditorInputMode));
  dom.saveButton.addEventListener("click", () => runAction(saveEditorDraft));
  dom.deleteButton.addEventListener("click", () => runAction(deleteEditorEntry));
  dom.editorTextarea.addEventListener("input", () => {
    if (state.editorInputMode === "json") {
      state.editorJsonText = dom.editorTextarea.value;
    }
  });

  dom.searchInput.addEventListener("input", (event) => {
    state.searchQuery = event.target.value.trim().toLowerCase();
    renderListScreen();
  });
  dom.laneFilter.addEventListener("change", (event) => {
    state.laneFilter = event.target.value;
    renderListScreen();
  });
  dom.levelFilter.addEventListener("change", (event) => {
    state.levelFilter = event.target.value;
    renderListScreen();
  });
  dom.languageFilter.addEventListener("change", (event) => {
    state.languageFilter = event.target.value;
    renderListScreen();
  });
  dom.statusFilter.addEventListener("change", (event) => {
    state.statusFilter = event.target.value;
    renderListScreen();
  });
  dom.topicFilter.addEventListener("change", (event) => {
    state.topicFilter = event.target.value;
    renderListScreen();
  });
  dom.domainFilter.addEventListener("change", (event) => {
    state.domainFilter = event.target.value;
    renderListScreen();
  });
  dom.tagFilter.addEventListener("input", (event) => {
    state.tagFilter = String(event.target.value || "").trim();
    renderListScreen();
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
      resetEditor();
      closeDetailMenu();
      closeCreateMenu();
      updateFilterVisibility();
      hydrateFilterOptions();
      if (isNarrowViewport()) {
        state.sidebarVisible = false;
        applySidebarVisibility();
      }
      switchView("list");
    });
  }

  document.addEventListener("click", (event) => {
    if (!dom.detailMenuShell.contains(event.target)) {
      closeDetailMenu();
    }
    if (dom.createEntryShell && !dom.createEntryShell.contains(event.target)) {
      closeCreateMenu();
    }
  });

  window.addEventListener("resize", () => applySidebarVisibility());
}

function renderStaticState() {
  applySidebarVisibility({ initialize: true });
  updateFilterVisibility();
  renderOverview();
  renderNavState();
  renderCurrentScreen();
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

  setStatus("Checking admin session…");
  await api("/admin/api/session", { includeAdminKey: false });
  await refreshCatalog();
}

async function refreshCatalog() {
  setStatus("Loading catalog…");
  const catalog = await api("/admin/api/catalog");
  state.catalog = catalog;

  if (state.selectedId && !findEntry(state.selectedKind, state.selectedId)) {
    state.selectedId = null;
  }
  if (state.view === "detail" && !findSelectedEntry()) {
    state.view = "list";
  }
  if (state.view === "variant" && (!findSelectedEntry() || state.selectedKind !== "exercises")) {
    state.view = findSelectedEntry() ? "detail" : "list";
  }
  if (state.view === "editor" && state.editorMode === "edit" && !findEntry(state.editorKind, state.editorSourceId)) {
    resetEditor();
    state.view = "list";
  }

  hydrateFilterOptions();
  renderOverview();
  renderNavState();
  renderCurrentScreen();
  setStatus(
    `Connected. Catalog v${catalog.contentVersion} with ${catalog.tracks.length} tracks, ${catalog.exercises.length} exercises, and ${catalog.skills.length} skills.`,
    { tone: "success" },
  );
}

function switchView(view) {
  state.view = view;
  closeDetailMenu();
  closeCreateMenu();
  if (isNarrowViewport() && view !== "list") {
    state.sidebarVisible = false;
    applySidebarVisibility();
  }
  renderCurrentScreen();
}

function renderOverview() {
  const catalog = state.catalog;
  const entries = allEntries();
  const pendingCount = entries.filter((item) => item.workflowStatus === "changes_pending").length;

  dom.lastPublishedValue.textContent = formatDateTime(catalog?.lastPublishedAt, "Never");
  dom.contentVersionValue.textContent = catalog ? String(catalog.contentVersion) : "—";
  dom.overviewTracksCountValue.textContent = String(catalog?.tracks?.length || 0);
  dom.overviewExercisesCountValue.textContent = String(catalog?.exercises?.length || 0);
  dom.overviewTaxonomyCountValue.textContent = String(
    (catalog?.topics?.length || 0) + (catalog?.domains?.length || 0) + (catalog?.skills?.length || 0),
  );
  dom.pendingCountValue.textContent = String(pendingCount);
}

function renderNavState() {
  const catalog = state.catalog;
  dom.tracksCountValue.textContent = String(catalog?.tracks?.length || 0);
  dom.entityExercisesCount.textContent = String(catalog?.exercises?.length || 0);
  dom.entityTopicsCount.textContent = String(catalog?.topics?.length || 0);
  dom.entityDomainsCount.textContent = String(catalog?.domains?.length || 0);
  dom.entitySkillsCount.textContent = String(catalog?.skills?.length || 0);
  dom.createEntryButton.textContent = `New ${entityLabel(state.selectedKind)}`;
  renderCreateMenu();

  for (const button of dom.entityTabs) {
    button.classList.toggle("active", button.dataset.entityTab === state.selectedKind);
  }
}

function renderCurrentScreen() {
  const hasSelection = !!findSelectedEntry();
  if (state.view === "detail" && !hasSelection) {
    state.view = "list";
  }
  if (state.view === "variant" && (!hasSelection || state.selectedKind !== "exercises")) {
    state.view = hasSelection ? "detail" : "list";
  }
  if (state.view === "editor" && state.editorMode === "idle") {
    state.view = hasSelection ? "detail" : "list";
  }

  dom.listScreen.hidden = state.view !== "list";
  dom.detailScreen.hidden = state.view !== "detail";
  dom.variantScreen.hidden = state.view !== "variant";
  dom.editorScreen.hidden = state.view !== "editor";

  renderListScreen();
  renderDetailScreen();
  renderVariantScreen();
  renderEditorScreen();
}

function renderListScreen() {
  const items = visibleEntries();
  dom.listTitle.textContent = entityCollectionLabel(state.selectedKind);
  dom.listSubtitle.textContent = listSubtitleForKind(state.selectedKind);
  dom.entityCountPill.textContent = String(items.length);
  dom.entityGroups.replaceChildren();

  if (!state.catalog) {
    dom.entityGroups.appendChild(
      createEmptyState("Connect to the admin API to load content entries."),
    );
    return;
  }

  if (items.length === 0) {
    dom.entityGroups.appendChild(createEmptyState("No entries match the current filters."));
    return;
  }

  for (const group of groupEntries(state.selectedKind, items)) {
    dom.entityGroups.appendChild(createGroupSection(group));
  }
}

function renderDetailScreen() {
  const item = findSelectedEntry();
  if (!item) {
    dom.detailTitle.textContent = "Nothing selected";
    dom.detailSubtitle.textContent =
      "Open an item from the list to inspect metadata, structure, and related content.";
    dom.detailSummary.textContent =
      "Pick an item from the list to inspect its structure and related content.";
    dom.selectionStatusPill.textContent = "Idle";
    dom.selectionStatusPill.className = "pill subtle-pill";
    dom.detailPublishButton.disabled = true;
    dom.selectionAttributes.replaceChildren(createAttributeRow("Status", "—"));
    dom.selectionStructure.replaceChildren(createMutedText("No structure details yet."));
    dom.selectionRelated.replaceChildren(createMutedText("No related items yet."));
    hideExerciseDetailSections();
    return;
  }

  dom.detailTitle.textContent = item.draft.title || item.id;
  dom.detailSubtitle.textContent = `${entityLabel(state.selectedKind)} · ${item.id}`;
  dom.detailSummary.textContent =
    item.draft.summary || item.draft.description || "No summary added yet.";
  dom.selectionStatusPill.textContent = humanizeValue(item.workflowStatus);
  dom.selectionStatusPill.className = `pill status-${item.workflowStatus}`;
  dom.detailPublishButton.disabled = false;
  dom.detailPublishButton.textContent =
    item.workflowStatus === "published" ? "Unpublish" : "Publish";
  dom.detailPublishButton.className =
    item.workflowStatus === "published" ? "ghost-button" : "secondary-button";

  const attributes = [
    ["Collection", entityLabel(state.selectedKind)],
    ["ID", item.id],
    ["Workflow", humanizeValue(item.workflowStatus)],
    ["Lane", item.draft.lane || "—"],
    ["Level", item.draft.level || "—"],
    ["Published", formatDateTime(item.publishedAt, "Not yet")],
    ["Updated", formatDateTime(item.updatedAt, "Unknown")],
  ];
  dom.selectionAttributes.replaceChildren(
    ...attributes.map(([label, value]) => createAttributeRow(label, value)),
  );

  const structure = buildStructure(state.selectedKind, item.draft);
  dom.selectionStructure.replaceChildren(
    ...(structure.length ? structure : [createMutedText("No structure details yet.")]),
  );

  const related = buildRelatedEntries(state.selectedKind, item);
  dom.selectionRelated.replaceChildren(
    ...(related.length ? related : [createMutedText("No related items yet.")]),
  );

  if (state.selectedKind === "exercises") {
    renderExerciseDetailSections(item.draft);
  } else {
    hideExerciseDetailSections();
  }
}

function renderVariantScreen() {
  if (dom.variantScreen.hidden) {
    return;
  }

  const item = findSelectedEntry();
  if (!item || state.selectedKind !== "exercises") {
    dom.variantTitle.textContent = "No variant selected";
    dom.variantSubtitle.textContent = "Open an exercise language variant from the detail page.";
    dom.variantProblem.textContent = "—";
    dom.variantGuidance.replaceChildren(createMutedText("—"));
    dom.variantHints.replaceChildren(createMutedText("—"));
    dom.variantConfig.replaceChildren(createMutedText("—"));
    dom.variantStarter.replaceChildren(createMutedText("—"));
    dom.variantSolution.replaceChildren(createMutedText("—"));
    dom.variantEditButton.disabled = true;
    return;
  }

  const draft = item.draft || {};
  const variants = Array.isArray(draft.languageVariants) ? draft.languageVariants : [];
  if (variants.length === 0) {
    dom.variantTitle.textContent = draft.title || item.id;
    dom.variantSubtitle.textContent = `Exercise · ${item.id}`;
    dom.variantProblem.textContent = draft.problemStatement || draft.summary || "—";
    dom.variantGuidance.replaceChildren(createMutedText("No language variants configured."));
    dom.variantHints.replaceChildren(createMutedText("—"));
    dom.variantConfig.replaceChildren(createMutedText("—"));
    dom.variantStarter.replaceChildren(createMutedText("—"));
    dom.variantSolution.replaceChildren(createMutedText("—"));
    dom.variantEditButton.disabled = false;
    return;
  }

  const variantIndex = Math.min(
    Math.max(state.selectedVariantIndex, 0),
    variants.length - 1,
  );
  state.selectedVariantIndex = variantIndex;
  const variant = variants[variantIndex];

  const variantLabel = String(variant?.languageLabel || variant?.languageId || "Language").trim();
  const variantId = String(variant?.languageId || "").trim();
  const suffix = variantId ? `${variantLabel} · ${variantId}` : variantLabel;

  dom.variantTitle.textContent = `${draft.title || item.id} — ${suffix}`;
  dom.variantSubtitle.textContent = [
    `Exercise · ${item.id}`,
    draft.lane ? `Lane: ${draft.lane}` : null,
    draft.level ? `Level: ${draft.level}` : null,
    variant?.isDefault ? "Default variant" : null,
  ]
    .filter(Boolean)
    .join(" · ");

  dom.variantProblem.textContent = draft.problemStatement || draft.summary || "—";

  dom.variantGuidance.replaceChildren(
    createVariantListSection("Acceptance criteria", Array.isArray(draft.acceptanceCriteria) ? draft.acceptanceCriteria : []),
    createVariantTaskStepsSection(Array.isArray(draft.taskSteps) ? draft.taskSteps : []),
    createVariantListSection("Reflection prompts", Array.isArray(draft.reflectionPrompts) ? draft.reflectionPrompts : []),
  );

  const hints = draft && typeof draft.hints === "object" && draft.hints !== null ? draft.hints : {};
  const hintEntries = Object.entries(hints).filter(([, value]) => String(value || "").trim());
  dom.variantHints.replaceChildren(
    ...(hintEntries.length
      ? hintEntries.map(([key, value]) => createStructureChip(humanizeValue(key), String(value)))
      : [createMutedText("No hints configured.")]),
  );

  const starterFiles = variant?.starterFiles && typeof variant.starterFiles === "object" ? variant.starterFiles : {};
  dom.variantConfig.replaceChildren(
    ...[
      createAttributeRow("Language", variantId ? `${variantLabel} (${variantId})` : variantLabel),
      createAttributeRow("Run", String(variant?.runCommand || "—")),
      createAttributeRow("Entry", String(variant?.entryFilePath || "—")),
      createAttributeRow("Demo", String(variant?.demoFilePath || "—")),
      createAttributeRow("Starter files", String(Object.keys(starterFiles).length)),
      createAttributeRow(
        "Test cases",
        String(Array.isArray(variant?.testCases) ? variant.testCases.length : 0),
      ),
    ],
  );

  dom.variantStarter.replaceChildren(
    createCodeBlock(String(variant?.starterCode || "")),
    createCodeBlock(
      Object.keys(starterFiles).length ? JSON.stringify(starterFiles, null, 2) : "",
      { label: "starterFiles (JSON)" },
    ),
  );

  dom.variantSolution.replaceChildren(
    createCodeBlock(
      variant?.solutionCode ? String(variant.solutionCode) : "",
      { emptyLabel: "No solutionCode configured." },
    ),
  );

  dom.variantEditButton.disabled = false;
}

function renderEditorScreen() {
  const editorLoaded = state.editorMode !== "idle" && !!state.editorDraft;
  const showJson = editorLoaded && state.editorInputMode === "json";

  dom.editorModeToggle.disabled = !editorLoaded;
  dom.editorModeToggle.textContent = showJson ? "Form" : "JSON";
  dom.editorJsonShell.hidden = !showJson;
  dom.editorFormShell.hidden = showJson;

  dom.editorTextarea.disabled = !editorLoaded || !showJson;
  dom.saveButton.disabled = !editorLoaded;
  dom.deleteButton.disabled = !(state.editorMode === "edit" && state.editorSourceId);

  if (!editorLoaded) {
    clearEditorError();
    dom.editorTitle.textContent = "No draft loaded";
    dom.editorSubtitle.textContent =
      "Update the draft using the form (or switch to JSON), save it, then return to the detail page.";
    dom.editorMeta.textContent =
      "Start a new item from the list view or open an existing item from the detail page.";
    dom.editorKindBadge.textContent = "Idle";
    dom.editorKindBadge.className = "pill subtle-pill";
    dom.editorTextarea.value = "";
    dom.editorFormShell.replaceChildren();
    return;
  }

  dom.editorKindBadge.textContent = `${humanizeValue(state.editorMode)} ${entityLabel(state.editorKind)}`;
  dom.editorKindBadge.className = "pill";
  if (state.editorMode === "create") {
    dom.editorTitle.textContent = `New ${entityLabel(state.editorKind)}`;
    dom.editorSubtitle.textContent =
      "Create the draft using the form, save it, then continue from the detail page.";
    dom.editorMeta.textContent =
      "This draft has not been saved yet. Saving will create a new entry in the selected menu.";
  } else {
    dom.editorTitle.textContent = `Editing ${entityLabel(state.editorKind)} · ${state.editorSourceId}`;
    dom.editorSubtitle.textContent =
      "Update the draft, save it, then return to the detail page for publish or delete actions.";
    dom.editorMeta.textContent =
      "You are editing an existing entry. Save updates the draft and returns to detail view.";
  }

  if (showJson) {
    if (!state.editorJsonText) {
      state.editorJsonText = JSON.stringify(state.editorDraft, null, 2);
    }
    dom.editorTextarea.value = state.editorJsonText;
  } else {
    state.editorJsonText = "";
    renderEditorForm();
  }
}

function hideExerciseDetailSections() {
  dom.exerciseContentSection.hidden = true;
  dom.exerciseGuidanceSection.hidden = true;
  dom.exerciseHintsSection.hidden = true;
  dom.exerciseVariantSection.hidden = true;
}

function renderExerciseDetailSections(draft) {
  const exercise = draft || {};
  dom.exerciseContentSection.hidden = false;
  dom.exerciseGuidanceSection.hidden = false;
  dom.exerciseHintsSection.hidden = false;
  dom.exerciseVariantSection.hidden = false;

  dom.exerciseProblem.textContent = exercise.problemStatement || exercise.summary || "—";

  dom.exerciseGuidance.replaceChildren(
    createVariantListSection(
      "Acceptance criteria",
      Array.isArray(exercise.acceptanceCriteria) ? exercise.acceptanceCriteria : [],
    ),
    createVariantTaskStepsSection(Array.isArray(exercise.taskSteps) ? exercise.taskSteps : []),
    createVariantListSection(
      "Reflection prompts",
      Array.isArray(exercise.reflectionPrompts) ? exercise.reflectionPrompts : [],
    ),
    createVariantListSection(
      "Requirements (regex checks)",
      Array.isArray(exercise.requirements)
        ? exercise.requirements
            .map((req) => {
              if (!req || typeof req !== "object") return "";
              const label = String(req.label || "").trim();
              const pattern = String(req.pattern || "").trim();
              const feedback = String(req.feedback || "").trim();
              const parts = [
                label ? `Label: ${label}` : "",
                pattern ? `Pattern: ${pattern}` : "",
                feedback ? `Feedback: ${feedback}` : "",
              ].filter(Boolean);
              return parts.join(" · ");
            })
            .filter((line) => String(line).trim())
        : [],
    ),
  );

  const hints = exercise && typeof exercise.hints === "object" && exercise.hints !== null ? exercise.hints : {};
  const hintEntries = Object.entries(hints).filter(([, value]) => String(value || "").trim());
  dom.exerciseHints.replaceChildren(
    ...(hintEntries.length
      ? hintEntries.map(([key, value]) => createHintCard(key, String(value)))
      : [createMutedText("No hints configured.")]),
  );

  dom.exerciseVariant.replaceChildren(renderExerciseVariantPreview(exercise));
}

function createHintCard(level, body) {
  const details = document.createElement("details");
  details.className = "related-card hint-card";
  const summary = document.createElement("summary");
  summary.className = "hint-summary";
  summary.textContent = humanizeValue(level);
  const text = document.createElement("div");
  text.className = "muted hint-body";
  text.textContent = body;
  details.append(summary, text);
  return details;
}

function renderExerciseVariantPreview(exercise) {
  const container = document.createElement("div");
  const variants = Array.isArray(exercise.languageVariants) ? exercise.languageVariants : [];
  if (variants.length === 0) {
    container.appendChild(createMutedText("No language variants configured."));
    return container;
  }

  const activeIndex = Math.min(Math.max(state.selectedVariantIndex, 0), variants.length - 1);
  state.selectedVariantIndex = activeIndex;

  const tabs = document.createElement("div");
  tabs.className = "variant-tabs";
  variants.forEach((variant, index) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `variant-tab-button ${index === activeIndex ? "active" : ""}`;
    const label = String(variant?.languageLabel || variant?.languageId || "Variant").trim();
    button.textContent = variant?.isDefault ? `${label} *` : label;
    button.addEventListener("click", () => {
      state.selectedVariantIndex = index;
      renderDetailScreen();
    });
    tabs.appendChild(button);
  });
  container.appendChild(tabs);

  const active = variants[activeIndex];
  const starterFiles =
    active?.starterFiles && typeof active.starterFiles === "object" ? active.starterFiles : {};

  const meta = document.createElement("div");
  meta.className = "variant-meta";
  meta.appendChild(
    createVariantMetaRow("Run", String(active?.runCommand || active?.entryFilePath || "—")),
  );
  meta.appendChild(createVariantMetaRow("Entry", String(active?.entryFilePath || "—")));
  meta.appendChild(createVariantMetaRow("Demo", String(active?.demoFilePath || "—")));
  meta.appendChild(createVariantMetaRow("Starter files", String(Object.keys(starterFiles).length)));
  meta.appendChild(
    createVariantMetaRow(
      "Test cases",
      String(Array.isArray(active?.testCases) ? active.testCases.length : 0),
    ),
  );
  container.appendChild(meta);

  container.appendChild(createCodeBlock(String(active?.starterCode || ""), { label: "Starter code" }));
  container.appendChild(
    createCodeBlock(
      Object.keys(starterFiles).length ? JSON.stringify(starterFiles, null, 2) : "",
      { label: "starterFiles (JSON)", emptyLabel: "—" },
    ),
  );
  container.appendChild(
    createCodeBlock(active?.solutionCode ? String(active.solutionCode) : "", {
      label: "Solution code",
      emptyLabel: "No solutionCode configured.",
    }),
  );

  const actions = document.createElement("div");
  actions.className = "inline-actions";

  const openVariant = document.createElement("button");
  openVariant.type = "button";
  openVariant.className = "ghost-button";
  openVariant.textContent = "Open variant page";
  openVariant.addEventListener("click", () => runAction(() => openSelectedExerciseVariant(activeIndex)));
  actions.appendChild(openVariant);

  const editVariant = document.createElement("button");
  editVariant.type = "button";
  editVariant.className = "secondary-button";
  editVariant.textContent = "Edit this variant";
  editVariant.addEventListener("click", () => runAction(editSelectedExerciseVariant));
  actions.appendChild(editVariant);

  container.appendChild(actions);
  return container;
}

async function loadCreateDraft(kind, { lane = "" } = {}) {
  state.editorMode = "create";
  state.editorKind = kind;
  state.editorSourceId = null;
  state.editorDraft = structuredCloneSafe(defaultDraftFor(kind));
  state.editorStepIndex = 0;
  if (lane && (kind === "tracks" || kind === "exercises")) {
    state.editorDraft.lane = lane;
    state.editorDraft.contentKind = contentKindOptionsFor(lane, { isTrack: kind === "tracks" })[0]?.value || state.editorDraft.contentKind;
  }
  if (kind === "tracks" && state.catalog && Array.isArray(state.catalog.exercises) && state.catalog.exercises.length > 0) {
    const draftLane = String(state.editorDraft.lane || "project");
    const laneMatch = state.catalog.exercises.find((exercise) => String(exercise.draft?.lane || "") === draftLane);
    const suggestedId = laneMatch?.id || state.catalog.exercises[0].id;
    if (suggestedId && (!Array.isArray(state.editorDraft.exerciseRefs) || state.editorDraft.exerciseRefs.length === 0)) {
      state.editorDraft.exerciseRefs = [{ exerciseId: suggestedId }];
    }
  }
  state.editorInputMode = "form";
  state.editorVariantIndex = guessDefaultVariantIndex(state.editorDraft);
  state.editorJsonText = "";
  clearEditorError();
  switchView("editor");
  setStatus(`Loaded a new ${entityLabel(kind).toLowerCase()} draft in the editor.`);
}

async function loadSelectedDraft() {
  const item = findSelectedEntry();
  if (!item) {
    throw new Error("Pick an entry from the list before editing.");
  }

  state.editorMode = "edit";
  state.editorKind = state.selectedKind;
  state.editorSourceId = item.id;
  state.editorDraft = structuredCloneSafe(item.draft);
  state.editorStepIndex = 0;
  state.editorInputMode = "form";
  state.editorVariantIndex = guessDefaultVariantIndex(state.editorDraft);
  state.editorJsonText = "";
  clearEditorError();
  switchView("editor");
  setStatus(`Loaded ${item.id} into the editor.`);
}

async function openSelectedExerciseVariant(index) {
  const item = findSelectedEntry();
  if (!item || state.selectedKind !== "exercises") {
    throw new Error("Open a variant from an exercise detail page.");
  }

  const variants = Array.isArray(item.draft?.languageVariants) ? item.draft.languageVariants : [];
  if (variants.length === 0) {
    throw new Error("This exercise has no language variants configured yet.");
  }

  state.selectedVariantIndex = Math.min(Math.max(index, 0), variants.length - 1);
  switchView("variant");
}

async function editSelectedExerciseVariant() {
  const item = findSelectedEntry();
  if (!item || state.selectedKind !== "exercises") {
    throw new Error("Pick an exercise before editing.");
  }

  const variants = Array.isArray(item.draft?.languageVariants) ? item.draft.languageVariants : [];
  const variantIndex =
    variants.length > 0
      ? Math.min(Math.max(state.selectedVariantIndex, 0), variants.length - 1)
      : 0;

  state.editorMode = "edit";
  state.editorKind = state.selectedKind;
  state.editorSourceId = item.id;
  state.editorDraft = structuredCloneSafe(item.draft);
  state.editorStepIndex = 0;
  state.editorInputMode = "form";
  state.editorVariantIndex = variantIndex;
  state.editorJsonText = "";
  clearEditorError();
  switchView("editor");
  setStatus(`Editing ${item.id} (${variants[variantIndex]?.languageLabel || variants[variantIndex]?.languageId || "variant"}).`);
}

async function saveEditorDraft() {
  if (state.editorMode === "idle") {
    throw new Error("Load a draft first.");
  }

  const payload = collectEditorPayload();
  let savedId = "";
  if (state.editorMode === "create") {
    const created = await api(`/admin/api/${state.editorKind}`, {
      method: "POST",
      body: JSON.stringify(payload),
    });
    savedId = created.id;
  } else {
    const updated = await api(`/admin/api/${state.editorKind}/${state.editorSourceId}`, {
      method: "PUT",
      body: JSON.stringify(payload),
    });
    savedId = updated.id || payload.id || state.editorSourceId;
  }

  await refreshCatalog();
  state.selectedKind = state.editorKind;
  state.selectedId = savedId;
  resetEditor();
  renderNavState();
  switchView("detail");
  setStatus(`Saved ${savedId}.`, { tone: "success" });
}

async function toggleSelectedPublishState() {
  const item = findSelectedEntry();
  if (!item) {
    throw new Error("Pick an entry before changing publish status.");
  }

  const action = item.workflowStatus === "published" ? "unpublish" : "publish";
  await api(`/admin/api/${state.selectedKind}/${item.id}/${action}`, {
    method: "POST",
  });
  await refreshCatalog();
  state.selectedId = item.id;
  switchView("detail");
  setStatus(`${humanizeValue(action)}ed ${item.id}.`, { tone: "success" });
}

async function deleteSelectedEntry() {
  const item = findSelectedEntry();
  if (!item) {
    throw new Error("Pick an entry before deleting it.");
  }
  if (!window.confirm(`Delete ${item.id}?`)) {
    return;
  }

  closeDetailMenu();
  await api(`/admin/api/${state.selectedKind}/${item.id}`, { method: "DELETE" });
  await refreshCatalog();
  state.selectedId = null;
  resetEditor();
  switchView("list");
  setStatus(`Deleted ${item.id}.`, { tone: "success" });
}

async function deleteEditorEntry() {
  if (state.editorMode !== "edit" || !state.editorSourceId) {
    throw new Error("Load an existing entry before deleting it.");
  }
  if (!window.confirm(`Delete ${state.editorSourceId}?`)) {
    return;
  }

  const deletedId = state.editorSourceId;
  await api(`/admin/api/${state.editorKind}/${deletedId}`, { method: "DELETE" });
  await refreshCatalog();
  state.selectedKind = state.editorKind;
  state.selectedId = null;
  resetEditor();
  switchView("list");
  setStatus(`Deleted ${deletedId}.`, { tone: "success" });
}

function handleEditorBack() {
  resetEditor();
  switchView(findSelectedEntry() ? "detail" : "list");
}

function resetEditor() {
  state.editorMode = "idle";
  state.editorSourceId = null;
  state.editorKind = state.selectedKind;
  state.editorInputMode = "form";
  state.editorDraft = null;
  state.editorStepIndex = 0;
  state.editorVariantIndex = 0;
  state.editorJsonText = "";
  clearEditorError();
}

function toggleDetailMenu() {
  state.detailMenuOpen = !state.detailMenuOpen;
  renderDetailMenu();
}

function closeDetailMenu() {
  state.detailMenuOpen = false;
  renderDetailMenu();
}

function renderDetailMenu() {
  dom.detailMenu.hidden = !state.detailMenuOpen;
  dom.detailMenuButton.setAttribute("aria-expanded", String(state.detailMenuOpen));
}

function toggleCreateMenu() {
  state.createMenuOpen = !state.createMenuOpen;
  renderCreateMenu();
}

function closeCreateMenu() {
  state.createMenuOpen = false;
  renderCreateMenu();
}

function renderCreateMenu() {
  if (!dom.createEntryMenu) {
    return;
  }

  dom.createEntryMenu.hidden = !state.createMenuOpen;
  dom.createEntryButton.setAttribute("aria-expanded", String(state.createMenuOpen));

  if (!state.createMenuOpen) {
    return;
  }

  dom.createEntryMenu.replaceChildren(...createCreateMenuItems(state.selectedKind));
}

function createCreateMenuItems(kind) {
  const items = [];
  if (kind === "tracks") {
    items.push(
      createMenuItem("New Project track", () => runAction(() => loadCreateDraft("tracks", { lane: "project" }))),
      createMenuItem("New DSA track", () => runAction(() => loadCreateDraft("tracks", { lane: "dsa" }))),
      createMenuItem("New LeetCode set", () =>
        runAction(() => loadCreateDraft("tracks", { lane: "leetcode" })),
      ),
    );
    return items;
  }

  if (kind === "exercises") {
    items.push(
      createMenuItem("New Project exercise", () =>
        runAction(() => loadCreateDraft("exercises", { lane: "project" })),
      ),
      createMenuItem("New DSA exercise", () => runAction(() => loadCreateDraft("exercises", { lane: "dsa" }))),
      createMenuItem("New LeetCode exercise", () =>
        runAction(() => loadCreateDraft("exercises", { lane: "leetcode" })),
      ),
    );
    return items;
  }

  items.push(createMenuItem(`New ${entityLabel(kind).toLowerCase()}`, () => runAction(() => loadCreateDraft(kind))));
  return items;
}

function createMenuItem(label, onClick) {
  const button = document.createElement("button");
  button.type = "button";
  button.className = "menu-item";
  button.textContent = label;
  button.addEventListener("click", (event) => {
    event.preventDefault();
    event.stopPropagation();
    closeCreateMenu();
    onClick();
  });
  return button;
}

function clearListFilters() {
  state.searchQuery = "";
  state.laneFilter = "";
  state.levelFilter = "";
  state.languageFilter = "";
  state.statusFilter = "";
  state.topicFilter = "";
  state.domainFilter = "";
  state.tagFilter = "";

  dom.searchInput.value = "";
  dom.laneFilter.value = "";
  dom.levelFilter.value = "";
  dom.languageFilter.value = "";
  dom.statusFilter.value = "";
  dom.topicFilter.value = "";
  dom.domainFilter.value = "";
  dom.tagFilter.value = "";

  renderListScreen();
}

function visibleEntries() {
  return currentEntries().filter((item) => matchesFilters(item));
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
  if (supportsLaneLevelFilters()) {
    if (state.laneFilter && String(item.draft.lane || "") !== state.laneFilter) {
      return false;
    }
    if (state.levelFilter && String(item.draft.level || "") !== state.levelFilter) {
      return false;
    }
    if (state.topicFilter) {
      const topics = Array.isArray(item.draft.topicIds) ? item.draft.topicIds : [];
      if (!topics.includes(state.topicFilter)) {
        return false;
      }
    }
    if (state.domainFilter) {
      const domains = Array.isArray(item.draft.domainIds) ? item.draft.domainIds : [];
      if (!domains.includes(state.domainFilter)) {
        return false;
      }
    }
    if (state.tagFilter) {
      const requiredTags = parseStringList(state.tagFilter);
      const tags = Array.isArray(item.draft.tags) ? item.draft.tags : [];
      if (requiredTags.length && !requiredTags.every((tag) => tags.includes(tag))) {
        return false;
      }
    }
    if (state.languageFilter) {
      if (state.selectedKind === "exercises") {
        const variants = Array.isArray(item.draft.languageVariants) ? item.draft.languageVariants : [];
        if (!variants.some((variant) => String(variant.languageId || "") === state.languageFilter)) {
          return false;
        }
      } else if (state.selectedKind === "tracks") {
        if (!trackSupportsLanguage(item, state.languageFilter)) {
          return false;
        }
      }
    }
  }
  if (!state.searchQuery) {
    return true;
  }

  const haystack = JSON.stringify(item.draft).toLowerCase();
  return haystack.includes(state.searchQuery) || String(item.id).toLowerCase().includes(state.searchQuery);
}

function findSelectedEntry() {
  return findEntry(state.selectedKind, state.selectedId);
}

function findEntry(kind, id) {
  if (!state.catalog || !id) {
    return null;
  }
  return (state.catalog[kind] || []).find((item) => item.id === id) || null;
}

function supportsLaneLevelFilters() {
  return state.selectedKind === "tracks" || state.selectedKind === "exercises";
}

function updateFilterVisibility() {
  const visible = supportsLaneLevelFilters();
  setNodeHidden(dom.laneFilterShell, !visible);
  setNodeHidden(dom.levelFilterShell, !visible);
  setNodeHidden(dom.languageFilterShell, !visible);
  setNodeHidden(dom.topicFilterShell, !visible);
  setNodeHidden(dom.domainFilterShell, !visible);
  setNodeHidden(dom.tagFilterShell, !visible);

  if (!visible) {
    state.laneFilter = "";
    state.levelFilter = "";
    state.languageFilter = "";
    state.topicFilter = "";
    state.domainFilter = "";
    state.tagFilter = "";
    dom.laneFilter.value = "";
    dom.levelFilter.value = "";
    dom.languageFilter.value = "";
    dom.topicFilter.value = "";
    dom.domainFilter.value = "";
    dom.tagFilter.value = "";
  }
}

function setNodeHidden(node, hidden) {
  if (!node) return;
  node.hidden = !!hidden;
}

function hydrateFilterOptions() {
  if (!state.catalog) {
    return;
  }

  hydrateLanguageFilter();
  hydrateTopicFilter();
  hydrateDomainFilter();
  hydrateTagSuggestions();
}

function hydrateLanguageFilter() {
  if (!dom.languageFilter) {
    return;
  }

  const languageLabels = new Map();
  for (const exercise of state.catalog.exercises || []) {
    const variants = Array.isArray(exercise?.draft?.languageVariants)
      ? exercise.draft.languageVariants
      : [];
    for (const variant of variants) {
      const id = String(variant?.languageId || "").trim();
      if (!id) continue;
      const label = String(variant?.languageLabel || id).trim();
      if (!languageLabels.has(id)) {
        languageLabels.set(id, label);
      }
    }
  }

  const options = [{ value: "", label: "All languages" }];
  const sorted = Array.from(languageLabels.entries()).sort((a, b) => a[1].localeCompare(b[1]));
  for (const [id, label] of sorted) {
    options.push({ value: id, label: `${label} (${id})` });
  }

  replaceSelectOptions(dom.languageFilter, options);
  if (!options.some((option) => option.value === state.languageFilter)) {
    state.languageFilter = "";
  }
  dom.languageFilter.value = state.languageFilter;
}

function hydrateTopicFilter() {
  if (!dom.topicFilter) {
    return;
  }

  const topics = Array.isArray(state.catalog.topics) ? state.catalog.topics : [];
  const options = [{ value: "", label: "All topics" }];
  const sorted = [...topics].sort((a, b) =>
    String(a?.draft?.title || a?.id || "").localeCompare(String(b?.draft?.title || b?.id || "")),
  );
  for (const topic of sorted) {
    const id = String(topic?.id || "").trim();
    if (!id) continue;
    const title = String(topic?.draft?.title || id);
    options.push({ value: id, label: `${title} (${id})` });
  }

  replaceSelectOptions(dom.topicFilter, options);
  if (!options.some((option) => option.value === state.topicFilter)) {
    state.topicFilter = "";
  }
  dom.topicFilter.value = state.topicFilter;
}

function hydrateDomainFilter() {
  if (!dom.domainFilter) {
    return;
  }

  const domains = Array.isArray(state.catalog.domains) ? state.catalog.domains : [];
  const options = [{ value: "", label: "All domains" }];
  const sorted = [...domains].sort((a, b) =>
    String(a?.draft?.title || a?.id || "").localeCompare(String(b?.draft?.title || b?.id || "")),
  );
  for (const domain of sorted) {
    const id = String(domain?.id || "").trim();
    if (!id) continue;
    const title = String(domain?.draft?.title || id);
    options.push({ value: id, label: `${title} (${id})` });
  }

  replaceSelectOptions(dom.domainFilter, options);
  if (!options.some((option) => option.value === state.domainFilter)) {
    state.domainFilter = "";
  }
  dom.domainFilter.value = state.domainFilter;
}

function hydrateTagSuggestions() {
  if (!dom.tagSuggestions) {
    return;
  }

  const tags = new Set();
  const suggestions = Array.isArray(state.catalog.tagSuggestions) ? state.catalog.tagSuggestions : [];
  for (const tag of suggestions) {
    const value = String(tag || "").trim();
    if (value) tags.add(value);
  }
  for (const entry of allEntries()) {
    const entryTags = Array.isArray(entry?.draft?.tags) ? entry.draft.tags : [];
    for (const tag of entryTags) {
      const value = String(tag || "").trim();
      if (value) tags.add(value);
    }
  }

  dom.tagSuggestions.replaceChildren(
    ...Array.from(tags)
      .sort((a, b) => a.localeCompare(b))
      .map((tag) => {
        const option = document.createElement("option");
        option.value = tag;
        return option;
      }),
  );
}

function isNarrowViewport() {
  return window.matchMedia("(max-width: 1180px)").matches;
}

function applySidebarVisibility({ initialize = false } = {}) {
  const narrow = isNarrowViewport();
  if (initialize) {
    state.sidebarVisible = !narrow;
  } else if (!narrow) {
    state.sidebarVisible = true;
  }

  if (dom.sidebarToggle) {
    dom.sidebarToggle.hidden = !narrow;
    dom.sidebarToggle.textContent = state.sidebarVisible ? "Close menu" : "Menu";
  }
  if (dom.sidebar) {
    dom.sidebar.hidden = narrow ? !state.sidebarVisible : false;
  }
}

function toggleSidebarVisibility() {
  if (!isNarrowViewport()) {
    return;
  }
  state.sidebarVisible = !state.sidebarVisible;
  applySidebarVisibility();
}

function parseEditorJson() {
  try {
    return JSON.parse(state.editorJsonText || dom.editorTextarea.value);
  } catch (error) {
    throw new Error(`Editor JSON is invalid: ${error.message}`);
  }
}

function clearEditorError() {
  if (!dom.editorError) {
    return;
  }
  dom.editorError.hidden = true;
  dom.editorError.textContent = "";
}

function setEditorError(message) {
  if (!dom.editorError) {
    return;
  }
  dom.editorError.hidden = false;
  dom.editorError.textContent = message;
}

function structuredCloneSafe(value) {
  if (typeof structuredClone === "function") {
    try {
      return structuredClone(value);
    } catch {
      // fall through
    }
  }
  return JSON.parse(JSON.stringify(value));
}

function guessDefaultVariantIndex(draft) {
  const variants = Array.isArray(draft?.languageVariants) ? draft.languageVariants : [];
  const index = variants.findIndex((variant) => variant && variant.isDefault);
  return index >= 0 ? index : 0;
}

async function toggleEditorInputMode() {
  if (state.editorMode === "idle" || !state.editorDraft) {
    return;
  }
  clearEditorError();

  if (state.editorInputMode === "form") {
    const draft = collectEditorDraftFromForm();
    state.editorDraft = structuredCloneSafe(draft);
    state.editorJsonText = JSON.stringify(draft, null, 2);
    state.editorInputMode = "json";
  } else {
    const parsed = parseEditorJson();
    state.editorDraft = structuredCloneSafe(parsed);
    state.editorVariantIndex = guessDefaultVariantIndex(state.editorDraft);
    state.editorJsonText = "";
    state.editorInputMode = "form";
  }

  renderEditorScreen();
}

function collectEditorPayload() {
  if (state.editorMode === "idle" || !state.editorDraft) {
    throw new Error("Load a draft first.");
  }

  clearEditorError();
  if (state.editorInputMode === "json") {
    const payload = parseEditorJson();
    state.editorDraft = structuredCloneSafe(payload);
    return payload;
  }

  const payload = collectEditorDraftFromForm();
  state.editorDraft = structuredCloneSafe(payload);
  return payload;
}

function collectEditorDraftFromForm() {
  try {
    if (!state.editorDraft) {
      throw new Error("Load a draft first.");
    }

    if (state.editorKind === "exercises") {
      persistActiveExerciseVariantFromForm();
    }

    if (state.editorKind === "tracks") {
      return collectTrackDraftFromForm();
    }
    if (state.editorKind === "exercises") {
      return collectExerciseDraftFromForm();
    }
    if (state.editorKind === "topics") {
      return collectTopicDraftFromForm();
    }
    if (state.editorKind === "domains") {
      return collectDomainDraftFromForm();
    }
    return collectSkillDraftFromForm();
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    setEditorError(message);
    throw error;
  }
}

function readFormValue(name, fallback = "") {
  const element = dom.editorFormShell.querySelector(`[name="${name}"]`);
  if (!element) {
    return fallback;
  }
  if (element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement) {
    return element.value;
  }
  if (element instanceof HTMLSelectElement) {
    return element.value;
  }
  return fallback;
}

function readFormChecked(name) {
  const element = dom.editorFormShell.querySelector(`[name="${name}"]`);
  if (!element || !(element instanceof HTMLInputElement)) {
    return false;
  }
  return element.checked;
}

function readFormCheckedValues(name) {
  const elements = dom.editorFormShell.querySelectorAll(`input[name="${name}"]:checked`);
  return Array.from(elements)
    .filter((element) => element instanceof HTMLInputElement)
    .map((element) => element.value);
}

function parseStringList(value) {
  return String(value || "")
    .split(/[\n,]/g)
    .map((item) => item.trim())
    .filter(Boolean);
}

function parseJsonField(raw, { fallback, label }) {
  const text = String(raw ?? "").trim();
  if (!text) {
    return fallback;
  }
  try {
    return JSON.parse(text);
  } catch (error) {
    throw new Error(`${label} JSON is invalid: ${error.message}`);
  }
}

function collectBaseDefinitionFields() {
  const id = readFormValue("id", state.editorSourceId || state.editorDraft?.id || "").trim();
  const title = readFormValue("title").trim();
  const summary = readFormValue("summary").trim();
  return { id, title, summary };
}

function collectTrackDraftFromForm() {
  const { id, title, summary } = collectBaseDefinitionFields();
  const lane = readFormValue("lane", "project");
  const contentKind = readFormValue("contentKind", lane === "leetcode" ? "leetcode_set" : lane === "dsa" ? "dsa_track" : "project_track");
  const level = readFormValue("level", "foundation");

  const exerciseRefsRaw = readFormValue("exerciseRefs", "");
  const exerciseIds = parseStringList(exerciseRefsRaw);
  const exerciseRefs = exerciseIds.map((exerciseId) => ({ exerciseId }));

  return {
    id,
    title,
    summary,
    lane,
    contentKind,
    level,
    topicIds: parseStringList(readFormValue("topicIds")),
    domainIds: parseStringList(readFormValue("domainIds")),
    tags: parseStringList(readFormValue("tags")),
    skillIds: parseStringList(readFormValue("skillIds")),
    exerciseRefs,
  };
}

function collectExerciseDraftFromForm() {
  const { id, title, summary } = collectBaseDefinitionFields();
  const lane = readFormValue("lane", "project");
  const contentKind = readFormValue("contentKind", lane === "leetcode" ? "leetcode_exercise" : lane === "dsa" ? "dsa_exercise" : "project_exercise");
  const level = readFormValue("level", "foundation");
  const supportedModes = readFormCheckedValues("supportedModes");

  return {
    id,
    title,
    summary,
    lane,
    contentKind,
    level,
    topicIds: parseStringList(readFormValue("topicIds")),
    domainIds: parseStringList(readFormValue("domainIds")),
    tags: parseStringList(readFormValue("tags")),
    skillIds: parseStringList(readFormValue("skillIds")),
    problemStatement: readFormValue("problemStatement"),
    acceptanceCriteria: parseStringList(readFormValue("acceptanceCriteria")),
    taskSteps: parseJsonField(readFormValue("taskSteps"), {
      fallback: [],
      label: "Task steps",
    }),
    supportedModes: supportedModes.length ? supportedModes : ["guided"],
    hints: parseJsonField(readFormValue("hints"), {
      fallback: {},
      label: "Hints",
    }),
    reflectionPrompts: parseStringList(readFormValue("reflectionPrompts")),
    requirements: parseJsonField(readFormValue("requirements"), {
      fallback: [],
      label: "Requirements",
    }),
    languageVariants: Array.isArray(state.editorDraft.languageVariants)
      ? state.editorDraft.languageVariants
      : [],
  };
}

function collectTopicDraftFromForm() {
  const { id, title, summary } = collectBaseDefinitionFields();
  return { id, title, summary };
}

function collectDomainDraftFromForm() {
  const { id, title, summary } = collectBaseDefinitionFields();
  return { id, title, summary };
}

function collectSkillDraftFromForm() {
  const id = readFormValue("id", state.editorSourceId || state.editorDraft?.id || "").trim();
  const title = readFormValue("title").trim();
  return {
    id,
    title,
    category: readFormValue("category").trim(),
    description: readFormValue("description"),
    reviewExerciseId: readFormValue("reviewExerciseId").trim(),
  };
}

function persistActiveExerciseVariantFromForm() {
  if (!state.editorDraft || state.editorKind !== "exercises") {
    return;
  }
  const variants = Array.isArray(state.editorDraft.languageVariants)
    ? state.editorDraft.languageVariants
    : [];
  if (variants.length === 0) {
    state.editorDraft.languageVariants = [defaultLanguageVariant({ isDefault: true })];
    state.editorVariantIndex = 0;
    return;
  }

  const activeIndex = Math.min(Math.max(state.editorVariantIndex, 0), variants.length - 1);
  const starterFiles = parseJsonField(readFormValue("variantStarterFiles"), {
    fallback: {},
    label: "Starter files",
  });
  const testCases = parseJsonField(readFormValue("variantTestCases"), {
    fallback: [],
    label: "Test cases",
  });

  const updated = {
    ...variants[activeIndex],
    languageId: readFormValue("variantLanguageId").trim(),
    languageLabel: readFormValue("variantLanguageLabel").trim(),
    isDefault: readFormChecked("variantIsDefault"),
    starterCode: readFormValue("variantStarterCode"),
    starterFiles,
    solutionCode: (() => {
      const raw = readFormValue("variantSolutionCode");
      return raw.trim() ? raw : null;
    })(),
    sandboxHarnessTemplate: readFormValue("variantSandboxHarnessTemplate"),
    runCommand: readFormValue("variantRunCommand").trim(),
    entryFilePath: readFormValue("variantEntryFilePath").trim(),
    demoFilePath: (() => {
      const raw = readFormValue("variantDemoFilePath");
      return raw.trim() ? raw.trim() : null;
    })(),
    testCases,
  };

  variants[activeIndex] = updated;

  const defaultIndex = variants.findIndex((variant) => variant && variant.isDefault);
  if (defaultIndex < 0) {
    variants[0].isDefault = true;
  } else {
    for (let i = 0; i < variants.length; i += 1) {
      if (i !== defaultIndex) {
        variants[i].isDefault = false;
      }
    }
  }

  state.editorDraft.languageVariants = variants;
}

function defaultLanguageVariant({ languageId = "python", languageLabel = "Python", isDefault = false } = {}) {
  return {
    languageId,
    languageLabel,
    isDefault,
    starterCode: "",
    starterFiles: {},
    solutionCode: null,
    sandboxHarnessTemplate: "{{USER_CODE}}\n\n{{TEST_BODY}}\n",
    runCommand: languageId === "python" ? "python main.py" : "",
    entryFilePath: "main.py",
    demoFilePath: null,
    testCases: [],
  };
}

function renderEditorForm() {
  dom.editorFormShell.replaceChildren();
  if (!state.editorDraft) {
    return;
  }

  const form = document.createElement("form");
  form.addEventListener("submit", (event) => event.preventDefault());

  if (state.editorKind === "tracks") {
    form.appendChild(renderTrackForm(state.editorDraft));
  } else if (state.editorKind === "exercises") {
    form.appendChild(renderExerciseForm(state.editorDraft));
  } else if (state.editorKind === "topics" || state.editorKind === "domains") {
    form.appendChild(renderSimpleTaxonomyForm(state.editorDraft, entityLabel(state.editorKind)));
  } else {
    form.appendChild(renderSkillForm(state.editorDraft));
  }

  dom.editorFormShell.appendChild(form);
}

function createEditorWizard(steps) {
  const wizard = document.createElement("div");
  wizard.className = "editor-form-shell editor-wizard";

  const nav = document.createElement("nav");
  nav.className = "wizard-nav";

  const panels = document.createElement("div");
  panels.className = "wizard-panels";

  const stepButtons = [];
  steps.forEach((step, index) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "wizard-step";
    button.textContent = step.title;
    button.addEventListener("click", () => setEditorWizardStep(wizard, steps.length, index));
    stepButtons.push(button);
    nav.appendChild(button);

    step.section.dataset.wizardStep = String(index);
    panels.appendChild(step.section);
  });

  const controls = document.createElement("div");
  controls.className = "wizard-controls";
  const previous = document.createElement("button");
  previous.type = "button";
  previous.className = "ghost-button wizard-prev";
  previous.textContent = "Previous";
  previous.addEventListener("click", () =>
    setEditorWizardStep(wizard, steps.length, state.editorStepIndex - 1),
  );
  const next = document.createElement("button");
  next.type = "button";
  next.className = "secondary-button wizard-next";
  next.textContent = "Next";
  next.addEventListener("click", () =>
    setEditorWizardStep(wizard, steps.length, state.editorStepIndex + 1),
  );
  controls.append(previous, next);

  wizard.append(nav, panels, controls);
  applyEditorWizardState(wizard, steps.length, { stepButtons, previous, next });
  return wizard;
}

function applyEditorWizardState(wizard, stepsCount, { stepButtons, previous, next }) {
  const active = Math.min(Math.max(state.editorStepIndex, 0), Math.max(stepsCount - 1, 0));
  state.editorStepIndex = active;

  stepButtons.forEach((button, index) => {
    button.classList.toggle("active", index === active);
    button.setAttribute("aria-current", index === active ? "step" : "false");
  });

  wizard.querySelectorAll("[data-wizard-step]").forEach((panel) => {
    panel.hidden = Number(panel.dataset.wizardStep) !== active;
  });

  previous.disabled = active <= 0;
  next.disabled = active >= stepsCount - 1;
  next.textContent = active >= stepsCount - 1 ? "Done" : "Next";
}

function setEditorWizardStep(wizard, stepsCount, index) {
  state.editorStepIndex = Math.min(Math.max(index, 0), Math.max(stepsCount - 1, 0));
  const stepButtons = Array.from(wizard.querySelectorAll(".wizard-step"));
  const previous = wizard.querySelector(".wizard-controls .wizard-prev");
  const next = wizard.querySelector(".wizard-controls .wizard-next");
  applyEditorWizardState(wizard, stepsCount, { stepButtons, previous, next });
  wizard.scrollIntoView({ block: "start" });
}

function renderTrackForm(draft) {
  const basics = renderBasicsSection(draft, { includeLaneLevel: true, isTrack: true });
  const taxonomy = renderTaxonomySection(draft);

  const structure = createEditorSection("Structure");
  const grid = createFormGrid({ columns: 1 });
  grid.appendChild(
    createTextareaField({
      name: "exerciseRefs",
      label: "Exercise refs (one exerciseId per line)",
      value: Array.isArray(draft.exerciseRefs)
        ? draft.exerciseRefs.map((ref) => ref.exerciseId).filter(Boolean).join("\n")
        : "",
      placeholder: "project_list_documents\nproject_update_document",
      className: "textarea-medium",
      help:
        "Ordered list of exercise ids for this track. Learner app will walk through these in order.",
      sample: "project_list_documents\nproject_update_document",
    }),
  );
  structure.appendChild(grid);
  return createEditorWizard([
    { title: "Basics", section: basics },
    { title: "Taxonomy", section: taxonomy },
    { title: "Structure", section: structure },
  ]);
}

function renderExerciseForm(draft) {
  const basics = renderBasicsSection(draft, { includeLaneLevel: true, isTrack: false });
  const taxonomy = renderTaxonomySection(draft);

  const content = createEditorSection("Content");
  const contentGrid = createFormGrid({ columns: 1 });
  contentGrid.appendChild(
    createTextareaField({
      name: "problemStatement",
      label: "Problem statement",
      value: String(draft.problemStatement || ""),
      placeholder: "Describe the goal, constraints, and expected behavior…",
      className: "textarea-medium",
      help:
        "The learner-facing prompt. Include the real-world scenario, constraints, and what 'done' looks like.",
      sample:
        "You are building a Document API. Implement listDocuments(params) with pagination and filters.\nConstraints: stable ordering, handle empty input.",
    }),
  );
  contentGrid.appendChild(
    createTextareaField({
      name: "acceptanceCriteria",
      label: "Acceptance criteria (one per line)",
      value: Array.isArray(draft.acceptanceCriteria)
        ? draft.acceptanceCriteria.join("\n")
        : "",
      placeholder: "Returns the correct result\nHandles empty input",
      help: "Checklist shown at the end of the session to self-verify correctness.",
      sample: "Returns the correct result\nHandles empty input\nDoes not mutate input",
    }),
  );
  contentGrid.appendChild(
    createTextareaField({
      name: "reflectionPrompts",
      label: "Reflection prompts (one per line)",
      value: Array.isArray(draft.reflectionPrompts)
        ? draft.reflectionPrompts.join("\n")
        : "",
      placeholder: "What trade-offs did you consider?\nHow would you test edge-cases?",
      help: "Prompts used after completion to reinforce reasoning and review memory.",
      sample:
        "What trade-offs did you consider?\nHow would you test edge-cases?\nWhat would you improve in a follow-up refactor?",
    }),
  );
  content.appendChild(contentGrid);

  const workflow = createEditorSection("Execution");
  const workflowGrid = createFormGrid({ columns: 1 });
  workflowGrid.appendChild(
    createCheckboxGroupField({
      name: "supportedModes",
      label: "Modes",
      options: [
        { value: "guided", label: "Guided" },
        { value: "standard", label: "Standard" },
      ],
      selected: Array.isArray(draft.supportedModes) ? draft.supportedModes : [],
      help:
        "Guided shows more coaching, Standard is closer to a blank editor. You can enable both.",
    }),
  );
  workflow.appendChild(workflowGrid);

  const advanced = createEditorSection("Advanced");
  const advancedGrid = createFormGrid({ columns: 1 });
  advancedGrid.appendChild(
    createTextareaField({
      name: "hints",
      label: "Hints (JSON map)",
      value: JSON.stringify(draft.hints || {}, null, 2),
      placeholder: "{\n  \"tip\": \"Try using a hash map\"\n}",
      help:
        "Optional hints keyed by hint level. Keys are arbitrary but should stay consistent across exercises.",
      sample: "{\n  \"foundation\": \"Start with a loop.\",\n  \"intermediate\": \"Consider a hash map.\",\n  \"advanced\": \"Think about time/space trade-offs.\"\n}",
    }),
  );
  advancedGrid.appendChild(
    createTextareaField({
      name: "taskSteps",
      label: "Task steps (JSON array)",
      value: JSON.stringify(draft.taskSteps || [], null, 2),
      placeholder: "[{\"id\":\"step1\",\"title\":\"\",\"description\":\"\"}]",
      help:
        "Optional structured steps for multi-part exercises. Used by the guided mode and review summaries.",
      sample:
        "[\n  {\"id\":\"step1\",\"title\":\"Parse input\",\"description\":\"Read params and validate\"},\n  {\"id\":\"step2\",\"title\":\"Query\",\"description\":\"Build the SQL query\"}\n]",
    }),
  );
  advancedGrid.appendChild(
    createTextareaField({
      name: "requirements",
      label: "Requirements (JSON array)",
      value: JSON.stringify(draft.requirements || [], null, 2),
      placeholder: "[{\"label\":\"\",\"pattern\":\"\",\"feedback\":\"\"}]",
      help:
        "Optional regex-based checks for the learner's code. Use sparingly (prefer tests when possible).",
      sample:
        "[\n  {\"label\":\"Uses pagination\",\"pattern\":\"limit\\\\s+\\\\d+\",\"feedback\":\"Add a LIMIT clause for pagination.\"}\n]",
    }),
  );
  advanced.appendChild(advancedGrid);

  const variants = renderExerciseVariantsSection(draft);

  return createEditorWizard([
    { title: "Basics", section: basics },
    { title: "Taxonomy", section: taxonomy },
    { title: "Content", section: content },
    { title: "Execution", section: workflow },
    { title: "Advanced", section: advanced },
    { title: "Languages", section: variants },
  ]);
}

function renderSimpleTaxonomyForm(draft, label) {
  const shell = document.createElement("div");
  shell.className = "editor-form-shell";
  const basics = createEditorSection("Basics");
  const grid = createFormGrid({ columns: 2 });
  grid.appendChild(
    createTextField({
      name: "id",
      label: `${label} id`,
      value: draft.id || "",
      readOnly: state.editorMode === "edit",
      help: `Stable identifier referenced by content entries.`,
      sample: label.toLowerCase() === "topic" ? "sql" : "document-management",
    }),
  );
  grid.appendChild(
    createTextField({
      name: "title",
      label: `${label} title`,
      value: draft.title || "",
      help: "Human-friendly label shown in pickers and badges.",
      sample: label.toLowerCase() === "topic" ? "SQL" : "Document Management",
    }),
  );
  const summaryField = createTextareaField({
    name: "summary",
    label: "Summary",
    value: String(draft.summary || ""),
    className: "textarea-medium",
    help: "Optional description for the taxonomy entry.",
  });
  summaryField.classList.add("field-span-all");
  grid.appendChild(summaryField);
  basics.appendChild(grid);
  shell.appendChild(basics);
  return shell;
}

function renderSkillForm(draft) {
  const shell = document.createElement("div");
  shell.className = "editor-form-shell";

  const basics = createEditorSection("Basics");
  const grid = createFormGrid({ columns: 2 });
  grid.appendChild(
    createTextField({
      name: "id",
      label: "Skill id",
      value: draft.id || "",
      readOnly: state.editorMode === "edit",
      help: "Stable identifier referenced by exercises via skillIds.",
      sample: "sql_basics",
    }),
  );
  grid.appendChild(
    createTextField({
      name: "title",
      label: "Title",
      value: draft.title || "",
      help: "Human-friendly title shown in review cards.",
      sample: "SQL Basics",
    }),
  );
  grid.appendChild(
    createTextField({
      name: "category",
      label: "Category",
      value: draft.category || "",
      help: "Used to group skills in the admin list. Keep categories stable.",
      sample: "languageSyntax",
    }),
  );
  grid.appendChild(
    createTextField({
      name: "reviewExerciseId",
      label: "Review exercise id",
      value: draft.reviewExerciseId || "",
      help: "Optional shortcut exercise used during review sessions.",
      sample: "project_list_documents",
    }),
  );
  grid.appendChild(
    createTextareaField({
      name: "description",
      label: "Description",
      value: String(draft.description || ""),
      className: "textarea-medium",
      help: "Shown to the learner when reviewing this skill.",
    }),
  );
  basics.appendChild(grid);
  shell.appendChild(basics);
  return shell;
}

function renderBasicsSection(draft, { includeLaneLevel, isTrack }) {
  const section = createEditorSection("Basics");
  const grid = createFormGrid({ columns: includeLaneLevel ? 3 : 2 });

  grid.appendChild(
    createTextField({
      name: "id",
      label: "ID",
      value: draft.id || "",
      readOnly: state.editorMode === "edit",
      help:
        "Stable identifier referenced by tracks, skills, and the learner app. Prefer lowercase snake_case.",
      sample: isTrack ? "project_foundations_track" : "project_list_documents",
    }),
  );
  grid.appendChild(
    createTextField({
      name: "title",
      label: "Title",
      value: draft.title || "",
      help: "Human-friendly title shown in lists and headers.",
      sample: isTrack ? "Document Management" : "List documents",
    }),
  );

  if (includeLaneLevel) {
    const lane = String(draft.lane || "project");
    const contentKind = String(draft.contentKind || (isTrack ? "project_track" : "project_exercise"));
    const laneField = createSelectField({
      name: "lane",
      label: "Lane",
      value: lane,
      options: [
        { value: "project", label: "Project" },
        { value: "dsa", label: "DSA" },
        { value: "leetcode", label: "LeetCode" },
      ],
      help:
        "Controls which learner surface this appears in and which contentKind options are allowed.",
    });
    const kindField = createSelectField({
      name: "contentKind",
      label: "Content kind",
      value: contentKind,
      options: contentKindOptionsFor(lane, { isTrack }),
      help: "Derived from lane. Keep it consistent unless you have a custom kind.",
    });
    const levelField = createSelectField({
      name: "level",
      label: "Level",
      value: String(draft.level || "foundation"),
      options: [
        { value: "foundation", label: "Foundation" },
        { value: "intermediate", label: "Intermediate" },
        { value: "advanced", label: "Advanced" },
      ],
      help: "Difficulty tier used for filtering and learner progression.",
    });

    const laneSelect = laneField.querySelector("select");
    const kindSelect = kindField.querySelector("select");
    laneSelect.addEventListener("change", () => {
      const nextLane = laneSelect.value;
      const nextOptions = contentKindOptionsFor(nextLane, { isTrack });
      replaceSelectOptions(kindSelect, nextOptions);
      if (!nextOptions.some((option) => option.value === kindSelect.value)) {
        kindSelect.value = nextOptions[0]?.value || "";
      }
    });

    grid.appendChild(laneField);
    grid.appendChild(kindField);
    grid.appendChild(levelField);
  }

  const summaryField = createTextareaField({
    name: "summary",
    label: "Summary",
    value: String(draft.summary || ""),
    className: "textarea-medium",
    help: "One-paragraph preview shown in the list and detail summary card.",
    sample:
      isTrack
        ? "A curated path through the key milestones of a document service."
        : "Build the list endpoint with filtering, pagination, and stable ordering.",
  });
  summaryField.classList.add("field-span-all");
  grid.appendChild(summaryField);

  section.appendChild(grid);
  return section;
}

function renderTaxonomySection(draft) {
  const section = createEditorSection("Taxonomy");
  const grid = createFormGrid({ columns: 2 });
  const topicSuggestions = (state.catalog?.topics || [])
    .map((topic) => ({
      value: String(topic?.id || ""),
      label: String(topic?.draft?.title || topic?.id || ""),
    }))
    .filter((option) => option.value);
  const domainSuggestions = (state.catalog?.domains || [])
    .map((domain) => ({
      value: String(domain?.id || ""),
      label: String(domain?.draft?.title || domain?.id || ""),
    }))
    .filter((option) => option.value);
  const skillSuggestions = (state.catalog?.skills || [])
    .map((skill) => ({
      value: String(skill?.id || ""),
      label: String(skill?.draft?.title || skill?.id || ""),
    }))
    .filter((option) => option.value);
  const tagSuggestions = Array.from(
    new Set([
      ...((state.catalog?.tagSuggestions || []).map((tag) => String(tag || "").trim()).filter(Boolean)),
      ...((draft.tags || []).map((tag) => String(tag || "").trim()).filter(Boolean)),
    ]),
  )
    .sort((a, b) => a.localeCompare(b))
    .map((tag) => ({ value: tag, label: tag }));

  grid.appendChild(
    createTokenListField({
      name: "topicIds",
      label: "Topics",
      values: Array.isArray(draft.topicIds) ? draft.topicIds : [],
      suggestions: topicSuggestions,
      placeholder: "Type a topic id and press Enter…",
      help: "Curated topic taxonomy. Add multiple topics to improve filtering.",
      sample: "sql\nconcurrency\nrace-condition",
    }),
  );
  grid.appendChild(
    createTokenListField({
      name: "domainIds",
      label: "Domains",
      values: Array.isArray(draft.domainIds) ? draft.domainIds : [],
      suggestions: domainSuggestions,
      placeholder: "Type a domain id and press Enter…",
      help: "Curated domain taxonomy. Domains describe the real-world system context.",
      sample: "document-management\nmessaging-system\ntransaction-service",
    }),
  );
  grid.appendChild(
    createTokenListField({
      name: "tags",
      label: "Tags",
      values: Array.isArray(draft.tags) ? draft.tags : [],
      suggestions: tagSuggestions,
      placeholder: "Type a tag and press Enter…",
      help: "Free-form keywords for cross-cutting filters.",
      sample: "list\nquery\npagination\ncache",
    }),
  );
  grid.appendChild(
    createTokenListField({
      name: "skillIds",
      label: "Skills",
      values: Array.isArray(draft.skillIds) ? draft.skillIds : [],
      suggestions: skillSuggestions,
      placeholder: "Type a skill id and press Enter…",
      help: "Skills power the review queue. Add only the skills you want to be reviewable.",
      sample: "sql_basics\nhttp_status_codes\nidempotency",
    }),
  );
  section.appendChild(grid);
  return section;
}

function renderExerciseVariantsSection(draft) {
  const section = createEditorSection("Language variants");
  section.dataset.variantSection = "exercises";
  renderExerciseVariantsBody(section, draft);
  return section;
}

function renderExerciseVariantsBody(section, draft) {
  const header = section.querySelector(".section-title");
  section.replaceChildren();
  if (header) {
    section.appendChild(header);
  }

  if (!state.editorDraft) {
    return;
  }

  const variants = Array.isArray(state.editorDraft?.languageVariants)
    ? state.editorDraft.languageVariants
    : Array.isArray(draft.languageVariants)
      ? draft.languageVariants
      : [];
  if (variants.length === 0) {
    state.editorDraft.languageVariants = [defaultLanguageVariant({ isDefault: true })];
  }
  const activeIndex = Math.min(
    Math.max(state.editorVariantIndex, 0),
    (state.editorDraft.languageVariants || []).length - 1,
  );
  state.editorVariantIndex = activeIndex;

  const tabs = document.createElement("div");
  tabs.className = "variant-tabs";
  state.editorDraft.languageVariants.forEach((variant, index) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `variant-tab ${index === activeIndex ? "active" : ""}`;
    const title = variant.languageLabel || variant.languageId || `Variant ${index + 1}`;
    button.textContent = variant.isDefault ? `${title} *` : title;
    button.addEventListener("click", () => runAction(() => selectExerciseVariant(section, index)));
    tabs.appendChild(button);
  });

  const addButton = document.createElement("button");
  addButton.type = "button";
  addButton.className = "secondary-button";
  addButton.textContent = "+ Variant";
  addButton.addEventListener("click", () => runAction(() => addExerciseVariant(section)));
  tabs.appendChild(addButton);

  const removeButton = document.createElement("button");
  removeButton.type = "button";
  removeButton.className = "danger-button";
  removeButton.textContent = "Remove";
  removeButton.disabled = state.editorDraft.languageVariants.length <= 1;
  removeButton.addEventListener("click", () => runAction(() => removeExerciseVariant(section)));
  tabs.appendChild(removeButton);

  section.appendChild(tabs);

  const active = state.editorDraft.languageVariants[activeIndex];
  const grid = createFormGrid({ columns: 3 });
  grid.appendChild(
    createTextField({
      name: "variantLanguageId",
      label: "Language id",
      value: active.languageId || "",
      help: "Short stable id used for filtering and preference (e.g. python, csharp).",
      sample: "python",
    }),
  );
  grid.appendChild(
    createTextField({
      name: "variantLanguageLabel",
      label: "Label",
      value: active.languageLabel || "",
      help: "Human-friendly label shown to learners.",
      sample: "Python",
    }),
  );
  grid.appendChild(
    createCheckboxField({
      name: "variantIsDefault",
      label: "Default",
      checked: !!active.isDefault,
      help: "The default language chosen when the learner has no preference set.",
    }),
  );

  const runGrid = createFormGrid({ columns: 2 });
  runGrid.appendChild(
    createTextField({
      name: "variantRunCommand",
      label: "Run command",
      value: active.runCommand || "",
      help: "Command used inside the sandbox to run the entry file.",
      sample: "python main.py",
    }),
  );
  runGrid.appendChild(
    createTextField({
      name: "variantEntryFilePath",
      label: "Entry file path",
      value: active.entryFilePath || "",
      help: "Main file path that the sandbox executes.",
      sample: "main.py",
    }),
  );
  runGrid.appendChild(
    createTextField({
      name: "variantDemoFilePath",
      label: "Demo file path (optional)",
      value: active.demoFilePath || "",
      help: "Optional file to show as a starting point in the UI.",
      sample: "demo.py",
    }),
  );
  const solutionField = createTextareaField({
    name: "variantSolutionCode",
    label: "Solution code (optional)",
    value: active.solutionCode || "",
    className: "textarea-medium textarea-code",
    help: "Optional reference solution for internal use or previews.",
  });
  solutionField.classList.add("field-span-all");
  runGrid.appendChild(solutionField);

  const codeGrid = createFormGrid({ columns: 1 });
  codeGrid.appendChild(
    createTextareaField({
      name: "variantStarterCode",
      label: "Starter code",
      value: active.starterCode || "",
      className: "textarea-code",
      help: "Code shown in the learner editor when starting the exercise.",
      sample: "def list_documents(params):\n    pass\n",
    }),
  );
  codeGrid.appendChild(
    createTextareaField({
      name: "variantSandboxHarnessTemplate",
      label: "Sandbox harness template",
      value: active.sandboxHarnessTemplate || "{{USER_CODE}}\n\n{{TEST_BODY}}\n",
      className: "textarea-medium textarea-code",
      help:
        "Template used to combine user code and test body. Use {{USER_CODE}} and {{TEST_BODY}} placeholders.",
      sample: "{{USER_CODE}}\n\n{{TEST_BODY}}\n",
    }),
  );
  codeGrid.appendChild(
    createTextareaField({
      name: "variantStarterFiles",
      label: "Starter files (JSON map)",
      value: JSON.stringify(active.starterFiles || {}, null, 2),
      placeholder: "{\n  \"helpers.py\": \"\"\n}",
      help: "Additional files written into the sandbox filesystem for this variant.",
      sample: "{\n  \"helpers.py\": \"# helper functions\\n\"\n}",
    }),
  );
  codeGrid.appendChild(
    createTextareaField({
      name: "variantTestCases",
      label: "Test cases (JSON array)",
      value: JSON.stringify(active.testCases || [], null, 2),
      placeholder: "[{\"id\":\"case1\",\"label\":\"\",\"body\":\"\",\"expectedOutput\":\"\"}]",
      help:
        "Optional per-variant tests. For LeetCode lane, include at least one case for each variant.",
      sample:
        "[\n  {\"id\":\"case1\",\"label\":\"empty\",\"body\":\"print(list_documents({}))\",\"expectedOutput\":\"[]\"}\n]",
    }),
  );

  section.appendChild(grid);
  section.appendChild(runGrid);
  section.appendChild(codeGrid);
}

async function selectExerciseVariant(section, index) {
  persistActiveExerciseVariantFromForm();
  state.editorVariantIndex = index;
  renderExerciseVariantsBody(section, state.editorDraft);
}

async function addExerciseVariant(section) {
  persistActiveExerciseVariantFromForm();
  const variants = Array.isArray(state.editorDraft.languageVariants)
    ? state.editorDraft.languageVariants
    : [];
  variants.push(defaultLanguageVariant());
  state.editorDraft.languageVariants = variants;
  state.editorVariantIndex = variants.length - 1;
  renderExerciseVariantsBody(section, state.editorDraft);
}

async function removeExerciseVariant(section) {
  persistActiveExerciseVariantFromForm();
  const variants = Array.isArray(state.editorDraft.languageVariants)
    ? state.editorDraft.languageVariants
    : [];
  if (variants.length <= 1) {
    return;
  }
  variants.splice(state.editorVariantIndex, 1);
  if (variants.length > 0 && !variants.some((variant) => variant.isDefault)) {
    variants[0].isDefault = true;
  }
  state.editorDraft.languageVariants = variants;
  state.editorVariantIndex = Math.min(state.editorVariantIndex, variants.length - 1);
  renderExerciseVariantsBody(section, state.editorDraft);
}

function createEditorSection(title) {
  const section = document.createElement("section");
  section.className = "editor-section";
  const header = document.createElement("p");
  header.className = "section-title";
  header.textContent = title;
  section.appendChild(header);
  return section;
}

function createFormGrid({ columns = 2 } = {}) {
  const grid = document.createElement("div");
  grid.className = columns === 3 ? "form-grid form-grid-3" : "form-grid";
  if (columns === 1) {
    grid.className = "form-grid";
    grid.style.gridTemplateColumns = "1fr";
  }
  return grid;
}

function createFieldLabel({ label, help = "", sample = "" }) {
  const row = document.createElement("div");
  row.className = "field-label";

  const caption = document.createElement("span");
  caption.className = "field-caption";
  caption.textContent = label;
  row.appendChild(caption);

  const tooltip = formatFieldTooltip({ help, sample });
  if (tooltip) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "help-icon";
    button.textContent = "?";
    button.title = tooltip;
    button.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
    });
    row.appendChild(button);
  }

  return row;
}

function formatFieldTooltip({ help = "", sample = "" }) {
  const parts = [];
  const trimmedHelp = String(help || "").trim();
  if (trimmedHelp) {
    parts.push(trimmedHelp);
  }
  const trimmedSample = String(sample || "").trim();
  if (trimmedSample) {
    parts.push(`Example:\n${trimmedSample}`);
  }
  return parts.join("\n\n");
}

function createTextField({ name, label, value, placeholder = "", readOnly = false, help = "", sample = "" }) {
  const shell = document.createElement("label");
  shell.className = "field-shell";
  const labelRow = createFieldLabel({ label, help, sample });
  const input = document.createElement("input");
  input.name = name;
  input.type = "text";
  input.value = String(value ?? "");
  input.placeholder = placeholder;
  input.readOnly = !!readOnly;
  shell.append(labelRow, input);
  return shell;
}

function createTextareaField({ name, label, value, placeholder = "", className = "", help = "", sample = "" }) {
  const shell = document.createElement("label");
  shell.className = "field-shell";
  const labelRow = createFieldLabel({ label, help, sample });
  const textarea = document.createElement("textarea");
  textarea.name = name;
  textarea.value = String(value ?? "");
  textarea.placeholder = placeholder;
  if (className) {
    textarea.className = className;
  }
  shell.append(labelRow, textarea);
  return shell;
}

function createTokenListField({
  name,
  label,
  values,
  suggestions = [],
  placeholder = "",
  help = "",
  sample = "",
}) {
  const shell = document.createElement("div");
  shell.className = "field-shell token-field";
  shell.appendChild(createFieldLabel({ label, help, sample }));

  const suggestionMap = new Map(
    suggestions
      .map((option) => [String(option?.value || "").trim(), String(option?.label || "").trim()])
      .filter(([value]) => value),
  );

  const row = document.createElement("div");
  row.className = "token-row";

  const input = document.createElement("input");
  input.type = "text";
  input.placeholder = placeholder;
  input.autocomplete = "off";

  const datalistId = `${name}-suggestions-${Math.random().toString(16).slice(2)}`;
  let datalist = null;
  if (suggestions.length) {
    datalist = document.createElement("datalist");
    datalist.id = datalistId;
    datalist.replaceChildren(
      ...suggestions.map((option) => {
        const node = document.createElement("option");
        node.value = option.value;
        return node;
      }),
    );
    input.setAttribute("list", datalistId);
  }

  const addButton = document.createElement("button");
  addButton.type = "button";
  addButton.className = "ghost-button";
  addButton.textContent = "Add";

  row.append(input, addButton);
  shell.appendChild(row);

  const chips = document.createElement("div");
  chips.className = "token-chips";
  shell.appendChild(chips);

  const hidden = document.createElement("textarea");
  hidden.name = name;
  hidden.hidden = true;
  shell.appendChild(hidden);
  if (datalist) {
    shell.appendChild(datalist);
  }

  const tokens = Array.isArray(values) ? [...values] : parseStringList(values);

  function sync() {
    hidden.value = tokens.join("\n");
    chips.replaceChildren(
      ...tokens.map((token) => {
        const chip = document.createElement("span");
        chip.className = "token-chip";
        chip.textContent = suggestionMap.get(token) ? `${suggestionMap.get(token)} (${token})` : token;
        if (suggestionMap.get(token)) {
          chip.title = suggestionMap.get(token);
        }

        const remove = document.createElement("button");
        remove.type = "button";
        remove.className = "token-remove";
        remove.textContent = "×";
        remove.addEventListener("click", () => {
          const index = tokens.indexOf(token);
          if (index >= 0) {
            tokens.splice(index, 1);
            sync();
          }
        });

        chip.appendChild(remove);
        return chip;
      }),
    );
  }

  function addToken(raw) {
    const value = String(raw || "").trim();
    if (!value) return;
    if (!tokens.includes(value)) {
      tokens.push(value);
      tokens.sort((a, b) => a.localeCompare(b));
    }
    input.value = "";
    sync();
  }

  addButton.addEventListener("click", () => addToken(input.value));
  input.addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
      event.preventDefault();
      addToken(input.value);
    }
  });

  sync();
  return shell;
}

function createSelectField({ name, label, value, options, help = "", sample = "" }) {
  const shell = document.createElement("label");
  shell.className = "field-shell";
  const labelRow = createFieldLabel({ label, help, sample });
  const select = document.createElement("select");
  select.name = name;
  replaceSelectOptions(select, options);
  select.value = value;
  shell.append(labelRow, select);
  return shell;
}

function replaceSelectOptions(select, options) {
  select.replaceChildren(
    ...options.map((option) => {
      const node = document.createElement("option");
      node.value = option.value;
      node.textContent = option.label;
      return node;
    }),
  );
}

function createCheckboxField({ name, label, checked, help = "", sample = "" }) {
  const shell = document.createElement("label");
  shell.className = "field-shell";
  const labelRow = createFieldLabel({ label, help, sample });
  const inputWrap = document.createElement("div");
  inputWrap.className = "checkbox-row";
  const input = document.createElement("input");
  input.type = "checkbox";
  input.name = name;
  input.checked = !!checked;
  inputWrap.appendChild(input);
  shell.append(labelRow, inputWrap);
  return shell;
}

function createCheckboxGroupField({ name, label, options, selected, help = "", sample = "" }) {
  const shell = document.createElement("div");
  shell.className = "field-shell";
  const labelRow = createFieldLabel({ label, help, sample });
  const row = document.createElement("div");
  row.className = "checkbox-row";
  const selectedSet = new Set(Array.isArray(selected) ? selected : []);
  for (const option of options) {
    const optionLabel = document.createElement("label");
    optionLabel.className = "checkbox-pill";
    const input = document.createElement("input");
    input.type = "checkbox";
    input.name = name;
    input.value = option.value;
    input.checked = selectedSet.has(option.value);
    const text = document.createElement("span");
    text.textContent = option.label;
    optionLabel.append(input, text);
    row.appendChild(optionLabel);
  }
  shell.append(labelRow, row);
  return shell;
}

function contentKindOptionsFor(lane, { isTrack }) {
  if (lane === "leetcode") {
    return [{ value: isTrack ? "leetcode_set" : "leetcode_exercise", label: isTrack ? "LeetCode set" : "LeetCode exercise" }];
  }
  if (lane === "dsa") {
    return [{ value: isTrack ? "dsa_track" : "dsa_exercise", label: isTrack ? "DSA track" : "DSA exercise" }];
  }
  return [{ value: isTrack ? "project_track" : "project_exercise", label: isTrack ? "Project track" : "Project exercise" }];
}

function groupEntries(kind, items) {
  if (kind === "tracks" || kind === "exercises") {
    const grouped = new Map();
    for (const lane of LANE_ORDER) {
      grouped.set(lane, []);
    }
    for (const item of items) {
      const lane = String(item.draft.lane || "project");
      if (!grouped.has(lane)) {
        grouped.set(lane, []);
      }
      grouped.get(lane).push(item);
    }
    return Array.from(grouped.entries())
      .filter(([, groupItems]) => groupItems.length > 0)
      .map(([lane, groupItems]) => ({
        title: laneLabel(lane),
        subtitle: `${groupItems.length} ${kind}`,
        items: sortByTitle(groupItems),
      }));
  }

  if (kind === "skills") {
    const grouped = new Map();
    for (const item of items) {
      const category = humanizeValue(item.draft.category || "skill");
      if (!grouped.has(category)) {
        grouped.set(category, []);
      }
      grouped.get(category).push(item);
    }
    return Array.from(grouped.entries())
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([category, groupItems]) => ({
        title: category,
        subtitle: `${groupItems.length} skills`,
        items: sortByTitle(groupItems),
      }));
  }

  const grouped = new Map();
  for (const item of items) {
    const title = String(item.draft.title || item.id || "#").trim();
    const initial = title.charAt(0).toUpperCase() || "#";
    if (!grouped.has(initial)) {
      grouped.set(initial, []);
    }
    grouped.get(initial).push(item);
  }
  return Array.from(grouped.entries())
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([initial, groupItems]) => ({
      title: initial,
      subtitle: `${groupItems.length} ${kind}`,
      items: sortByTitle(groupItems),
    }));
}

function createGroupSection(group) {
  const section = document.createElement("section");
  section.className = "group-section";

  const header = document.createElement("div");
  header.className = "group-header";

  const titleWrap = document.createElement("div");
  const title = document.createElement("h3");
  title.textContent = group.title;
  const subtitle = document.createElement("p");
  subtitle.className = "group-subtitle";
  subtitle.textContent = group.subtitle;
  titleWrap.append(title, subtitle);

  const count = document.createElement("span");
  count.className = "pill subtle-pill";
  count.textContent = String(group.items.length);
  header.append(titleWrap, count);

  const items = document.createElement("div");
  items.className = "group-items";
  for (const item of group.items) {
    items.appendChild(createEntityListItem(item));
  }

  section.append(header, items);
  return section;
}

function createEntityListItem(item) {
  const fragment = dom.itemTemplate.content.cloneNode(true);
  const button = fragment.querySelector(".entity-item");
  const title = fragment.querySelector(".entity-title");
  const summary = fragment.querySelector(".entity-summary");
  const badges = fragment.querySelector(".entity-badges");
  const itemKind = fragment.querySelector(".entity-kind");
  const status = fragment.querySelector(".entity-status");

  title.textContent = item.draft.title || item.id;
  summary.textContent = describeItem(state.selectedKind, item);
  itemKind.textContent = entityBadgeForItem(state.selectedKind, item);
  status.textContent = humanizeValue(item.workflowStatus);
  status.classList.add(`status-${item.workflowStatus}`);

  badges?.replaceChildren(...buildListBadges(state.selectedKind, item));

  button.addEventListener("click", () => {
    state.selectedId = item.id;
    if (isNarrowViewport()) {
      state.sidebarVisible = false;
      applySidebarVisibility();
    }
    switchView("detail");
  });

  return fragment;
}

function buildListBadges(kind, item) {
  if (kind !== "tracks" && kind !== "exercises") {
    return [];
  }

  const draft = item.draft || {};
  const nodes = [];

  nodes.push(createBadgePill(`Lane: ${laneLabel(String(draft.lane || "project"))}`));
  nodes.push(createBadgePill(`Level: ${humanizeValue(String(draft.level || "foundation"))}`));

  const languages =
    kind === "exercises"
      ? collectExerciseLanguages(draft)
      : collectTrackLanguages(item);
  if (languages.length) {
    const display = summarizeList(languages.map((lang) => lang.label), { max: 2 });
    nodes.push(
      createBadgePill(`Lang: ${display}`, {
        title: `Supported languages: ${languages.map((lang) => lang.label).join(", ")}`,
      }),
    );
  }

  const topics = Array.isArray(draft.topicIds) ? draft.topicIds : [];
  if (topics.length) {
    nodes.push(
      createBadgePill(`Topics: ${summarizeList(topics, { max: 2 })}`, {
        title: `Topics: ${topics.join(", ")}`,
      }),
    );
  }

  const domains = Array.isArray(draft.domainIds) ? draft.domainIds : [];
  if (domains.length) {
    nodes.push(
      createBadgePill(`Domains: ${summarizeList(domains, { max: 2 })}`, {
        title: `Domains: ${domains.join(", ")}`,
      }),
    );
  }

  const tags = Array.isArray(draft.tags) ? draft.tags : [];
  if (tags.length) {
    nodes.push(
      createBadgePill(`Tags: ${summarizeList(tags, { max: 2 })}`, {
        title: `Tags: ${tags.join(", ")}`,
      }),
    );
  }

  return nodes;
}

function collectExerciseLanguages(draft) {
  const variants = Array.isArray(draft?.languageVariants) ? draft.languageVariants : [];
  const labels = new Map();
  for (const variant of variants) {
    const id = String(variant?.languageId || "").trim();
    if (!id) continue;
    const label = String(variant?.languageLabel || id).trim();
    if (!labels.has(id)) {
      labels.set(id, label);
    }
  }
  return Array.from(labels.entries())
    .map(([id, label]) => ({ id, label }))
    .sort((a, b) => a.label.localeCompare(b.label));
}

function summarizeList(values, { max = 2 } = {}) {
  const list = Array.isArray(values) ? values.filter(Boolean) : [];
  if (list.length <= max) {
    return list.join(", ");
  }
  return `${list.slice(0, max).join(", ")} +${list.length - max}`;
}

function createBadgePill(text, { title = "" } = {}) {
  const node = document.createElement("span");
  node.className = "badge-pill";
  node.textContent = text;
  if (title) {
    node.title = title;
  }
  return node;
}

function buildStructure(kind, draft) {
  if (kind === "tracks") {
    const refs = Array.isArray(draft.exerciseRefs) ? draft.exerciseRefs : [];
    return [
      createStructureChip("Exercise refs", `${refs.length} linked`),
      ...refs.slice(0, 6).map((ref) =>
        createStructureChip(
          ref.title || ref.exerciseId || "Exercise",
          ref.milestoneLabel || ref.exerciseId || "Track step",
        ),
      ),
    ];
  }

  if (kind === "exercises") {
    const variants = Array.isArray(draft.languageVariants) ? draft.languageVariants : [];
    const supportedModes = Array.isArray(draft.supportedModes) ? draft.supportedModes : [];
    return [
      createStructureChip("Language variants", `${variants.length} configured`),
      createStructureChip("Modes", supportedModes.join(", ") || "No modes"),
      ...variants.slice(0, 6).map((variant, index) =>
        createStructureChipButton(
          `${variant.isDefault ? "Default · " : ""}${variant.languageLabel || variant.languageId || "Language"}`,
          variant.runCommand || variant.entryFilePath || "Open variant",
          () => runAction(() => openSelectedExerciseVariant(index)),
        ),
      ),
    ];
  }

  if (kind === "skills") {
    return [
      createStructureChip("Category", humanizeValue(draft.category || "skill")),
      createStructureChip(
        "Review exercise",
        draft.reviewExerciseId || draft.reviewMilestoneId || "Not linked",
      ),
    ];
  }

  return [createStructureChip("Entry id", draft.id || "—")];
}

function buildRelatedEntries(kind, item) {
  if (!state.catalog) {
    return [];
  }

  const draft = item.draft;
  const related = [];

  if (kind === "tracks") {
    const refs = Array.isArray(draft.exerciseRefs) ? draft.exerciseRefs : [];
    for (const ref of refs) {
      const exercise = findEntry("exercises", ref.exerciseId);
      related.push(
        createRelatedCard(
          `Exercise · ${ref.exerciseId || "Unknown"}`,
          exercise?.draft?.title || ref.title || ref.milestoneLabel || "Linked from track",
        ),
      );
    }
    for (const [label, ids, collection] of taxonomyTriples(draft)) {
      related.push(...idsToRelatedCards(label, ids, collection));
    }
    return related;
  }

  if (kind === "exercises") {
    const parentTracks = (state.catalog.tracks || []).filter((track) =>
      Array.isArray(track.draft.exerciseRefs)
        ? track.draft.exerciseRefs.some((ref) => ref.exerciseId === item.id)
        : false,
    );
    for (const track of parentTracks) {
      related.push(
        createRelatedCard(`Track · ${track.id}`, track.draft.title || "Referenced by track"),
      );
    }
    for (const [label, ids, collection] of taxonomyTriples(draft)) {
      related.push(...idsToRelatedCards(label, ids, collection));
    }
    return related;
  }

  if (kind === "topics" || kind === "domains") {
    const field = kind === "topics" ? "topicIds" : "domainIds";
    for (const [collection, entries] of [
      ["tracks", state.catalog.tracks || []],
      ["exercises", state.catalog.exercises || []],
    ]) {
      for (const entry of entries) {
        const ids = Array.isArray(entry.draft[field]) ? entry.draft[field] : [];
        if (ids.includes(item.id)) {
          related.push(
            createRelatedCard(
              `${entityLabel(collection)} · ${entry.id}`,
              entry.draft.title || "Uses this taxonomy item",
            ),
          );
        }
      }
    }
    return related;
  }

  if (kind === "skills") {
    const skillUsers = [...(state.catalog.tracks || []), ...(state.catalog.exercises || [])].filter((entry) =>
      Array.isArray(entry.draft.skillIds) ? entry.draft.skillIds.includes(item.id) : false,
    );
    for (const entry of skillUsers) {
      related.push(
        createRelatedCard(
          `${entryCollectionForDraft(entry.draft)} · ${entry.id}`,
          entry.draft.title || "Uses this skill",
        ),
      );
    }
    if (draft.reviewExerciseId) {
      const reviewExercise = findEntry("exercises", draft.reviewExerciseId);
      related.push(
        createRelatedCard(
          `Review exercise · ${draft.reviewExerciseId}`,
          reviewExercise?.draft?.title || "Linked review practice",
        ),
      );
    }
    return related;
  }

  return related;
}

function taxonomyTriples(draft) {
  return [
    ["Topic", Array.isArray(draft.topicIds) ? draft.topicIds : [], "topics"],
    ["Domain", Array.isArray(draft.domainIds) ? draft.domainIds : [], "domains"],
    ["Skill", Array.isArray(draft.skillIds) ? draft.skillIds : [], "skills"],
  ];
}

function idsToRelatedCards(label, ids, collection) {
  return ids.slice(0, 8).map((id) => {
    const entry = findEntry(collection, id);
    return createRelatedCard(
      `${label} · ${id}`,
      entry?.draft?.title || entry?.draft?.description || "Linked entity",
    );
  });
}

function entryCollectionForDraft(draft) {
  return draft.contentKind?.includes("track") ? "Track" : "Exercise";
}

function createEmptyState(message) {
  const node = document.createElement("div");
  node.className = "empty-state";
  node.textContent = message;
  return node;
}

function createMutedText(message) {
  const node = document.createElement("div");
  node.className = "muted";
  node.textContent = message;
  return node;
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

function createVariantListSection(title, items) {
  const list = Array.isArray(items) ? items.filter((item) => String(item || "").trim()) : [];
  if (list.length === 0) {
    return createMutedText(`${title}: —`);
  }

  const node = document.createElement("div");
  const heading = document.createElement("strong");
  heading.textContent = title;
  const ul = document.createElement("ul");
  ul.className = "variant-list";
  for (const item of list) {
    const li = document.createElement("li");
    li.textContent = String(item);
    ul.appendChild(li);
  }
  node.append(heading, ul);
  return node;
}

function createVariantTaskStepsSection(steps) {
  const list = Array.isArray(steps) ? steps : [];
  if (list.length === 0) {
    return createMutedText("Steps: —");
  }

  const node = document.createElement("div");
  const heading = document.createElement("strong");
  heading.textContent = "Step guide";
  const ol = document.createElement("ol");
  ol.className = "variant-list";
  for (const step of list) {
    if (!step || typeof step !== "object") continue;
    const title = String(step.title || "").trim();
    const description = String(step.description || "").trim();
    if (!title && !description) continue;
    const li = document.createElement("li");
    const label = title || "Step";
    li.textContent = description ? `${label}: ${description}` : label;
    ol.appendChild(li);
  }
  node.append(heading, ol);
  return node;
}

function createVariantMetaRow(label, value) {
  const row = document.createElement("div");
  row.textContent = `${label}: ${value}`;
  return row;
}

function createCodeBlock(code, { label = "", emptyLabel = "—" } = {}) {
  const wrapper = document.createElement("div");
  const trimmed = String(code || "");
  if (label) {
    const caption = document.createElement("div");
    caption.className = "code-label";
    caption.textContent = label;
    wrapper.appendChild(caption);
  }
  const block = document.createElement("pre");
  block.className = "code-block";
  block.textContent = trimmed.trim() ? trimmed : emptyLabel;
  wrapper.appendChild(block);
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

function createStructureChipButton(title, description, onClick) {
  const chip = document.createElement("button");
  chip.type = "button";
  chip.className = "structure-chip structure-chip-button";
  const heading = document.createElement("strong");
  heading.textContent = title;
  const detail = document.createElement("span");
  detail.textContent = description;
  chip.append(heading, detail);
  chip.addEventListener("click", onClick);
  return chip;
}

function createRelatedCard(title, description) {
  const card = document.createElement("div");
  card.className = "related-card";
  const heading = document.createElement("strong");
  heading.textContent = title;
  const detail = document.createElement("span");
  detail.textContent = description;
  card.append(heading, detail);
  return card;
}

function entityCollectionLabel(kind) {
  return humanizeValue(kind);
}

function entityLabel(kind) {
  if (kind === "tracks") return "Track";
  if (kind === "exercises") return "Exercise";
  if (kind === "topics") return "Topic";
  if (kind === "domains") return "Domain";
  if (kind === "skills") return "Skill";
  return humanizeValue(kind);
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
    const refs = Array.isArray(item.draft.exerciseRefs) ? item.draft.exerciseRefs.length : 0;
    return [item.draft.summary || "Track summary is empty.", `${refs} refs`].join(" · ");
  }
  if (kind === "exercises") {
    return item.draft.summary || "Exercise summary is empty.";
  }
  if (kind === "skills") {
    return item.draft.description || "Skill description is empty.";
  }
  return item.draft.summary || "No summary yet.";
}

function collectTrackLanguages(trackItem) {
  if (!state.catalog) {
    return [];
  }
  const labels = new Map();
  const refs = Array.isArray(trackItem?.draft?.exerciseRefs) ? trackItem.draft.exerciseRefs : [];
  for (const ref of refs) {
    const exercise = findEntry("exercises", ref.exerciseId);
    const variants = Array.isArray(exercise?.draft?.languageVariants)
      ? exercise.draft.languageVariants
      : [];
    for (const variant of variants) {
      const id = String(variant?.languageId || "").trim();
      if (!id) continue;
      const label = String(variant?.languageLabel || id).trim();
      if (!labels.has(id)) {
        labels.set(id, label);
      }
    }
  }
  return Array.from(labels.entries())
    .map(([id, label]) => ({ id, label }))
    .sort((a, b) => a.label.localeCompare(b.label));
}

function trackSupportsLanguage(trackItem, languageId) {
  if (!languageId) {
    return true;
  }
  return collectTrackLanguages(trackItem).some((language) => language.id === languageId);
}

function listSubtitleForKind(kind) {
  if (kind === "tracks" || kind === "exercises") {
    return "Grouped by lane with search and filter controls on the same page.";
  }
  if (kind === "skills") {
    return "Grouped by skill category so review-memory taxonomy stays easier to scan.";
  }
  return "Grouped alphabetically with search and workflow filtering.";
}

function laneLabel(lane) {
  if (lane === "leetcode") return "LeetCode";
  if (lane === "dsa") return "DSA";
  if (lane === "project") return "Project";
  return humanizeValue(lane);
}

function sortByTitle(items) {
  return [...items].sort((left, right) =>
    String(left.draft.title || left.id).localeCompare(String(right.draft.title || right.id)),
  );
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

function setStatus(message, { tone = "info" } = {}) {
  dom.authStatus.textContent = message;
  dom.connectionIndicator.classList.remove("connected", "error");
  if (tone === "success") {
    dom.connectionIndicator.classList.add("connected");
  } else if (tone === "error") {
    dom.connectionIndicator.classList.add("error");
  }
}

async function api(path, options = {}) {
  const url = new URL(path, window.location.origin);

  let response;
  try {
    response = await fetch(url, {
      ...options,
      headers: {
        ...(options.includeAdminKey === false ? {} : { "x-admin-key": state.adminKey }),
        ...(options.body ? { "Content-Type": "application/json" } : {}),
        ...(options.headers || {}),
      },
    });
  } catch {
    throw new Error(
      `Cannot reach admin API at ${url.pathname}. Check that app-api is running on ${window.location.origin}.`,
    );
  }

  if (response.status === 204) {
    return null;
  }

  const rawBody = await response.text();
  let payload = null;
  if (rawBody) {
    try {
      payload = JSON.parse(rawBody);
    } catch {
      payload = { error: rawBody };
    }
  }

  if (!response.ok) {
    throw new Error(payload?.error || payload?.message || `Request failed with status ${response.status}.`);
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
