#!/usr/bin/env ruby

require 'xcodeproj'
require 'pathname'

# Script to automatically add model files to Xcode project

project_path = ARGV[0] || 'RunAnywhereAI.xcodeproj'
models_dir = ARGV[1] || 'RunAnywhereAI/Models'

unless File.exist?(project_path)
  puts "Error: Project file not found at #{project_path}"
  exit 1
end

unless Dir.exist?(models_dir)
  puts "Error: Models directory not found at #{models_dir}"
  exit 1
end

# Open the project
project = Xcodeproj::Project.open(project_path)

# Find the main target
target = project.targets.find { |t| t.name == 'RunAnywhereAI' }
unless target
  puts "Error: Target 'RunAnywhereAI' not found"
  exit 1
end

# Find the Models group - handle new synchronized groups
models_group = nil
app_group = nil

# First try to find the RunAnywhereAI group
project.main_group.children.each do |child|
  if child.path == 'RunAnywhereAI' || child.display_name == 'RunAnywhereAI'
    app_group = child
    break
  end
end

unless app_group
  puts "Error: RunAnywhereAI group not found in project"
  exit 1
end

# Now find the Models group within RunAnywhereAI
if app_group.respond_to?(:children)
  app_group.children.each do |child|
    if child.path == 'Models' || child.display_name == 'Models'
      models_group = child
      break
    end
  end
end

# For synchronized groups, we need to work differently
if app_group.class.name.include?('Synchronized')
  puts "Note: Project uses synchronized groups. Models should be automatically included."
  puts "Just ensure the model files exist in RunAnywhereAI/Models/ directory."
  exit 0
end

unless models_group
  puts "Creating Models group..."
  models_group = app_group.new_group('Models', 'RunAnywhereAI/Models')
end

# Model file extensions to look for
model_extensions = ['mlpackage', 'mlmodel', 'mlmodelc', 'onnx', 'tflite', 'gguf', 'bin']

# Track what we've added
added_files = []
skipped_files = []

# Find all model files
Dir.glob(File.join(models_dir, '**/*')).each do |file_path|
  next if File.directory?(file_path)

  # Check if it's a model file or part of a model package
  extension = File.extname(file_path)[1..-1]
  base_name = File.basename(file_path)

  # Skip if not a model file (unless it's inside an mlpackage)
  unless model_extensions.include?(extension) || file_path.include?('.mlpackage/')
    next if extension != 'swift' # Keep Swift files in Models group
  end

  # Check if file already exists in project
  relative_path = Pathname.new(file_path).relative_path_from(Pathname.new('.'))
  existing_ref = models_group.files.find { |f| f.path == relative_path.to_s }

  if existing_ref
    skipped_files << base_name
    next
  end

  # For mlpackage directories, add the directory not individual files
  if file_path.include?('.mlpackage/') && !file_path.end_with?('.mlpackage')
    next
  end

  # Add file reference to project
  file_ref = models_group.new_file(relative_path.to_s)

  # Add to target's resources build phase (for model files)
  if model_extensions.include?(extension)
    target.resources_build_phase.add_file_reference(file_ref)
    added_files << base_name
  elsif extension == 'swift'
    # Add Swift files to compile sources
    target.source_build_phase.add_file_reference(file_ref)
    added_files << base_name
  end
end

# Save the project
project.save

# Report results
puts "\n✅ Project updated successfully!"
puts "\nAdded #{added_files.count} files:"
added_files.each { |f| puts "  - #{f}" }

if skipped_files.any?
  puts "\nSkipped #{skipped_files.count} files (already in project):"
  skipped_files.each { |f| puts "  - #{f}" }
end

puts "\nModels are now included in the project and will be bundled with the app."
