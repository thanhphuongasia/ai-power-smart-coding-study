import { expect, test } from "@playwright/test";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

import { ContentStoreRepository } from "../src/content-store.js";
import { createApp } from "../src/index.js";

test.describe.configure({ mode: "serial" });

let server: import("node:http").Server;
let baseUrl: string;

test.beforeAll(async () => {
  const tempDirectory = await fs.mkdtemp(path.join(os.tmpdir(), "coach-admin-e2e-"));
  const bootstrapPath = path.join(tempDirectory, "bootstrap.json");
  const storePath = path.join(tempDirectory, "content-store.json");

  await fs.writeFile(
    bootstrapPath,
    JSON.stringify(
      {
        exportedAt: "2026-04-12T00:00:00.000Z",
        tracks: [
          {
            id: "project_documents",
            title: "Documents",
            summary: "Published summary",
            lane: "project",
            contentKind: "project_track",
            level: "foundation",
            topicIds: [],
            domainIds: ["document-management"],
            tags: ["list"],
            skillIds: [],
            exerciseRefs: [{ exerciseId: "project_list_documents" }],
          },
        ],
        exercises: [
          {
            id: "project_list_documents",
            title: "List documents",
            summary: "Published exercise summary",
            lane: "project",
            contentKind: "project_exercise",
            level: "foundation",
            topicIds: [],
            domainIds: ["document-management"],
            tags: ["list"],
            skillIds: [],
            problemStatement: "Build a list endpoint.",
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
                starterCode: "def list_documents(rows):\n    return rows\n",
                starterFiles: {},
                solutionCode: null,
                sandboxHarnessTemplate: "{{USER_CODE}}\n\n{{TEST_BODY}}\n",
                runCommand: "python main.py",
                entryFilePath: "main.py",
                demoFilePath: null,
                testCases: [],
              },
            ],
          },
        ],
        topics: [],
        domains: [
          {
            id: "document-management",
            title: "Document Management",
            summary: "Document workflows",
          },
        ],
        skills: [],
      },
      null,
      2,
    ),
  );

  const app = createApp({
    adminApiKey: "test-admin-key",
    contentStoreRepository: new ContentStoreRepository({
      storePath,
      bootstrapSnapshotPath: bootstrapPath,
    }),
  });

  server = await new Promise<import("node:http").Server>((resolve) => {
    const instance = app.listen(0, () => resolve(instance));
  });
  const { port } = server.address() as { port: number };
  baseUrl = `http://127.0.0.1:${port}`;
});

test.afterAll(async () => {
  await new Promise<void>((resolve, reject) => {
    server.close((error) => {
      if (error) {
        reject(error);
        return;
      }
      resolve();
    });
  });
});

test("admin editor uses a form by default (with JSON toggle)", async ({ page }) => {
  await page.goto(`${baseUrl}/admin/`);
  await page.fill("#admin-key", "test-admin-key");
  await page.click("#connect-button");

  await expect(page.locator("#list-screen")).toBeVisible();
  await expect(page.locator(".entity-item")).toHaveCount(1);

  await page.locator(".entity-item").first().click();
  await expect(page.locator("#detail-screen")).toBeVisible();

  await page.click("#detail-menu-button");
  await page.click("#detail-edit-button");
  await expect(page.locator("#editor-screen")).toBeVisible();

  await expect(page.locator("#editor-form-shell")).toBeVisible();
  await expect(page.locator("#editor-json-shell")).toBeHidden();
  await expect(page.locator('input[name="title"]')).toBeVisible();

  await page.click("#editor-mode-toggle");
  await expect(page.locator("#editor-json-shell")).toBeVisible();
  await expect(page.locator("#editor-form-shell")).toBeHidden();
  await expect(page.locator("#editor-textarea")).toHaveValue(/"id":\s*"project_documents"/);

  await page.click("#editor-mode-toggle");
  await expect(page.locator("#editor-form-shell")).toBeVisible();
});

test("admin sidebar collapses on narrow viewports", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`${baseUrl}/admin/`);
  await page.fill("#admin-key", "test-admin-key");
  await page.click("#connect-button");

  await expect(page.locator("#sidebar-toggle")).toBeVisible();
  await expect(page.locator("#sidebar")).toBeHidden();

  await page.click("#sidebar-toggle");
  await expect(page.locator("#sidebar")).toBeVisible();
});
