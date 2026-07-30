"""RAG example: the ``rag`` namespace — ingest a few documents, then search and ask."""
from __future__ import annotations

import sys

import runanywhere as ra
from runanywhere import LlmOptions, ModelRef, RagConfig, RagDocument, RagEventKind

EMBEDDER = "minilm"
DEFAULT_LLM = "smollm2-135m"

DOCUMENTS = [
    "The RunAnywhere runtime executes AI models entirely on the host device. "
    "No network connection is needed for inference, only for downloading model weights.",
    "The Python SDK binds the C++ runanywhere-commons runtime through a single "
    "pybind11 extension module and exposes LLM, embedding, speech and RAG APIs.",
    "Model weights are cached under the user's RunAnywhere home directory, so a "
    "model is downloaded once and reused by every later run.",
]

QUESTION = "Does RunAnywhere need a network connection for inference?"


def main() -> int:
    llm_id = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_LLM
    ra.initialize()
    try:
        with ra.rag.open(
            ModelRef(EMBEDDER),
            ModelRef(llm_id),
            RagConfig(top_k=2, chunk_size=256, chunk_overlap=32),
        ) as session:
            session.ingest([RagDocument(text) for text in DOCUMENTS])
            stats = session.stats()
            print(f"ingested {stats.document_count} documents ({stats.chunk_count} chunks)")

            print("\n== search (retrieval only) ==")
            for match in session.search(QUESTION, top_k=2):
                print(f"  {match.score:.2f}  {match.text[:70]}...")

            print(f"\n== query ==\nquestion: {QUESTION}")
            result = session.query(QUESTION, LlmOptions(max_output_tokens=96, temperature=0.2))
            print(f"answer: {result.answer.strip()}")
            for source in result.sources:
                print(f"  source (score {source.score:.2f}): {source.text[:70]}...")

            # Commons emits token deltas then `completed`; `retrieved` is handled for when it
            # starts emitting that too.
            print("\n== query_stream ==")
            for event in session.query_stream(
                "Where are model weights cached?",
                LlmOptions(max_output_tokens=64, temperature=0.2),
            ):
                if event.kind == RagEventKind.RETRIEVED:
                    print(f"[retrieved {len(event.matches)} chunks]")
                elif event.is_token:
                    print(event.text, end="", flush=True)
                elif event.is_completed and event.result is not None:
                    print(f"\n[{len(event.result.sources)} sources]")
    finally:
        ra.reset()
    return 0


if __name__ == "__main__":
    sys.exit(main())
