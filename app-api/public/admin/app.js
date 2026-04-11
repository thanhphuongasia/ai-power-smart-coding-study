const state = {
  adminKey: localStorage.getItem("adminKey") || "",
  catalog: null,
  selectedKind: null,
  selectedId: null,
};

const dom = {
  adminKey: document.getElementById("admin-key"),
  authStatus: document.getElementById("auth-status"),
  connectButton: document.getElementById("connect-button"),
  tracksList: document.getElementById("tracks-list"),
  skillsList: document.getElementById("skills-list"),
  editorTitle: document.getElementById("editor-title"),
  editorMeta: document.getElementById("editor-meta"),
  editorTextarea: document.getElementById("editor-textarea"),
  saveButton: document.getElementById("save-button"),
  publishButton: document.getElementById("publish-button"),
  unpublishButton: document.getElementById("unpublish-button"),
  deleteButton: document.getElementById("delete-button"),
  refreshButton: document.getElementById("refresh-button"),
  newTrackButton: document.getElementById("new-track-button"),
  newSkillButton: document.getElementById("new-skill-button"),
  itemTemplate: document.getElementById("entity-item-template"),
};

dom.adminKey.value = state.adminKey;
dom.editorTextarea.disabled = true;

dom.connectButton.addEventListener("click", connect);
dom.refreshButton.addEventListener("click", refreshCatalog);
dom.newTrackButton.addEventListener("click", () => createEntry("tracks"));
dom.newSkillButton.addEventListener("click", () => createEntry("skills"));
dom.saveButton.addEventListener("click", saveSelectedEntry);
dom.publishButton.addEventListener("click", () => publishSelectedEntry("publish"));
dom.unpublishButton.addEventListener("click", () => publishSelectedEntry("unpublish"));
dom.deleteButton.addEventListener("click", deleteSelectedEntry);

if (state.adminKey) {
  connect().catch((error) => {
    setStatus(error.message, true);
  });
}

async function connect() {
  state.adminKey = dom.adminKey.value.trim();
  localStorage.setItem("adminKey", state.adminKey);
  await refreshCatalog();
}

async function refreshCatalog() {
  const catalog = await api("/admin/api/catalog");
  state.catalog = catalog;
  if (!state.selectedKind || !state.selectedId) {
    const firstTrack = catalog.tracks[0];
    if (firstTrack) {
      selectEntry("tracks", firstTrack.id);
    }
  } else {
    selectEntry(state.selectedKind, state.selectedId, { preserve: true });
  }
  renderLists();
  setStatus(
    `Connected. Content version ${catalog.contentVersion}, last published ${catalog.lastPublishedAt || "never"}.`,
  );
}

function renderLists() {
  renderEntityList("tracks", dom.tracksList, state.catalog?.tracks || []);
  renderEntityList("skills", dom.skillsList, state.catalog?.skills || []);
}

function renderEntityList(kind, container, items) {
  container.replaceChildren();
  for (const item of items) {
    const fragment = dom.itemTemplate.content.cloneNode(true);
    const button = fragment.querySelector(".entity-item");
    const title = fragment.querySelector(".entity-title");
    const status = fragment.querySelector(".entity-status");
    title.textContent = item.draft.title || item.id;
    status.textContent = item.workflowStatus.replaceAll("_", " ");
    if (state.selectedKind === kind && state.selectedId === item.id) {
      button.classList.add("active");
    }
    button.addEventListener("click", () => selectEntry(kind, item.id));
    container.appendChild(fragment);
  }
}

function selectEntry(kind, id, options = {}) {
  state.selectedKind = kind;
  state.selectedId = id;
  const item = findSelectedEntry();
  renderLists();

  if (!item) {
    if (!options.preserve) {
      dom.editorTitle.textContent = "Select an entry";
      dom.editorMeta.textContent = "No item selected.";
      dom.editorTextarea.value = "";
      dom.editorTextarea.disabled = true;
    }
    return;
  }

  dom.editorTitle.textContent = `${kind === "tracks" ? "Track" : "Skill"} · ${item.id}`;
  dom.editorMeta.textContent = [
    `Workflow: ${item.workflowStatus}`,
    `Updated: ${new Date(item.updatedAt).toLocaleString()}`,
    `Published: ${item.publishedAt ? new Date(item.publishedAt).toLocaleString() : "Not yet"}`,
  ].join(" · ");
  dom.editorTextarea.value = JSON.stringify(item.draft, null, 2);
  dom.editorTextarea.disabled = false;
}

async function createEntry(kind) {
  const id = window.prompt(`New ${kind === "tracks" ? "track" : "skill"} id`);
  if (!id) {
    return;
  }

  const payload =
    kind === "tracks"
      ? {
          id,
          title: "Untitled track",
          summary: "Describe the learning lane here.",
          type: "project",
          difficultyLabel: "Foundation",
          focusAreas: [],
          modules: [],
        }
      : {
          id,
          title: "Untitled skill",
          category: "languageSyntax",
          description: "Describe this skill.",
          reviewMilestoneId: "",
        };

  const entry = await api(`/admin/api/${kind}`, {
    method: "POST",
    body: JSON.stringify(payload),
  });
  await refreshCatalog();
  selectEntry(kind, entry.id);
}

async function saveSelectedEntry() {
  const item = findSelectedEntry();
  if (!item) {
    return;
  }

  let parsed;
  try {
    parsed = JSON.parse(dom.editorTextarea.value);
  } catch (error) {
    setStatus(`Invalid JSON: ${error.message}`, true);
    return;
  }

  if (parsed.id !== item.id) {
    setStatus("Entry id cannot be changed from the editor.", true);
    return;
  }

  await api(`/admin/api/${state.selectedKind}/${item.id}`, {
    method: "PUT",
    body: JSON.stringify(parsed),
  });
  await refreshCatalog();
  selectEntry(state.selectedKind, item.id);
}

async function publishSelectedEntry(mode) {
  const item = findSelectedEntry();
  if (!item) {
    return;
  }

  await api(`/admin/api/${state.selectedKind}/${item.id}/${mode}`, {
    method: "POST",
  });
  await refreshCatalog();
  selectEntry(state.selectedKind, item.id);
}

async function deleteSelectedEntry() {
  const item = findSelectedEntry();
  if (!item) {
    return;
  }

  if (!window.confirm(`Delete ${item.id}?`)) {
    return;
  }

  await api(`/admin/api/${state.selectedKind}/${item.id}`, {
    method: "DELETE",
  });
  state.selectedId = null;
  await refreshCatalog();
}

function findSelectedEntry() {
  if (!state.catalog || !state.selectedKind || !state.selectedId) {
    return null;
  }
  return state.catalog[state.selectedKind]?.find((item) => item.id === state.selectedId) || null;
}

async function api(url, options = {}) {
  const response = await fetch(url, {
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

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(payload.error || `Request failed with ${response.status}`);
  }
  return payload;
}

function setStatus(message, isError = false) {
  dom.authStatus.textContent = message;
  dom.authStatus.style.color = isError ? "#b42318" : "";
}
