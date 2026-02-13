#!/usr/bin/env python3
"""
Generate proper ggml-vulkan-shaders.cpp with aggregate arrays.
This matches what llama.cpp's vulkan-shaders-gen tool should generate.
"""

import os
import sys
from pathlib import Path

def generate_cpp_with_aggregates(vulkan_dir, output_cpp):
    """Generate .cpp with individual shader data AND aggregate arrays."""
    
    vulkan_path = Path(vulkan_dir)
    spv_files = sorted(vulkan_path.glob("*.spv"))
    
    if not spv_files:
        print(f"Error: No .spv files found in {vulkan_dir}")
        return False
    
    print(f"Found {len(spv_files)} .spv files")
    
    with open(output_cpp, 'w') as f:
        # Write header include
        f.write('#include "ggml-vulkan-shaders.hpp"\n\n')
        
        # Write each shader's binary data
        for spv_file in spv_files:
            shader_name = spv_file.stem
            
            # Read binary data
            with open(spv_file, 'rb') as spv:
                data = spv.read()
            
            # Write as unsigned char array
            f.write(f"const unsigned char {shader_name}_data[] = {{\n")
            
            # Write bytes in rows of 12
            for i in range(0, len(data), 12):
                chunk = data[i:i+12]
                hex_values = ','.join(f'0x{b:02x}' for b in chunk)
                f.write(f"    {hex_values},\n")
            
            f.write("};\n")
            f.write(f"const uint64_t {shader_name}_len = {len(data)};\n\n")
        
        # Now generate aggregate arrays for add, sub, mul, div, add_rms
        # These map to variants: [t0][t1][t2][rte] where:
        # t0, t1, t2 = 0 (f32) or 1 (f16)
        # rte = 0 (normal) or 1 (rte variant)
        
        suffixes = ["_f32", "_f16"]
        
        for op in ["add", "sub", "mul", "div", "add_rms"]:
            # Generate data array
            f.write(f"const void * {op}_data[2][2][2][2] = {{\n")
            for t0 in range(2):
                f.write("  {\n")
                for t1 in range(2):
                    f.write("    {\n")
                    for t2 in range(2):
                        f.write("      {")
                        for rte in range(2):
                            shader_name = f"{op}{suffixes[t0]}{suffixes[t1]}{suffixes[t2]}"
                            if rte == 1:
                                shader_name += "_rte"
                            f.write(f"{shader_name}_data")
                            if rte == 0:
                                f.write(", ")
                        f.write("},\n")
                    f.write("    },\n")
                f.write("  },\n")
            f.write("};\n\n")
            
            # Generate len array
            f.write(f"const uint64_t {op}_len[2][2][2][2] = {{\n")
            for t0 in range(2):
                f.write("  {\n")
                for t1 in range(2):
                    f.write("    {\n")
                    for t2 in range(2):
                        f.write("      {")
                        for rte in range(2):
                            shader_name = f"{op}{suffixes[t0]}{suffixes[t1]}{suffixes[t2]}"
                            if rte == 1:
                                shader_name += "_rte"
                            f.write(f"{shader_name}_len")
                            if rte == 0:
                                f.write(", ")
                        f.write("},\n")
                    f.write("    },\n")
                f.write("  },\n")
            f.write("};\n\n")
    
    file_size = os.path.getsize(output_cpp)
    print(f"Generated {output_cpp}")
    print(f"File size: {file_size / 1024 / 1024:.2f} MB")
    
    return True

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: generate-shader-aggregates.py <vulkan_dir> <output_cpp>")
        sys.exit(1)
    
    vulkan_dir = sys.argv[1]
    output_cpp = sys.argv[2]
    
    if generate_cpp_with_aggregates(vulkan_dir, output_cpp):
        print("✓ Success!")
        sys.exit(0)
    else:
        print("✗ Failed!")
        sys.exit(1)
