"""RAG example: ingest a few short documents and ask a grounded question."""
from __future__ import annotations

import sys

from runanywhere import RunAnywhere

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


def main() -> int:
    llm_id = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_LLM
    with RunAnywhere() as ra:
        with ra.create_rag(EMBEDDER, llm_model=llm_id) as rag:
            stats = rag.ingest_many(DOCUMENTS)
            print(f"ingested {stats.indexed_documents} documents ({stats.indexed_chunks} chunks)")

            question = "Does RunAnywhere need a network connection for inference?"
            print(f"\nquestion: {question}")
            result = rag.query(
                question,
                max_output_tokens=96,
                temperature=0.2,
                retrieval_top_k=2,
            )
            print(f"answer: {result.answer.strip()}")
            for hit in result.retrieved_chunks:
                print(f"  source (score {hit.similarity_score:.2f}): {hit.text[:70]}...")
    return 0


if __name__ == "__main__":
    sys.exit(main())
