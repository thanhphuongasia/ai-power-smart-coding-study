const test = require('node:test');
const assert = require('node:assert/strict');
const JSZip = require('jszip');

const { createApp } = require('./index');

test('sandbox execute returns a structured multi-case report', async () => {
  const fetchCalls = [];
  const responses = [
    jsonResponse([
      { id: 71, name: 'Python (3.11.2)' },
    ]),
    jsonResponse({ token: 'token-case-1' }),
    jsonResponse({
      status: { id: 3, description: 'Accepted' },
      stdout: encode('Quarterly Report by Nina (14 pages)\n'),
      stderr: '',
      compile_output: '',
      message: '',
      exit_code: 0,
      time: '0.01',
      memory: 2048,
    }),
    jsonResponse({ token: 'token-case-2' }),
    jsonResponse({
      status: { id: 3, description: 'Accepted' },
      stdout: encode('Spec by Minh (2 pages)\n'),
      stderr: '',
      compile_output: '',
      message: '',
      exit_code: 0,
      time: '0.01',
      memory: 2048,
    }),
  ];

  const server = await startTestServer({
    judge0BaseUrl: 'https://judge0.test',
    fetchImpl: async (url, init = {}) => {
      fetchCalls.push({ url, init });
      const next = responses.shift();
      assert.ok(next, `Unexpected fetch call for ${url}`);
      return next;
    },
  });

  try {
    const response = await fetch(`${server.baseUrl}/api/sandbox/execute`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        action: 'run',
        languageLabel: 'Python',
        entryFilePath: 'models/document.py',
        fileContents: {
          'models/document.py': [
            'class Document:',
            '    def __init__(self, title, owner, page_count):',
            '        self.title = title',
            '        self.owner = owner',
            '        self.page_count = page_count',
            '',
            '    def summary(self):',
            '        return f"{self.title} by {self.owner} ({self.page_count} pages)"',
          ].join('\n'),
        },
        harnessTemplate: '{{USER_CODE}}\n\n{{TEST_BODY}}\n',
        testCases: [
          {
            id: 'document_summary_primary',
            label: 'Formats the sample document summary',
            body: 'document = Document("Quarterly Report", "Nina", 14)\nprint(document.summary())',
            expectedOutput: 'Quarterly Report by Nina (14 pages)',
          },
          {
            id: 'document_summary_short',
            label: 'Handles another owner and page count',
            body: 'document = Document("Spec", "Minh", 2)\nprint(document.summary())',
            expectedOutput: 'Spec by Minh (2 pages)',
          },
        ],
      }),
    });

    assert.equal(response.status, 200);
    const payload = await response.json();
    assert.equal(payload.success, true);
    assert.equal(payload.summary, 'All 2 sandbox test cases passed.');
    assert.equal(payload.report.passedCaseCount, 2);
    assert.equal(payload.report.totalCaseCount, 2);
    assert.equal(payload.report.caseResults.length, 2);
    assert.equal(payload.report.caseResults[0].actualOutput, 'Quarterly Report by Nina (14 pages)');
    assert.match(payload.output, /Passed 2\/2 test cases/);
    assert.equal(fetchCalls.length, 5);
  } finally {
    await stopTestServer(server.server);
  }
});

test('sandbox execute forwards helper files through Judge0 additional_files', async () => {
  let capturedCreateBody = null;
  const responses = [
    jsonResponse([
      { id: 71, name: 'Python (3.11.2)' },
    ]),
    jsonResponse({ token: 'token-multi-file' }),
    jsonResponse({
      status: { id: 3, description: 'Accepted' },
      stdout: encode('hello from helper\n'),
      stderr: '',
      compile_output: '',
      message: '',
      exit_code: 0,
      time: '0.01',
      memory: 2048,
    }),
  ];

  const server = await startTestServer({
    judge0BaseUrl: 'https://judge0.test',
    fetchImpl: async (url, init = {}) => {
      if (String(url).includes('/submissions?')) {
        capturedCreateBody = JSON.parse(init.body);
      }
      const next = responses.shift();
      assert.ok(next, `Unexpected fetch call for ${url}`);
      return next;
    },
  });

  try {
    const response = await fetch(`${server.baseUrl}/api/sandbox/execute`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        action: 'run',
        languageLabel: 'Python',
        entryFilePath: 'main.py',
        fileContents: {
          'main.py': 'from helpers.util import greet\n\nprint(greet())\n',
          'helpers/util.py': 'def greet():\n    return "hello from helper"\n',
        },
        harnessTemplate: '{{USER_CODE}}\n',
        testCases: [
          {
            id: 'multi_file_python',
            label: 'Imports a helper module from an extra file',
            body: '',
            expectedOutput: 'hello from helper',
          },
        ],
      }),
    });

    assert.equal(response.status, 200);
    const payload = await response.json();
    assert.equal(payload.success, true);
    assert.ok(capturedCreateBody);
    assert.ok(capturedCreateBody.additional_files);

    const zip = await JSZip.loadAsync(Buffer.from(capturedCreateBody.additional_files, 'base64'));
    const helperFile = zip.file('helpers/util.py');
    assert.ok(helperFile, 'Expected helper file to be present in additional_files zip');
    assert.equal(
      await helperFile.async('string'),
      'def greet():\n    return "hello from helper"\n',
    );
  } finally {
    await stopTestServer(server.server);
  }
});

test('sandbox execute runs demo file when no test cases are provided', async () => {
  const fetchCalls = [];
  const responses = [
    jsonResponse([{ id: 71, name: 'Python (3.11.2)' }]),
    jsonResponse({ token: 'token-demo-only' }),
    jsonResponse({
      status: { id: 3, description: 'Accepted' },
      stdout: encode('demo output\n'),
      stderr: '',
      compile_output: '',
      message: '',
      exit_code: 0,
      time: '0.01',
      memory: 2048,
    }),
  ];

  const server = await startTestServer({
    judge0BaseUrl: 'https://judge0.test',
    fetchImpl: async (url, init = {}) => {
      fetchCalls.push({ url, init });
      const next = responses.shift();
      assert.ok(next, `Unexpected fetch call for ${url}`);
      return next;
    },
  });

  try {
    const response = await fetch(`${server.baseUrl}/api/sandbox/execute`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        action: 'run',
        languageLabel: 'Python',
        entryFilePath: 'main.py',
        demoFilePath: 'main.py',
        fileContents: {
          'main.py': 'print("demo output")\n',
        },
        harnessTemplate: '{{USER_CODE}}\n',
        testCases: [],
      }),
    });

    assert.equal(response.status, 200);
    const payload = await response.json();
    assert.equal(payload.success, true);
    assert.equal(payload.summary, 'Program run completed (no test cases executed).');
    assert.equal(payload.report.passedCaseCount, 0);
    assert.equal(payload.report.totalCaseCount, 0);
    assert.equal(payload.report.programResult.actualOutput, 'demo output');
    assert.equal(fetchCalls.length, 3);
  } finally {
    await stopTestServer(server.server);
  }
});

test('sandbox execute ignores test cases when runWithoutTests is true', async () => {
  const fetchCalls = [];
  const responses = [
    jsonResponse([{ id: 71, name: 'Python (3.11.2)' }]),
    jsonResponse({ token: 'token-demo-preview' }),
    jsonResponse({
      status: { id: 3, description: 'Accepted' },
      stdout: encode('preview output\n'),
      stderr: '',
      compile_output: '',
      message: '',
      exit_code: 0,
      time: '0.01',
      memory: 2048,
    }),
  ];

  const server = await startTestServer({
    judge0BaseUrl: 'https://judge0.test',
    fetchImpl: async (url, init = {}) => {
      fetchCalls.push({ url, init });
      const next = responses.shift();
      assert.ok(next, `Unexpected fetch call for ${url}`);
      return next;
    },
  });

  try {
    const response = await fetch(`${server.baseUrl}/api/sandbox/execute`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        action: 'run',
        runWithoutTests: true,
        languageLabel: 'Python',
        entryFilePath: 'main.py',
        demoFilePath: 'main.py',
        fileContents: {
          'main.py': 'print("preview output")\n',
        },
        harnessTemplate: '{{USER_CODE}}\n',
        testCases: [
          {
            id: 'would-have-run',
            label: 'Would have run',
            body: '',
            expectedOutput: 'nope',
          },
        ],
      }),
    });

    assert.equal(response.status, 200);
    const payload = await response.json();
    assert.equal(payload.success, true);
    assert.equal(payload.report.totalCaseCount, 0);
    assert.equal(payload.report.programResult.actualOutput, 'preview output');
    assert.equal(fetchCalls.length, 3);
  } finally {
    await stopTestServer(server.server);
  }
});

test('sandbox execute wraps default C# harnesses in a Program.Main entry point', async () => {
  let capturedCreateBody = null;
  const responses = [
    jsonResponse([{ id: 51, name: 'C# (.NET Core)' }]),
    jsonResponse({ token: 'token-csharp-main' }),
    jsonResponse({
      status: { id: 3, description: 'Accepted' },
      stdout: encode('Architecture Notes:1700\n'),
      stderr: '',
      compile_output: '',
      message: '',
      exit_code: 0,
      time: '0.01',
      memory: 2048,
    }),
  ];

  const server = await startTestServer({
    judge0BaseUrl: 'https://judge0.test',
    fetchImpl: async (url, init = {}) => {
      if (String(url).includes('/submissions?')) {
        capturedCreateBody = JSON.parse(init.body);
      }
      const next = responses.shift();
      assert.ok(next, `Unexpected fetch call for ${url}`);
      return next;
    },
  });

  try {
    const response = await fetch(`${server.baseUrl}/api/sandbox/execute`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        action: 'run',
        languageLabel: 'C#',
        entryFilePath: 'DocumentQueries.cs',
        fileContents: {
          'DocumentQueries.cs': [
            'using System.Collections.Generic;',
            '',
            'public static class DocumentQueries',
            '{',
            '    public static List<string> ListActive()',
            '    {',
            '        return new List<string> { "Architecture Notes:1700" };',
            '    }',
            '}',
          ].join('\n'),
        },
        harnessTemplate: '{{USER_CODE}}\n\n{{TEST_BODY}}\n',
        testCases: [
          {
            id: 'csharp_entrypoint',
            label: 'Adds a Program.Main wrapper',
            body: 'foreach (var item in DocumentQueries.ListActive())\n{\n    Console.WriteLine(item);\n}',
            expectedOutput: 'Architecture Notes:1700',
          },
        ],
      }),
    });

    assert.equal(response.status, 200);
    assert.ok(capturedCreateBody, 'Expected submission body to be captured');

    const sourceCode = decode(capturedCreateBody.source_code);
    assert.match(sourceCode, /public static class Program/);
    assert.match(sourceCode, /public static void Main\(\)/);
    assert.match(sourceCode, /Console\.WriteLine\(item\);/);
    assert.match(sourceCode, /public static class DocumentQueries/);
  } finally {
    await stopTestServer(server.server);
  }
});

test('sandbox execute rewrites C# records when Judge0 falls back to Mono', async () => {
  let capturedCreateBody = null;
  const responses = [
    jsonResponse([{ id: 52, name: 'C# (Mono 6.12.0.182)' }]),
    jsonResponse({ token: 'token-csharp-record' }),
    jsonResponse({
      status: { id: 3, description: 'Accepted' },
      stdout: encode('Quarterly Report\n'),
      stderr: '',
      compile_output: '',
      message: '',
      exit_code: 0,
      time: '0.01',
      memory: 2048,
    }),
  ];

  const server = await startTestServer({
    judge0BaseUrl: 'https://judge0.test',
    fetchImpl: async (url, init = {}) => {
      if (String(url).includes('/submissions?')) {
        capturedCreateBody = JSON.parse(init.body);
      }
      const next = responses.shift();
      assert.ok(next, `Unexpected fetch call for ${url}`);
      return next;
    },
  });

  try {
    const response = await fetch(`${server.baseUrl}/api/sandbox/execute`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        action: 'run',
        languageLabel: 'C#',
        entryFilePath: 'Document.cs',
        fileContents: {
          'Document.cs': [
            'public record Document(string Title, string Owner, int PageCount)',
            '{',
            '    public string Summary()',
            '    {',
            '        return Title;',
            '    }',
            '}',
          ].join('\n'),
        },
        harnessTemplate: '{{USER_CODE}}\n\n{{TEST_BODY}}\n',
        testCases: [
          {
            id: 'csharp_record',
            label: 'Compiles a positional record on Mono',
            body: 'var document = new Document("Quarterly Report", "Nina", 14);\nConsole.WriteLine(document.Summary());',
            expectedOutput: 'Quarterly Report',
          },
        ],
      }),
    });

    assert.equal(response.status, 200);
    assert.ok(capturedCreateBody, 'Expected submission body to be captured');

    const sourceCode = decode(capturedCreateBody.source_code);
    assert.doesNotMatch(sourceCode, /\brecord\b/);
    assert.match(sourceCode, /public class Document/);
    assert.match(sourceCode, /public string Title \{ get; private set; \}/);
    assert.match(sourceCode, /public Document\(string Title, string Owner, int PageCount\)/);
    assert.match(sourceCode, /this\.Title = Title;/);
    assert.match(sourceCode, /public string Summary\(\)/);
  } finally {
    await stopTestServer(server.server);
  }
});

async function startTestServer(options) {
  const app = createApp(options);
  const server = await new Promise((resolve) => {
    const instance = app.listen(0, () => resolve(instance));
  });
  const address = server.address();
  const baseUrl = `http://127.0.0.1:${address.port}`;
  return { app, server, baseUrl };
}

function stopTestServer(server) {
  return new Promise((resolve, reject) => {
    server.close((error) => {
      if (error) {
        reject(error);
        return;
      }
      resolve();
    });
  });
}

function jsonResponse(payload, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function encode(value) {
  return Buffer.from(String(value), 'utf8').toString('base64');
}

function decode(value) {
  return Buffer.from(String(value), 'base64').toString('utf8');
}
