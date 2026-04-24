# Solution YAML examples

Each file here is a valid input to `rac_solution_create_from_yaml()`.

| File | Shape | DAG |
| --- | --- | --- |
| `voice_agent.yaml` | `SolutionConfig.voice_agent` | VAD → STT → LLM → TTS |
| `rag.yaml` | `SolutionConfig.rag` | Query → Embed → Retrieve → ContextBuild → LLM |

The YAML subset accepted by the loader is deliberately narrow: block
mappings, block sequences, quoted/bare scalars, and `#` comments.

## Running

```cpp
#include "rac/solutions/rac_solution.h"

rac_solution_handle_t h = nullptr;
const char* yaml = read_file("voice_agent.yaml");
rac_solution_create_from_yaml(yaml, &h);
rac_solution_start(h);
// ... feed frames via rac_solution_feed(...) ...
rac_solution_close_input(h);
rac_solution_destroy(h);
```
