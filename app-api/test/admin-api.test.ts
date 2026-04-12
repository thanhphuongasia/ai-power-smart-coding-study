import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { ContentStoreRepository } from "../src/content-store.js";
import { createApp } from "../src/index.js";

test("admin workflow keeps draft changes private until publish", async () => {
  const tempDirectory = await fs.mkdtemp(
    path.join(os.tmpdir(), "coach-admin-api-"),
  );
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
            topicIds: ["sql"],
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
                entryFilePath: "solution.py",
                demoFilePath: null,
                testCases: [],
              },
            ],
          },
        ],
        topics: [
          {
            id: "sql",
            title: "SQL",
            summary: "Query building",
          },
        ],
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
  const server = await new Promise<import("node:http").Server>((resolve) => {
    const instance = app.listen(0, () => resolve(instance));
  });
  const { port } = server.address() as { port: number };
  const baseUrl = `http://127.0.0.1:${port}`;

  try {
    const catalogResponse = await fetch(`${baseUrl}/v1/catalog`);
    const catalogPayload = (await catalogResponse.json()) as {
      tracks: Array<{ summary: string }>;
      exercises: Array<{ summary: string }>;
    };
    assert.equal(catalogPayload.tracks[0].summary, "Published summary");
    assert.equal(catalogPayload.exercises[0].summary, "Published exercise summary");

    const draftUpdateResponse = await fetch(
      `${baseUrl}/admin/api/exercises/project_list_documents`,
      {
        method: "PUT",
        headers: {
          "Content-Type": "application/json",
          "x-admin-key": "test-admin-key",
        },
        body: JSON.stringify({
          id: "project_list_documents",
          title: "List documents",
          summary: "Draft summary only",
          lane: "project",
          contentKind: "project_exercise",
          level: "foundation",
          topicIds: ["sql"],
          domainIds: ["document-management"],
          tags: ["list", "query"],
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
              entryFilePath: "solution.py",
              demoFilePath: null,
              testCases: [],
            },
          ],
        }),
      },
    );
    assert.equal(draftUpdateResponse.status, 200);

    const beforePublishResponse = await fetch(`${baseUrl}/v1/catalog`);
    const beforePublishPayload = (await beforePublishResponse.json()) as {
      exercises: Array<{ summary: string }>;
    };
    assert.equal(beforePublishPayload.exercises[0].summary, "Published exercise summary");

    const publishResponse = await fetch(
      `${baseUrl}/admin/api/exercises/project_list_documents/publish`,
      {
        method: "POST",
        headers: {
          "x-admin-key": "test-admin-key",
        },
      },
    );
    assert.equal(publishResponse.status, 200);

    const afterPublishResponse = await fetch(`${baseUrl}/v1/catalog`);
    const afterPublishPayload = (await afterPublishResponse.json()) as {
      exercises: Array<{ summary: string }>;
      tagSuggestions: string[];
    };
    assert.equal(afterPublishPayload.exercises[0].summary, "Draft summary only");
    assert.deepEqual(afterPublishPayload.tagSuggestions, ["list", "query"]);
  } finally {
    await new Promise<void>((resolve, reject) => {
      server.close((error) => {
        if (error) {
          reject(error);
          return;
        }
        resolve();
      });
    });
  }
});
