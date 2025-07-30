# TODOs for Later - RunAnywhereAI

This document tracks technical improvements and fixes that should be addressed in the future.

## Model Size Calculation for .mlpackage Directories

### Issue Description
The `verify_urls.sh` script cannot properly calculate sizes for HuggingFace-hosted `.mlpackage` directories (used by Swift Transformers models). These are Core ML model packages that are stored as directory structures rather than single files.

### Current State
- **Script**: `/scripts/verify_urls.sh` (lines 93-123 in `get_file_size()` function)
- **Affected Models**: All Swift Transformers models in `ModelURLRegistry.swift`:
  - OpenELM-270M-Instruct (currently showing ~1GB)
  - OpenELM-450M-Instruct (currently showing ~1.7GB)  
  - OpenELM-1.1B-Instruct (currently showing ~4GB)

### Technical Details
1. **Problem**: `.mlpackage` files on HuggingFace are directory structures, not single files
2. **Current Approach**: The script tries to use the HuggingFace API to sum file sizes, but the API returns 0 or very small sizes
3. **Working Implementation**: `HuggingFaceDirectoryDownloader.swift` (lines 108-126) correctly handles this by recursively listing and downloading all files

### Manual Size Verification
Using the HuggingFace API with proper authentication:
```bash
# OpenELM-270M actual size: ~1.0 GB
curl -sL --header "Authorization: Bearer $HF_TOKEN" \
  "https://huggingface.co/api/models/corenet-community/coreml-OpenELM-270M-Instruct/tree/main/OpenELM-270M-Instruct-128-float32.mlpackage/Data/com.apple.CoreML/weights"

# OpenELM-450M actual size: ~1.7 GB  
# OpenELM-1.1B actual size: ~4.0 GB
```

### Proposed Solution
1. **Option 1**: Enhance `verify_urls.sh` to properly handle HuggingFace directory structures by:
   - Detecting `.mlpackage` extensions
   - Using recursive API calls to sum all file sizes (similar to `HuggingFaceDirectoryDownloader.swift`)
   - Caching results to avoid repeated API calls

2. **Option 2**: Create a separate script specifically for HuggingFace directory models:
   - `scripts/update_hf_directory_sizes.sh`
   - Reuse logic from `HuggingFaceDirectoryDownloader.swift`
   - Store size metadata in a separate file

3. **Option 3**: Manually maintain sizes for directory-based models:
   - Add a comment in `ModelURLRegistry.swift` with verified sizes
   - Update sizes during model addition/updates

### References
- **Size Calculation Logic**: See `HuggingFaceDirectoryDownloader.swift` lines 108-126 for working recursive directory traversal
- **API Endpoints**: HuggingFace API documentation at https://huggingface.co/docs/hub/api
- **Authentication**: Requires HuggingFace token for private models

### Priority
Low - The sizes are currently close enough for user guidance. This is mainly a technical accuracy improvement.

---

## Other TODOs

### 1. TensorFlow Lite Implementation Improvements
See `/thoughts/shared/plans/tensorflow_lite_modernization_plan.md` for the complete modernization plan including:
- GPU/Neural Engine acceleration
- Complete model inference pipeline
- LLM support with proper tokenization
- Quantization support (int4/int8)

### 2. Model Download Progress Accuracy
The download progress for directory-based models shows file count progress rather than byte-accurate progress. Consider enhancing to show actual download percentage based on bytes.

### 3. Script Compatibility
The `verify_urls.sh` script uses bash features not available in macOS's default bash 3.2:
- Associative arrays (declare -A)
- Consider rewriting for POSIX compatibility or requiring bash 4+

---

*Last Updated: July 29, 2025*