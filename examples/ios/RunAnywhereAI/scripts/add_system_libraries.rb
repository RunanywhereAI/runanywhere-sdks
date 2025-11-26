#!/usr/bin/env ruby

# add_system_libraries.rb
# Adds libarchive and libbz2 to the RunAnywhereAI Xcode project

require 'xcodeproj'

project_path = File.join(File.dirname(__FILE__), '..', 'RunAnywhereAI.xcodeproj')
project = Xcodeproj::Project.open(project_path)

# Find the app target
target = project.targets.find { |t| t.name == 'RunAnywhereAI' }

if target.nil?
  puts "❌ Could not find RunAnywhereAI target"
  exit 1
end

# Libraries to add
libraries = [
  'libarchive',
  'libbz2',
  'libc++'
]

# Frameworks to add
frameworks = [
  'Accelerate'
]

# Add libraries
libraries.each do |lib|
  # Check if already exists
  existing = target.frameworks_build_phase.files.find do |file|
    file.display_name == "#{lib}.tbd" || file.display_name == "#{lib}.dylib"
  end

  next if existing

  # Add library
  file_ref = project.frameworks_group.new_file("usr/lib/#{lib}.tbd")
  file_ref.name = "#{lib}.tbd"
  file_ref.source_tree = 'SDKROOT'

  build_file = target.frameworks_build_phase.add_file_reference(file_ref)

  puts "✅ Added #{lib}.tbd to RunAnywhereAI target"
end

# Add frameworks
frameworks.each do |framework|
  # Check if already exists
  existing = target.frameworks_build_phase.files.find do |file|
    file.display_name == "#{framework}.framework"
  end

  next if existing

  # Add framework
  file_ref = project.frameworks_group.new_file("System/Library/Frameworks/#{framework}.framework")
  file_ref.name = "#{framework}.framework"
  file_ref.source_tree = 'SDKROOT'

  build_file = target.frameworks_build_phase.add_file_reference(file_ref)

  puts "✅ Added #{framework}.framework to RunAnywhereAI target"
end

# Save the project
project.save

puts ""
puts "✅ Successfully updated RunAnywhereAI.xcodeproj"
puts "   Added libraries: #{libraries.join(', ')}"
puts "   Added frameworks: #{frameworks.join(', ')}"
