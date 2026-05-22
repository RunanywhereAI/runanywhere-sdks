
## 2026-05-22 Android Kotlin iter5 queue (run 20260522-014106-kotlin-verify-iter5)

| TC | Status | Notes |
| --- | --- | --- |
| TC-09 | FAIL (product) | VLM gallery analyze runs but completion marker/UI response missing after iter5 harness run on Pixel 8 Pro. |
| TC-13 | FAIL (product/harness) | Document picker driven; no `Document loaded successfully` / `Embedding generation complete` in logcat within 180s despite fixture push to Download. |
| TC-21 | FAIL (harness/product) | LoRA UI flow executed; `Loaded LoRA adapter` Timber marker never observed (only ModelBootstrap seed logs). |

**Action:** Kotlin lane blocked for full PASS/N/A matrix; Flutter/RN Android lanes not started per STOP rule.
