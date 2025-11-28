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

# Libraries to add (using modern API)
libraries = [
  'archive',   # libarchive -> archive
  'bz2',       # libbz2 -> bz2
  'c++'        # libc++ -> c++
]

# Frameworks to add (using modern API)
frameworks = [
  'Accelerate'
]

# Track what was added
added_libraries = []
added_frameworks = []

# Add libraries using modern xcodeproj API
# add_system_library_tbd handles duplicate detection automatically
libraries.each do |lib|
  # Check if already exists
  existing = target.frameworks_build_phase.files.find do |file|
    file.display_name == "lib#{lib}.tbd" || file.display_name == "lib#{lib}.dylib"
  end

  unless existing
    target.add_system_library_tbd(lib)
    added_libraries << lib
    puts "✅ Added lib#{lib}.tbd to RunAnywhereAI target"
  end
end

# Add frameworks using modern xcodeproj API
# add_system_framework handles duplicate detection automatically
frameworks.each do |framework|
  # Check if already exists
  existing = target.frameworks_build_phase.files.find do |file|
    file.display_name == "#{framework}.framework"
  end

  unless existing
    target.add_system_framework(framework)
    added_frameworks << framework
    puts "✅ Added #{framework}.framework to RunAnywhereAI target"
  end
end

# Save the project
project.save

puts ""
puts "✅ Successfully updated RunAnywhereAI.xcodeproj"
puts "   Libraries: #{libraries.join(', ')}"
puts "   Frameworks: #{frameworks.join(', ')}"
