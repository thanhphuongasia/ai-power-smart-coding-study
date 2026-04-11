# App API

This service owns learner-specific state that should not live in Strapi:

- anonymous learner bootstrap
- sync cursor / idempotent learner events
- derived progress, dashboard, review queue, and skill memory

## Local development

1. Export a catalog snapshot from the old seed curriculum:

```bash
dart run tool/export_seed_content.dart
```

2. Install dependencies and run the API:

```bash
cd app-api
npm install
CATALOG_SNAPSHOT_PATH=../strapi/seed/seed_content.json npm start
```

The service listens on `http://127.0.0.1:8788` by default.

## Persistence

The current TypeScript server runs an in-memory learner store so the mobile app
can integrate end-to-end immediately. The Prisma schema in `prisma/schema.prisma`
defines the target PostgreSQL persistence model for moving this service from
single-process dev mode to durable storage.
