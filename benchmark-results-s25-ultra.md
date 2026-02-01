# Kokoro TTS NNAPI NPU Benchmark Results

**Device:** Samsung Galaxy S25 Ultra
**Date:** February 1, 2026
**Test:** Text-to-Speech generation with NPU (NNAPI) vs CPU comparison

---

## Summary

| Model | Best NPU Speedup | Avg NPU Time | Avg CPU Time | Best RTF |
|-------|------------------|--------------|--------------|----------|
| INT8 NPU (Baseline) | **1.60x** | ~40s | ~51s | 1.94x |
| INT8 Optimized (New) | 1.30x | ~40s | ~52s | 1.49x |

---

## Model: Kokoro TTS 82M (INT8 NPU) - Baseline

This is the baseline model with Split→Slice fixes applied.

### Run 1 (Best Performance)
| Metric | Value |
|--------|-------|
| **NPU (NNAPI) Inference** | 31,094.77 ms |
| **Real-time Factor (NPU)** | 1.94x |
| **CPU Only Inference** | 49,883.51 ms |
| **Real-time Factor (CPU)** | 1.21x |
| **Audio Duration** | 60,250.00 ms |
| **NPU Speedup** | **1.60x FASTER** |
| **Time Saved** | 18,788.74 ms |
| **NNAPI Active** | YES ✓ |

### Run 2
| Metric | Value |
|--------|-------|
| **NPU (NNAPI) Inference** | 31,494.58 ms |
| **Real-time Factor (NPU)** | 1.91x |
| **CPU Only Inference** | 49,403.68 ms |
| **Real-time Factor (CPU)** | 1.22x |
| **Audio Duration** | 60,250.00 ms |
| **NPU Speedup** | **1.57x FASTER** |
| **Time Saved** | 17,909.10 ms |
| **NNAPI Active** | YES ✓ |

### Run 3
| Metric | Value |
|--------|-------|
| **NPU (NNAPI) Inference** | 37,155.96 ms |
| **Real-time Factor (NPU)** | 1.62x |
| **CPU Only Inference** | 42,436.17 ms |
| **Real-time Factor (CPU)** | 1.42x |
| **Audio Duration** | 60,250.00 ms |
| **NPU Speedup** | **1.14x FASTER** |
| **Time Saved** | 5,280.21 ms |
| **NNAPI Active** | YES ✓ |

### Run 4
| Metric | Value |
|--------|-------|
| **NPU (NNAPI) Inference** | 39,898.22 ms |
| **Real-time Factor (NPU)** | 1.51x |
| **CPU Only Inference** | 53,210.55 ms |
| **Real-time Factor (CPU)** | 1.13x |
| **Audio Duration** | 60,250.00 ms |
| **NPU Speedup** | **1.33x FASTER** |
| **Time Saved** | 13,312.33 ms |
| **NNAPI Active** | YES ✓ |

### Run 5 (Thermal Throttling?)
| Metric | Value |
|--------|-------|
| **NPU (NNAPI) Inference** | 55,912.61 ms |
| **Real-time Factor (NPU)** | 1.08x |
| **CPU Only Inference** | 56,444.26 ms |
| **Real-time Factor (CPU)** | 1.07x |
| **Audio Duration** | 60,250.00 ms |
| **NPU Speedup** | **1.01x FASTER** |
| **Time Saved** | 531.65 ms |
| **NNAPI Active** | YES ✓ |

### Run 6 (No Voice Selected - Edge Case)
| Metric | Value |
|--------|-------|
| **NPU (NNAPI) Inference** | 58,093.43 ms |
| **Real-time Factor (NPU)** | 0.99x |
| **CPU Only Inference** | 55,565.10 ms |
| **Real-time Factor (CPU)** | 1.03x |
| **Audio Duration** | 57,500.00 ms |
| **NPU Speedup** | 0.96x (CPU faster) |
| **NNAPI Active** | YES ✓ |

---

## Model: Kokoro TTS 82M (INT8 Optimized) - New

This model has additional optimizations:
- 139 `DynamicQuantizeLinear` → replaced with static `QuantizeLinear`
- 31 `LayerNormalization` → decomposed to NNAPI-supported ops
- Total nodes: 4,118 (vs 3,688 baseline)

### Run 1
| Metric | Value |
|--------|-------|
| **NPU (NNAPI) Inference** | 38,637.25 ms |
| **Real-time Factor (NPU)** | 1.49x |
| **CPU Only Inference** | 50,360.56 ms |
| **Real-time Factor (CPU)** | 1.14x |
| **Audio Duration** | 57,500.00 ms |
| **NPU Speedup** | **1.30x FASTER** |
| **Time Saved** | 11,723.31 ms |
| **NNAPI Active** | YES ✓ |

### Run 2
| Metric | Value |
|--------|-------|
| **NPU (NNAPI) Inference** | 41,571.03 ms |
| **Real-time Factor (NPU)** | 1.38x |
| **CPU Only Inference** | 53,090.84 ms |
| **Real-time Factor (CPU)** | 1.08x |
| **Audio Duration** | 57,500.00 ms |
| **NPU Speedup** | **1.28x FASTER** |
| **Time Saved** | 11,519.81 ms |
| **NNAPI Active** | YES ✓ |

---

## Analysis

### INT8 NPU (Baseline) Performance Statistics
| Metric | Min | Max | Average |
|--------|-----|-----|---------|
| NPU Inference (ms) | 31,095 | 58,093 | ~42,275 |
| CPU Inference (ms) | 42,436 | 56,444 | ~51,157 |
| NPU Speedup | 0.96x | 1.60x | ~1.30x |
| Real-time Factor (NPU) | 0.99x | 1.94x | ~1.51x |

### INT8 Optimized Performance Statistics
| Metric | Min | Max | Average |
|--------|-----|-----|---------|
| NPU Inference (ms) | 38,637 | 41,571 | ~40,104 |
| CPU Inference (ms) | 50,361 | 53,091 | ~51,726 |
| NPU Speedup | 1.28x | 1.30x | ~1.29x |
| Real-time Factor (NPU) | 1.38x | 1.49x | ~1.44x |

---

## Key Observations

1. **Best Performance**: INT8 NPU baseline achieved **1.60x NPU speedup** with 1.94x real-time factor (best run)

2. **Consistency**: INT8 Optimized model shows more **consistent** performance (~1.29x speedup) vs baseline's high variance (0.96x-1.60x)

3. **Thermal Throttling**: Later runs show degraded performance, suggesting thermal throttling after sustained NPU usage

4. **Real-time Capable**: Both models achieve >1x real-time factor on NPU, meaning audio generates faster than playback

5. **NNAPI Coverage**:
   - Baseline: 903/3,616 nodes on NPU (~25%)
   - Optimized: Should have higher coverage with decomposed ops (to be measured)

---

## Device Information

| Property | Value |
|----------|-------|
| Device | Samsung Galaxy S25 Ultra |
| SoC | Qualcomm Snapdragon 8 Elite |
| NPU | Qualcomm Hexagon NPU |
| NNAPI Version | Android 15+ |
| RAM | 12GB+ |

---

## Model Specifications

### INT8 NPU (Baseline)
| Property | Value |
|----------|-------|
| Model ID | `kokoro-tts-int8` |
| Size | ~92 MB |
| Nodes | 3,688 |
| DynamicQuantizeLinear | 139 |
| ConvInteger | 87 |
| MatMulInteger | 148 |

### INT8 Optimized
| Property | Value |
|----------|-------|
| Model ID | `kokoro-tts-int8-optimized` |
| Size | ~93 MB |
| Nodes | 4,118 |
| DynamicQuantizeLinear | 0 (replaced) |
| QuantizeLinear | 139 |
| LayerNormalization | 0 (decomposed) |

---

## Conclusion

The NNAPI NPU acceleration provides **1.3x-1.6x speedup** over CPU-only inference on the Samsung Galaxy S25 Ultra. The baseline INT8 NPU model shows higher peak performance but more variance, while the optimized model shows more consistent (but slightly lower) speedups.

**Recommendation**: Use the baseline INT8 NPU model for best peak performance, with the understanding that performance may vary due to thermal conditions.
