import {
  InferenceFramework,
  ModelCategory,
} from '@runanywhere/proto-ts/model_types';

export type PortableEmbeddingCatalogEntry = Readonly<{
  id: string;
  name: string;
  url: string;
  framework: InferenceFramework;
  modality: ModelCategory;
  memoryRequirement: number;
}>;

export const PORTABLE_NVIDIA_EMBEDDING_MODELS = [
  {
    id: 'nemotron-3-embed-1b-q4_k_m',
    name: 'NVIDIA Nemotron 3 Embed 1B Q4_K_M',
    url: 'https://huggingface.co/zenmagnets/Nemotron-3-Embed-1B-Q4_K_M-GGUF/resolve/06df1fde6f7009c91f6cc3cd520081921929a678/nemotron-3-embed-1b-q4_k_m.gguf',
    framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
    modality: ModelCategory.MODEL_CATEGORY_EMBEDDING,
    memoryRequirement: 749_352_096,
  },
  {
    id: 'llama-nemotron-embed-1b-v2-q4_k_m',
    name: 'NVIDIA Llama Nemotron Embed 1B v2 Q4_K_M',
    url: 'https://huggingface.co/mykor/llama-nemotron-embed-1b-v2-GGUF/resolve/bf7c9832b1d76f86777379e58b7b74805ee58006/llama-nemotron-embed-1B-v2-Q4_K_M.gguf',
    framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
    modality: ModelCategory.MODEL_CATEGORY_EMBEDDING,
    memoryRequirement: 807_690_624,
  },
] as const satisfies readonly PortableEmbeddingCatalogEntry[];

export const RAG_EMBEDDING_FRAMEWORKS: ReadonlySet<InferenceFramework> =
  new Set([
    InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
    InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
    InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
  ]);
