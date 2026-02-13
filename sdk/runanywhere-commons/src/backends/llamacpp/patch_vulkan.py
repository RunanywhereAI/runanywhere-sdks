#!/usr/bin/env python3
import sys
import re
import os

if len(sys.argv) != 2:
    print("Usage: patch_vulkan.py <vulkan_cmake_file>", file=sys.stderr)
    sys.exit(1)

file_path = sys.argv[1]

# Check if file exists
if not os.path.exists(file_path):
    print(f"Error: File not found: {file_path}", file=sys.stderr)
    sys.exit(1)

try:
    with open(file_path, 'r') as f:
        content = f.read()
except Exception as e:
    print(f"Error reading file: {e}", file=sys.stderr)
    sys.exit(1)

# Patch 1: Remove COMPONENTS glslc (make glslc optional)
content = content.replace('find_package(Vulkan COMPONENTS glslc REQUIRED)', 'find_package(Vulkan REQUIRED)')

# Patch 2: Comment out include(ExternalProject) completely
content = re.sub(
    r'^(\s*include\s*\(\s*ExternalProject\s*\))',
    r'# \1 # Disabled for cross-compilation',
    content,
    flags=re.MULTILINE
)

# Patch 3: Comment out file(GENERATE ...) for host-toolchain.cmake
content = re.sub(
    r'(file\s*\(\s*GENERATE[^)]*host-toolchain\.cmake[^)]*\))',
    r'# \1 # Disabled for cross-compilation',
    content,
    flags=re.DOTALL
)

# Patch 4: Comment out entire ExternalProject_Add blocks
# Find and comment out the entire ExternalProject_Add(...) block
lines = content.split('\n')
in_external_project = False
external_project_depth = 0
result_lines = []

for line in lines:
    # Check if we're starting an ExternalProject_Add
    if 'ExternalProject_Add' in line and not line.strip().startswith('#'):
        in_external_project = True
        external_project_depth = line.count('(') - line.count(')')
        result_lines.append('# ' + line + ' # Disabled for cross-compilation')
        continue
    
    # If we're inside an ExternalProject_Add block
    if in_external_project:
        external_project_depth += line.count('(') - line.count(')')
        result_lines.append('# ' + line)
        
        # Check if we've closed all parentheses
        if external_project_depth <= 0:
            in_external_project = False
            external_project_depth = 0
        continue
    
    result_lines.append(line)

content = '\n'.join(result_lines)

# Patch 5: Comment out all add_custom_command blocks that depend on vulkan-shaders-gen
lines = content.split('\n')
in_custom_command = False
custom_command_depth = 0
result_lines = []

for line in lines:
    # Check if we're starting an add_custom_command
    if 'add_custom_command' in line and not line.strip().startswith('#'):
        in_custom_command = True
        custom_command_depth = line.count('(') - line.count(')')
        result_lines.append('# ' + line + ' # Disabled for cross-compilation')
        continue
    
    # If we're inside an add_custom_command block
    if in_custom_command:
        custom_command_depth += line.count('(') - line.count(')')
        result_lines.append('# ' + line)
        
        # Check if we've closed all parentheses
        if custom_command_depth <= 0:
            in_custom_command = False
            custom_command_depth = 0
        continue
    
    result_lines.append(line)

content = '\n'.join(result_lines)

# Patch 6: Comment out target_sources that reference shader files
content = re.sub(
    r'(target_sources\s*\(\s*ggml-vulkan\s+PRIVATE\s+\$\{_ggml_vk_[^}]+\})',
    r'# \1 # Disabled for cross-compilation',
    content
)

# Patch 7: Comment out foreach loop for shader files
lines = content.split('\n')
in_foreach = False
foreach_depth = 0
result_lines = []

for line in lines:
    # Check if we're starting a foreach for shader files
    if 'foreach' in line and '_ggml_vk_shader_files' in line and not line.strip().startswith('#'):
        in_foreach = True
        foreach_depth = line.count('(') - line.count(')')
        result_lines.append('# ' + line + ' # Disabled for cross-compilation')
        continue
    
    # If we're inside a foreach block
    if in_foreach:
        foreach_depth += line.count('(') - line.count(')')
        result_lines.append('# ' + line)
        
        # Check if we've closed all parentheses (endforeach)
        if 'endforeach' in line:
            in_foreach = False
            foreach_depth = 0
        continue
    
    result_lines.append(line)

content = '\n'.join(result_lines)

# Patch 8: Comment out test_shader_extension_support calls
content = re.sub(
    r'(\s+test_shader_extension_support\s*\()',
    r'    # \1 # Disabled for cross-compilation',
    content
)

# Patch 9: Add a stub for GGML_VULKAN_SHADER_HEADERS if not present
if 'GGML_VULKAN_SHADER_HEADERS' not in content:
    # Find where to insert (after find_package(Vulkan))
    content = re.sub(
        r'(find_package\s*\(\s*Vulkan[^)]*\))',
        r'\1\n\n# Shader generation disabled for cross-compilation\nset(GGML_VULKAN_SHADER_HEADERS "" CACHE INTERNAL "Pre-compiled shaders embedded")',
        content
    )

# Patch 10: Comment out Vulkan::Vulkan link for Android (we'll use API 26 library explicitly)
content = re.sub(
    r'(\s+target_link_libraries\s*\(\s*ggml-vulkan\s+PRIVATE\s+Vulkan::Vulkan\s*\))',
    r'    # \1 # Disabled for Android - using explicit API 26 library',
    content
)

with open(file_path, 'w') as f:
    f.write(content)

print("Vulkan CMakeLists.txt patched successfully - ExternalProject disabled")
sys.exit(0)
