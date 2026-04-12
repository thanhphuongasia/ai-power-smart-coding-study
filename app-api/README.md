# App API

This service now owns both:

- learner-specific state for the mobile app
- a lightweight custom admin web for managing learning content without Strapi

## Local development

1. The repo already includes a demo snapshot at `../strapi/seed/seed_content.json`.
   If you want to regenerate that snapshot from the Dart seed curriculum, you can
   still do that:

```bash
flutter pub run tool/export_seed_content.dart strapi/seed/seed_content.json
```

2. Install dependencies and run the API:

```bash
cd app-api
npm install
BOOTSTRAP_CATALOG_PATH=../strapi/seed/seed_content.json npm start
```

The service listens on `http://127.0.0.1:8788` by default.

## Admin web

Open:

```text
http://127.0.0.1:8788/admin
```

Authentication uses `x-admin-key` with `ADMIN_API_KEY`. If you do not provide
the variable locally, the default key is:

```text
local-dev-admin-key
```

## Persistence

The learner event store is still in-memory for local development. Content is now
persisted to `app-api/data/content-store.json` with draft/published workflow.
The Prisma schema in `prisma/schema.prisma` still defines the target PostgreSQL
model for moving this service to durable storage later.
