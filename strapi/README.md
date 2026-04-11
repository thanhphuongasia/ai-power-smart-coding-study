# Strapi Content Scaffold

This folder captures the content model and import pipeline for the learning
catalog that used to live entirely in `lib/data/sample_curriculum.dart`.

## Suggested workflow

1. Export the current seed curriculum into JSON:

```bash
dart run tool/export_seed_content.dart
```

2. Stand up a Strapi workspace separately and recreate the content types from
   [`content-model.json`](./content-model.json).

3. Import the exported payload into Strapi:

```bash
STRAPI_BASE_URL=http://127.0.0.1:1337 \
STRAPI_API_TOKEN=your-token \
node importers/upsert-seed-content.mjs seed/seed_content.json
```

## Scope

- `learning-track` owns nested modules and references skill ids by value.
- `skill-node` is a separate collection type so review projections can look up
  `reviewMilestoneId` independently from the catalog tree.
- The import script is idempotent by `id`/`slug`, so editorial teams can rerun
  exports after reshaping the starter curriculum.
