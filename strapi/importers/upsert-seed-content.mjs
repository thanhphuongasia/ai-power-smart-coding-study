import fs from "node:fs/promises";

const inputPath = process.argv[2] || "seed/seed_content.json";
const baseUrl = process.env.STRAPI_BASE_URL;
const apiToken = process.env.STRAPI_API_TOKEN;

if (!baseUrl || !apiToken) {
  console.error("STRAPI_BASE_URL and STRAPI_API_TOKEN are required.");
  process.exit(1);
}

const raw = await fs.readFile(inputPath, "utf8");
const payload = JSON.parse(raw);

for (const track of payload.tracks || []) {
  await upsertCollectionEntry("learning-tracks", track.id, {
    ...track,
    slug: track.id,
    version: payload.exportedAt,
    status: "published",
  });
}

for (const skill of payload.skills || []) {
  await upsertCollectionEntry("skill-nodes", skill.id, {
    ...skill,
    slug: skill.id,
    version: payload.exportedAt,
    status: "published",
  });
}

console.log(
  `Imported ${payload.tracks?.length || 0} tracks and ${payload.skills?.length || 0} skills into Strapi.`,
);

async function upsertCollectionEntry(collectionPath, stableId, data) {
  const existingResponse = await fetch(
    `${baseUrl}/api/${collectionPath}?filters[id][$eq]=${encodeURIComponent(stableId)}`,
    {
      headers: headers(),
    },
  );
  const existingPayload = await existingResponse.json();
  const existingId = existingPayload?.data?.[0]?.id;

  if (existingId) {
    await fetch(`${baseUrl}/api/${collectionPath}/${existingId}`, {
      method: "PUT",
      headers: headers(),
      body: JSON.stringify({ data }),
    });
    return;
  }

  await fetch(`${baseUrl}/api/${collectionPath}`, {
    method: "POST",
    headers: headers(),
    body: JSON.stringify({ data }),
  });
}

function headers() {
  return {
    "Content-Type": "application/json",
    Authorization: `Bearer ${apiToken}`,
  };
}
