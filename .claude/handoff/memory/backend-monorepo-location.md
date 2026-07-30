---
name: backend-monorepo-location
description: "The RunAnywhere backend/frontend monorepo lives at /home/home/Projects/Runanywhere-monorepo, separate from this SDK repo"
metadata: 
  node_type: memory
  type: project
  originSessionId: 16bc371b-e60e-4d76-b083-037c3d930444
  modified: 2026-07-26T11:38:03.557Z
---

The company's other repo is `/home/home/Projects/Runanywhere-monorepo` — FastAPI backend (`backend/`, with alembic migrations, model catalog, GGUF parsing, assignments), Vite frontend (`frontend/`), plus `integration/`, `docs/`, `scripts/`. It does not vendor or build llama.cpp; `llamacpp` there is only a framework identifier in catalog/assignment data.

**Why:** Questions about model catalog, assignments, or telemetry ingestion are answered in that repo, not in `runanywhere-sdks`.

**How to apply:** Check it when a question is server-side (catalog seeding, deployments, telemetry endpoints). Native/engine pins stay in `sdk/runanywhere-commons/VERSIONS` in this repo.
