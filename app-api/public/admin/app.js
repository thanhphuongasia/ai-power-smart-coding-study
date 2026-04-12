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
  statusFilter: "",
  view: "list",
  editorMode: "idle",
  editorInputMode: "form",
  editorKind: "tracks",
  editorSourceId: null,
  editorDraft: null,
  editorVariantIndex: 0,
  editorJsonText: "",
  sidebarVisible: true,
  detailMenuOpen: false,
};

const dom = {
  adminKey: document.getElementById("admin-key"),
  authStatus: document.getElementById("auth-status"),
  connectionIndicator: document.getElementById("connection-indicator"),
  connectButton: document.getElementById("connect-button"),
  refreshButton: document.getElementById("refresh-button"),
  sidebar: document.getElementById("sidebar"),
  sidebarToggle: document.getElementById("sidebar-toggle"),
  createEntryButton: document.getElementById("create-entry-button"),
  searchInput: document.getElementById("search-input"),
  laneFilter: document.getElementById("lane-filter"),
  levelFilter: document.getElementById("level-filter"),
  statusFilter: document.getElementById("status-filter"),
  laneFilterShell: document.getElementById("lane-filter")?.closest(".field-shell"),
  levelFilterShell: document.getElementById("level-filter")?.closest(".field-shell"),
  listScreen: document.getElementById("list-screen"),
  detailScreen: document.getElementById("detail-screen"),
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
  dom.createEntryButton.addEventListener("click", () =>
    runAction(() => loadCreateDraft(state.selectedKind)),
  );
  dom.backToListButton.addEventListener("click", () => switchView("list"));
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
  dom.statusFilter.addEventListener("change", (event) => {
    state.statusFilter = event.target.value;
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
      updateFilterVisibility();
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
  if (state.view === "editor" && state.editorMode === "edit" && !findEntry(state.editorKind, state.editorSourceId)) {
    resetEditor();
    state.view = "list";
  }

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

  for (const button of dom.entityTabs) {
    button.classList.toggle("active", button.dataset.entityTab === state.selectedKind);
  }
}

function renderCurrentScreen() {
  const hasSelection = !!findSelectedEntry();
  if (state.view === "detail" && !hasSelection) {
    state.view = "list";
  }
  if (state.view === "editor" && state.editorMode === "idle") {
    state.view = hasSelection ? "detail" : "list";
  }

  dom.listScreen.hidden = state.view !== "list";
  dom.detailScreen.hidden = state.view !== "detail";
  dom.editorScreen.hidden = state.view !== "editor";

  renderListScreen();
  renderDetailScreen();
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

async function loadCreateDraft(kind) {
  state.editorMode = "create";
  state.editorKind = kind;
  state.editorSourceId = null;
  state.editorDraft = structuredCloneSafe(defaultDraftFor(kind));
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
  state.editorInputMode = "form";
  state.editorVariantIndex = guessDefaultVariantIndex(state.editorDraft);
  state.editorJsonText = "";
  clearEditorError();
  switchView("editor");
  setStatus(`Loaded ${item.id} into the editor.`);
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
  dom.laneFilterShell.hidden = !visible;
  dom.levelFilterShell.hidden = !visible;
  if (!visible) {
    state.laneFilter = "";
    state.levelFilter = "";
    dom.laneFilter.value = "";
    dom.levelFilter.value = "";
  }
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

function renderTrackForm(draft) {
  const shell = document.createElement("div");
  shell.className = "editor-form-shell";

  shell.appendChild(renderBasicsSection(draft, { includeLaneLevel: true, isTrack: true }));
  shell.appendChild(renderTaxonomySection(draft));

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
    }),
  );
  structure.appendChild(grid);
  shell.appendChild(structure);

  return shell;
}

function renderExerciseForm(draft) {
  const shell = document.createElement("div");
  shell.className = "editor-form-shell";

  shell.appendChild(renderBasicsSection(draft, { includeLaneLevel: true, isTrack: false }));
  shell.appendChild(renderTaxonomySection(draft));

  const content = createEditorSection("Content");
  const contentGrid = createFormGrid({ columns: 1 });
  contentGrid.appendChild(
    createTextareaField({
      name: "problemStatement",
      label: "Problem statement",
      value: String(draft.problemStatement || ""),
      placeholder: "Describe the goal, constraints, and expected behavior…",
      className: "textarea-medium",
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
    }),
  );
  content.appendChild(contentGrid);
  shell.appendChild(content);

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
    }),
  );
  workflow.appendChild(workflowGrid);
  shell.appendChild(workflow);

  const advanced = createEditorSection("Advanced");
  const advancedGrid = createFormGrid({ columns: 1 });
  advancedGrid.appendChild(
    createTextareaField({
      name: "hints",
      label: "Hints (JSON map)",
      value: JSON.stringify(draft.hints || {}, null, 2),
      placeholder: "{\n  \"tip\": \"Try using a hash map\"\n}",
    }),
  );
  advancedGrid.appendChild(
    createTextareaField({
      name: "taskSteps",
      label: "Task steps (JSON array)",
      value: JSON.stringify(draft.taskSteps || [], null, 2),
      placeholder: "[{\"id\":\"step1\",\"title\":\"\",\"description\":\"\"}]",
    }),
  );
  advancedGrid.appendChild(
    createTextareaField({
      name: "requirements",
      label: "Requirements (JSON array)",
      value: JSON.stringify(draft.requirements || [], null, 2),
      placeholder: "[{\"label\":\"\",\"pattern\":\"\",\"feedback\":\"\"}]",
    }),
  );
  advanced.appendChild(advancedGrid);
  shell.appendChild(advanced);

  shell.appendChild(renderExerciseVariantsSection(draft));

  return shell;
}

function renderSimpleTaxonomyForm(draft, label) {
  const shell = document.createElement("div");
  shell.className = "editor-form-shell";
  const basics = createEditorSection("Basics");
  const grid = createFormGrid({ columns: 2 });
  grid.appendChild(createTextField({ name: "id", label: `${label} id`, value: draft.id || "", readOnly: state.editorMode === "edit" }));
  grid.appendChild(createTextField({ name: "title", label: `${label} title`, value: draft.title || "" }));
  const summaryField = createTextareaField({
    name: "summary",
    label: "Summary",
    value: String(draft.summary || ""),
    className: "textarea-medium",
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
  grid.appendChild(createTextField({ name: "id", label: "Skill id", value: draft.id || "", readOnly: state.editorMode === "edit" }));
  grid.appendChild(createTextField({ name: "title", label: "Title", value: draft.title || "" }));
  grid.appendChild(createTextField({ name: "category", label: "Category", value: draft.category || "" }));
  grid.appendChild(createTextField({ name: "reviewExerciseId", label: "Review exercise id", value: draft.reviewExerciseId || "" }));
  grid.appendChild(
    createTextareaField({
      name: "description",
      label: "Description",
      value: String(draft.description || ""),
      className: "textarea-medium",
    }),
  );
  basics.appendChild(grid);
  shell.appendChild(basics);
  return shell;
}

function renderBasicsSection(draft, { includeLaneLevel, isTrack }) {
  const section = createEditorSection("Basics");
  const grid = createFormGrid({ columns: includeLaneLevel ? 3 : 2 });

  grid.appendChild(createTextField({ name: "id", label: "ID", value: draft.id || "", readOnly: state.editorMode === "edit" }));
  grid.appendChild(createTextField({ name: "title", label: "Title", value: draft.title || "" }));

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
    });
    const kindField = createSelectField({
      name: "contentKind",
      label: "Content kind",
      value: contentKind,
      options: contentKindOptionsFor(lane, { isTrack }),
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
  });
  summaryField.classList.add("field-span-all");
  grid.appendChild(summaryField);

  section.appendChild(grid);
  return section;
}

function renderTaxonomySection(draft) {
  const section = createEditorSection("Taxonomy");
  const grid = createFormGrid({ columns: 2 });
  grid.appendChild(createTextareaField({ name: "topicIds", label: "Topic ids (one per line)", value: Array.isArray(draft.topicIds) ? draft.topicIds.join("\n") : "", placeholder: "sql\nhttp" }));
  grid.appendChild(createTextareaField({ name: "domainIds", label: "Domain ids (one per line)", value: Array.isArray(draft.domainIds) ? draft.domainIds.join("\n") : "", placeholder: "document-management" }));
  grid.appendChild(createTextareaField({ name: "tags", label: "Tags (one per line)", value: Array.isArray(draft.tags) ? draft.tags.join("\n") : "", placeholder: "list\nquery" }));
  grid.appendChild(createTextareaField({ name: "skillIds", label: "Skill ids (one per line)", value: Array.isArray(draft.skillIds) ? draft.skillIds.join("\n") : "", placeholder: "spaced_repetition_scheduler" }));
  section.appendChild(grid);
  return section;
}

function renderExerciseVariantsSection(draft) {
  const section = createEditorSection("Language variants");

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
    button.addEventListener("click", () => runAction(() => selectExerciseVariant(index)));
    tabs.appendChild(button);
  });

  const addButton = document.createElement("button");
  addButton.type = "button";
  addButton.className = "secondary-button";
  addButton.textContent = "+ Variant";
  addButton.addEventListener("click", () => runAction(addExerciseVariant));
  tabs.appendChild(addButton);

  const removeButton = document.createElement("button");
  removeButton.type = "button";
  removeButton.className = "danger-button";
  removeButton.textContent = "Remove";
  removeButton.disabled = state.editorDraft.languageVariants.length <= 1;
  removeButton.addEventListener("click", () => runAction(removeExerciseVariant));
  tabs.appendChild(removeButton);

  section.appendChild(tabs);

  const active = state.editorDraft.languageVariants[activeIndex];
  const grid = createFormGrid({ columns: 3 });
  grid.appendChild(createTextField({ name: "variantLanguageId", label: "Language id", value: active.languageId || "" }));
  grid.appendChild(createTextField({ name: "variantLanguageLabel", label: "Label", value: active.languageLabel || "" }));
  grid.appendChild(createCheckboxField({ name: "variantIsDefault", label: "Default", checked: !!active.isDefault }));

  const runGrid = createFormGrid({ columns: 2 });
  runGrid.appendChild(createTextField({ name: "variantRunCommand", label: "Run command", value: active.runCommand || "" }));
  runGrid.appendChild(createTextField({ name: "variantEntryFilePath", label: "Entry file path", value: active.entryFilePath || "" }));
  runGrid.appendChild(createTextField({ name: "variantDemoFilePath", label: "Demo file path (optional)", value: active.demoFilePath || "" }));
  const solutionField = createTextareaField({
    name: "variantSolutionCode",
    label: "Solution code (optional)",
    value: active.solutionCode || "",
    className: "textarea-medium textarea-code",
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
    }),
  );
  codeGrid.appendChild(
    createTextareaField({
      name: "variantSandboxHarnessTemplate",
      label: "Sandbox harness template",
      value: active.sandboxHarnessTemplate || "{{USER_CODE}}\n\n{{TEST_BODY}}\n",
      className: "textarea-medium textarea-code",
    }),
  );
  codeGrid.appendChild(
    createTextareaField({
      name: "variantStarterFiles",
      label: "Starter files (JSON map)",
      value: JSON.stringify(active.starterFiles || {}, null, 2),
      placeholder: "{\n  \"helpers.py\": \"\"\n}",
    }),
  );
  codeGrid.appendChild(
    createTextareaField({
      name: "variantTestCases",
      label: "Test cases (JSON array)",
      value: JSON.stringify(active.testCases || [], null, 2),
      placeholder: "[{\"id\":\"case1\",\"label\":\"\",\"body\":\"\",\"expectedOutput\":\"\"}]",
    }),
  );

  section.appendChild(grid);
  section.appendChild(runGrid);
  section.appendChild(codeGrid);
  return section;
}

async function selectExerciseVariant(index) {
  persistActiveExerciseVariantFromForm();
  state.editorVariantIndex = index;
  renderEditorForm();
}

async function addExerciseVariant() {
  persistActiveExerciseVariantFromForm();
  const variants = Array.isArray(state.editorDraft.languageVariants)
    ? state.editorDraft.languageVariants
    : [];
  variants.push(defaultLanguageVariant());
  state.editorDraft.languageVariants = variants;
  state.editorVariantIndex = variants.length - 1;
  renderEditorForm();
}

async function removeExerciseVariant() {
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
  renderEditorForm();
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

function createTextField({ name, label, value, placeholder = "", readOnly = false }) {
  const shell = document.createElement("label");
  shell.className = "field-shell";
  const caption = document.createElement("span");
  caption.textContent = label;
  const input = document.createElement("input");
  input.name = name;
  input.type = "text";
  input.value = String(value ?? "");
  input.placeholder = placeholder;
  input.readOnly = !!readOnly;
  shell.append(caption, input);
  return shell;
}

function createTextareaField({ name, label, value, placeholder = "", className = "" }) {
  const shell = document.createElement("label");
  shell.className = "field-shell";
  const caption = document.createElement("span");
  caption.textContent = label;
  const textarea = document.createElement("textarea");
  textarea.name = name;
  textarea.value = String(value ?? "");
  textarea.placeholder = placeholder;
  if (className) {
    textarea.className = className;
  }
  shell.append(caption, textarea);
  return shell;
}

function createSelectField({ name, label, value, options }) {
  const shell = document.createElement("label");
  shell.className = "field-shell";
  const caption = document.createElement("span");
  caption.textContent = label;
  const select = document.createElement("select");
  select.name = name;
  replaceSelectOptions(select, options);
  select.value = value;
  shell.append(caption, select);
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

function createCheckboxField({ name, label, checked }) {
  const shell = document.createElement("label");
  shell.className = "field-shell";
  const caption = document.createElement("span");
  caption.textContent = label;
  const inputWrap = document.createElement("div");
  inputWrap.className = "checkbox-row";
  const input = document.createElement("input");
  input.type = "checkbox";
  input.name = name;
  input.checked = !!checked;
  inputWrap.appendChild(input);
  shell.append(caption, inputWrap);
  return shell;
}

function createCheckboxGroupField({ name, label, options, selected }) {
  const shell = document.createElement("div");
  shell.className = "field-shell";
  const caption = document.createElement("span");
  caption.textContent = label;
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
  shell.append(caption, row);
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
  const itemKind = fragment.querySelector(".entity-kind");
  const status = fragment.querySelector(".entity-status");

  title.textContent = item.draft.title || item.id;
  summary.textContent = describeItem(state.selectedKind, item);
  itemKind.textContent = entityBadgeForItem(state.selectedKind, item);
  status.textContent = humanizeValue(item.workflowStatus);
  status.classList.add(`status-${item.workflowStatus}`);

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
      ...variants.slice(0, 6).map((variant) =>
        createStructureChip(
          variant.languageLabel || variant.languageId || "Language",
          variant.runCommand || variant.entryFilePath || "No run command",
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
    return [item.draft.summary || "Track summary is empty.", `${refs} exercise refs`].join(" · ");
  }
  if (kind === "exercises") {
    const variants = Array.isArray(item.draft.languageVariants)
      ? item.draft.languageVariants
      : [];
    const languages = variants
      .map((variant) => variant.languageLabel || variant.languageId)
      .filter(Boolean)
      .join(", ");
    return [item.draft.summary || "Exercise summary is empty.", languages || "No languages"].join(
      " · ",
    );
  }
  if (kind === "skills") {
    return item.draft.description || "Skill description is empty.";
  }
  return item.draft.summary || "No summary yet.";
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
