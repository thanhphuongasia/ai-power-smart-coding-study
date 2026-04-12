const express = require('express');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const JSZip = require('jszip');

function createApp(options = {}) {
  const config = {
    port: Number(options.port || process.env.PORT || 8787),
    judge0BaseUrl: (options.judge0BaseUrl || process.env.JUDGE0_BASE_URL || 'https://ce.judge0.com').replace(/\/+$/, ''),
    judge0AuthToken: options.judge0AuthToken || process.env.JUDGE0_AUTH_TOKEN || '',
    judge0AuthHeader: options.judge0AuthHeader || process.env.JUDGE0_AUTH_HEADER || 'X-Auth-Token',
    fetchImpl: options.fetchImpl || globalThis.fetch,
    rateLimitWindowMs: options.rateLimitWindowMs || 60 * 1000,
    rateLimitMax: options.rateLimitMax || 30,
  };

  if (typeof config.fetchImpl !== 'function') {
    throw new Error('A fetch implementation is required to create the sandbox proxy app.');
  }

  const app = express();
  let cachedLanguages = null;

  app.use(cors());
  app.use(express.json({ limit: '1mb' }));
  app.use(
    '/api/sandbox',
    rateLimit({
      windowMs: config.rateLimitWindowMs,
      max: config.rateLimitMax,
      standardHeaders: true,
      legacyHeaders: false,
    }),
  );

  app.get('/health', (_request, response) => {
    response.json({
      ok: true,
      judge0BaseUrl: config.judge0BaseUrl,
      directJudge0AuthConfigured: config.judge0AuthToken.length > 0,
    });
  });

  app.post('/api/sandbox/execute', async (request, response) => {
    try {
      const payload = request.body || {};
      const action = payload.action;
      const languageVariant = payload.languageVariant && typeof payload.languageVariant === 'object'
        ? payload.languageVariant
        : {};
      const languageLabel = languageVariant.languageLabel || payload.languageLabel;
      const entryFilePath = languageVariant.entryFilePath || payload.entryFilePath;
      const demoFilePath = languageVariant.demoFilePath || payload.demoFilePath;
      const fileContents = payload.fileContents;
      const harnessTemplate = languageVariant.harnessTemplate || payload.harnessTemplate;
      const testCases = Array.isArray(languageVariant.testCases)
        ? languageVariant.testCases
        : Array.isArray(payload.testCases)
          ? payload.testCases
          : [];

      if (action !== 'build' && action !== 'run') {
        return response.status(400).json({ error: 'action must be "build" or "run"' });
      }
      if (typeof languageLabel !== 'string' || languageLabel.trim().length === 0) {
        return response.status(400).json({ error: 'languageLabel is required' });
      }
      if (typeof entryFilePath !== 'string' || entryFilePath.trim().length === 0) {
        return response.status(400).json({ error: 'entryFilePath is required' });
      }
      if (!fileContents || typeof fileContents !== 'object' || Array.isArray(fileContents)) {
        return response.status(400).json({ error: 'fileContents must be an object map' });
      }
      if (typeof harnessTemplate !== 'string' || harnessTemplate.length === 0) {
        return response.status(400).json({ error: 'harnessTemplate is required' });
      }

      const entrySourceCode = String(fileContents[entryFilePath] || '');
      const additionalFiles = await encodeAdditionalFiles({
        entryFilePath,
        fileContents,
      });
      const demoSourceCode =
        typeof demoFilePath === 'string' && demoFilePath.trim().length > 0
          ? String(fileContents[demoFilePath] || '')
          : '';
      const demoAdditionalFiles =
        typeof demoFilePath === 'string' && demoFilePath.trim().length > 0
          ? await encodeAdditionalFiles({
              entryFilePath: demoFilePath,
              fileContents,
            })
          : '';

      const languageId = await resolveLanguageId(languageLabel);

      if (action === 'build') {
        const buildCase = testCases[0] || {
          id: 'build',
          label: 'Build harness',
          body: '',
          expectedOutput: '',
        };
        const buildSource =
          demoSourceCode.length > 0
            ? demoSourceCode
            : composeSource({
                harnessTemplate,
                sourceCode: entrySourceCode,
                testBody: buildCase.body || '',
              });
        const buildSubmission = await executeJudge0Submission({
          languageId,
          sourceCode: buildSource,
          additionalFiles: demoSourceCode.length > 0 ? demoAdditionalFiles : additionalFiles,
        });
        const success = buildSubmission.statusDescription === 'Accepted';
        const report = {
          engineLabel: 'Judge0 via sandbox proxy',
          statusLabel: buildSubmission.statusDescription,
          passedCaseCount: 0,
          totalCaseCount: 0,
          programResult: null,
          sections: buildSectionsFromSubmissions([buildSubmission]),
          caseResults: [],
        };
        return response.json({
          success,
          summary: success
            ? 'Build validation completed through the sandbox proxy.'
            : `Build finished with ${buildSubmission.statusDescription}.`,
          output: buildPlainTextOutput(report),
          report,
        });
      }

      if (testCases.length === 0) {
        return response.status(400).json({ error: 'At least one test case is required for run.' });
      }

      let programResult = null;
      if (demoSourceCode.length > 0) {
        const submission = await executeJudge0Submission({
          languageId,
          sourceCode: demoSourceCode,
          additionalFiles: demoAdditionalFiles,
        });
        programResult = {
          label: 'Program run',
          passed: submission.statusDescription === 'Accepted',
          statusLabel: submission.statusDescription,
          actualOutput: actualOutputForSubmission(submission),
          stdout: submission.stdout,
          stderr: submission.stderr,
          compileOutput: submission.compileOutput,
          message: submission.message,
        };
      }

      const caseResults = [];
      for (const testCase of testCases) {
        const wrappedSource = composeSource({
          harnessTemplate,
          sourceCode: entrySourceCode,
          testBody: String(testCase.body || ''),
        });
        const submission = await executeJudge0Submission({
          languageId,
          sourceCode: wrappedSource,
          expectedOutput: String(testCase.expectedOutput || ''),
          additionalFiles,
        });
        caseResults.push({
          id: String(testCase.id || 'case'),
          label: String(testCase.label || 'Test case'),
          passed: submission.statusDescription === 'Accepted',
          statusLabel: submission.statusDescription,
          expectedOutput: String(testCase.expectedOutput || ''),
          actualOutput: actualOutputForSubmission(submission),
          stdout: submission.stdout,
          stderr: submission.stderr,
          compileOutput: submission.compileOutput,
          message: submission.message,
        });
      }

      const passedCaseCount = caseResults.filter((item) => item.passed).length;
      const programPassed = programResult == null || programResult.passed;
      const allCasesPassed = passedCaseCount === caseResults.length;
      const report = {
        engineLabel: 'Judge0 via sandbox proxy',
        statusLabel: programPassed && allCasesPassed ? 'Accepted' : 'Needs work',
        passedCaseCount,
        totalCaseCount: caseResults.length,
        programResult,
        sections: buildSectionsFromCaseResults(caseResults),
        caseResults,
      };

      response.json({
        success: programPassed && allCasesPassed,
        summary:
          programResult != null && !programPassed
            ? `Program run reported issues. Passed ${passedCaseCount}/${caseResults.length} sandbox test cases.`
            : programResult != null && allCasesPassed
              ? `Program run completed and all ${caseResults.length} sandbox test cases passed.`
              : allCasesPassed
                ? `All ${caseResults.length} sandbox test cases passed.`
              : `Passed ${passedCaseCount}/${caseResults.length} sandbox test cases.`,
        output: buildPlainTextOutput(report),
        report,
      });
    } catch (error) {
      response.status(500).json({
        error: error instanceof Error ? error.message : String(error),
      });
    }
  });

  async function resolveLanguageId(languageLabel) {
    if (!cachedLanguages) {
      const response = await config.fetchImpl(`${config.judge0BaseUrl}/languages`, {
        headers: judge0Headers(),
      });
      await ensureOk(response, 'load Judge0 languages');
      const payload = await response.json();
      cachedLanguages = Array.isArray(payload) ? payload : [];
    }

    const languageMap = new Map();
    for (const item of cachedLanguages) {
      if (!item || typeof item !== 'object') {
        continue;
      }
      const id = item.id;
      const name = item.name || item.description;
      if (typeof id === 'number' && typeof name === 'string') {
        languageMap.set(normalize(name), id);
      }
    }

    for (const preferred of preferredLanguageNames(languageLabel)) {
      const exact = languageMap.get(normalize(preferred));
      if (exact != null) {
        return exact;
      }
    }

    for (const [name, id] of languageMap.entries()) {
      if (preferredLanguageNames(languageLabel).some((candidate) => name.includes(normalize(candidate)))) {
        return id;
      }
    }

    throw new Error(`Judge0 does not expose a matching language for "${languageLabel}".`);
  }

  async function executeJudge0Submission({
    languageId,
    sourceCode,
    expectedOutput = '',
    additionalFiles = '',
  }) {
    const createResponse = await config.fetchImpl(
      `${config.judge0BaseUrl}/submissions?base64_encoded=true&wait=false`,
      {
        method: 'POST',
        headers: {
          ...judge0Headers(),
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          language_id: languageId,
          source_code: encode(sourceCode),
          expected_output: expectedOutput ? encode(expectedOutput) : undefined,
          additional_files: additionalFiles || undefined,
          cpu_time_limit: 2,
          cpu_extra_time: 0.5,
          wall_time_limit: 8,
          memory_limit: 128000,
        }),
      },
    );
    await ensureOk(createResponse, 'create Judge0 submission');
    const createPayload = await createResponse.json();
    if (!createPayload || typeof createPayload.token !== 'string') {
      throw new Error('Judge0 did not return a submission token.');
    }

    for (let attempt = 0; attempt < 12; attempt += 1) {
      const pollResponse = await config.fetchImpl(
        `${config.judge0BaseUrl}/submissions/${createPayload.token}?base64_encoded=true&fields=token,status,stdout,stderr,compile_output,message,exit_code,time,memory`,
        {
          headers: judge0Headers(),
        },
      );
      await ensureOk(pollResponse, 'poll Judge0 submission');
      const payload = await pollResponse.json();
      const statusId = payload?.status?.id;
      if (statusId !== 1 && statusId !== 2) {
        return {
          statusDescription: payload?.status?.description || 'Unknown',
          stdout: decode(payload.stdout),
          stderr: decode(payload.stderr),
          compileOutput: decode(payload.compile_output),
          message: decode(payload.message),
          exitCode: payload.exit_code,
          time: payload.time,
          memory: payload.memory,
        };
      }
      await delay(1000);
    }

    throw new Error('Judge0 timed out while polling the submission.');
  }

  function judge0Headers() {
    if (!config.judge0AuthToken) {
      return {};
    }
    return {
      [config.judge0AuthHeader]: config.judge0AuthToken,
    };
  }

  return app;
}

function startServer(options = {}) {
  const app = createApp(options);
  const port = Number(options.port || process.env.PORT || 8787);
  const server = app.listen(port, () => {
    console.log(`Sandbox proxy listening on http://localhost:${port}`);
  });
  return server;
}

async function encodeAdditionalFiles({ entryFilePath, fileContents }) {
  const extraEntries = Object.entries(fileContents).filter(([path, content]) => {
    return path !== entryFilePath && typeof content === 'string' && content.length > 0;
  });

  if (extraEntries.length === 0) {
    return '';
  }

  const zip = new JSZip();
  for (const [path, content] of extraEntries) {
    zip.file(path, content);
  }

  return zip.generateAsync({ type: 'base64' });
}

function composeSource({ harnessTemplate, sourceCode, testBody }) {
  return harnessTemplate
    .replace('{{USER_CODE}}', sourceCode)
    .replace('{{TEST_BODY}}', testBody);
}

function buildSectionsFromSubmissions(submissions) {
  return buildCombinedSections(
    submissions.map((submission, index) => ({
      label: `Case ${index + 1}`,
      stdout: submission.stdout,
      stderr: submission.stderr,
      compileOutput: submission.compileOutput,
      message: submission.message,
      actualOutput: actualOutputForSubmission(submission),
    })),
  );
}

function buildSectionsFromCaseResults(caseResults) {
  return buildCombinedSections(caseResults);
}

function buildCombinedSections(items) {
  const sections = [];
  const stdoutContent = joinLabeled(items, 'stdout');
  const stderrContent = joinLabeled(items, 'stderr');
  const compileContent = joinLabeled(items, 'compileOutput');
  const messageContent = joinLabeled(items, 'message');

  if (stdoutContent) {
    sections.push({ id: 'stdout', title: 'Stdout', content: stdoutContent });
  }
  if (stderrContent) {
    sections.push({ id: 'stderr', title: 'Stderr', content: stderrContent });
  }
  if (compileContent) {
    sections.push({ id: 'compile', title: 'Compile', content: compileContent });
  }
  if (messageContent) {
    sections.push({ id: 'message', title: 'Message', content: messageContent });
  }

  if (sections.length === 0) {
    sections.push({
      id: 'details',
      title: 'Details',
      content: 'No stdout, stderr, compile output, or extra message was produced.',
    });
  }

  return sections;
}

function joinLabeled(items, key) {
  const parts = items
    .filter((item) => typeof item[key] === 'string' && item[key].trim().length > 0)
    .map((item) => `${item.label}\n${item[key].trim()}`);
  return parts.join('\n\n');
}

function actualOutputForSubmission(submission) {
  const stdout = submission.stdout.trim();
  if (stdout) {
    return stdout;
  }
  const compileOutput = submission.compileOutput.trim();
  if (compileOutput) {
    return compileOutput;
  }
  const stderr = submission.stderr.trim();
  if (stderr) {
    return stderr;
  }
  return submission.message.trim();
}

function buildPlainTextOutput(report) {
  const lines = [`${report.engineLabel} · ${report.statusLabel}`];
  if (report.programResult) {
    lines.push(`${report.programResult.label}: ${report.programResult.statusLabel}`);
    if (report.programResult.actualOutput) {
      lines.push(report.programResult.actualOutput);
    }
  }
  if (report.totalCaseCount > 0) {
    lines.push(`Passed ${report.passedCaseCount}/${report.totalCaseCount} test cases`);
  }
  for (const section of report.sections) {
    lines.push('');
    lines.push(`${section.title}:`);
    lines.push(section.content);
  }
  return lines.join('\n');
}

function preferredLanguageNames(languageLabel) {
  const normalized = normalize(languageLabel);
  if (normalized === 'python') {
    return ['Python (3.8.1)', 'Python (3.11.2)', 'Python'];
  }
  if (normalized === 'c#') {
    return ['C# (.NET Core SDK 7.0.400)', 'C# (.NET Core)', 'C#'];
  }
  return [languageLabel];
}

function normalize(value) {
  return String(value).trim().toLowerCase();
}

function encode(value) {
  return Buffer.from(String(value), 'utf8').toString('base64');
}

function decode(value) {
  if (!value) {
    return '';
  }
  try {
    return Buffer.from(String(value), 'base64').toString('utf8');
  } catch (_error) {
    return String(value);
  }
}

async function ensureOk(response, action) {
  if (response.ok) {
    return;
  }
  const body = await response.text();
  throw new Error(`Failed to ${action} (${response.status}): ${body}`);
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

if (require.main === module) {
  startServer();
}

module.exports = {
  createApp,
  startServer,
};
