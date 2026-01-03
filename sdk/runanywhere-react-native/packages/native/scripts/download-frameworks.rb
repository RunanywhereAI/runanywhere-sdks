#!/usr/bin/env ruby
#
# download-frameworks.rb
#
# Downloads iOS XCFrameworks from GitHub releases:
# - RACommons from runanywhere-sdks
# - RABackendLlamaCPP from runanywhere-sdks
# - RABackendONNX from runanywhere-sdks
# - onnxruntime from runanywhere-binaries
#
# Usage:
#   ruby scripts/download-frameworks.rb
#   ruby scripts/download-frameworks.rb --commons-only
#

require 'fileutils'
require 'net/http'
require 'uri'
require 'open-uri'

# =============================================================================
# Version Constants (MUST match Swift Package.swift and Podspec)
# =============================================================================
COMMONS_VERSION = "0.1.0"
CORE_VERSION = "0.1.1-dev.03aacf9"
GITHUB_ORG = "RunanywhereAI"

# =============================================================================
# Paths
# =============================================================================
SCRIPT_DIR = File.dirname(__FILE__)
FRAMEWORKS_DIR = File.join(SCRIPT_DIR, "../ios/Frameworks")

# =============================================================================
# Download Configuration
# =============================================================================
DOWNLOADS = {
  "RACommons" => {
    url: "https://github.com/#{GITHUB_ORG}/runanywhere-sdks/releases/download/commons-v#{COMMONS_VERSION}/RACommons-#{COMMONS_VERSION}.zip",
    required: true,
    repo: "runanywhere-sdks"
  },
  "RABackendLlamaCPP" => {
    url: "https://github.com/#{GITHUB_ORG}/runanywhere-sdks/releases/download/commons-v#{COMMONS_VERSION}/RABackendLlamaCPP-#{COMMONS_VERSION}.zip",
    required: false,
    repo: "runanywhere-sdks"
  },
  "RABackendONNX" => {
    url: "https://github.com/#{GITHUB_ORG}/runanywhere-sdks/releases/download/commons-v#{COMMONS_VERSION}/RABackendONNX-#{COMMONS_VERSION}.zip",
    required: false,
    repo: "runanywhere-sdks"
  },
  "onnxruntime" => {
    url: "https://github.com/#{GITHUB_ORG}/runanywhere-binaries/releases/download/core-v#{CORE_VERSION}/onnxruntime-ios-v#{CORE_VERSION}.zip",
    required: false,
    repo: "runanywhere-binaries"
  }
}

# =============================================================================
# Helper Functions
# =============================================================================

def download_file(url, dest)
  puts "  Downloading from #{url}..."

  uri = URI.parse(url)

  begin
    # Follow redirects (GitHub releases use redirects)
    downloaded = URI.open(url,
      "User-Agent" => "RunAnywhere-SDK-Downloader/1.0",
      redirect: true
    )

    File.open(dest, 'wb') do |file|
      file.write(downloaded.read)
    end

    size_kb = File.size(dest) / 1024
    puts "  Downloaded #{size_kb}KB"
    true
  rescue OpenURI::HTTPError => e
    puts "  HTTP Error: #{e.message}"
    false
  rescue => e
    puts "  Error: #{e.message}"
    false
  end
end

def extract_zip(zip_file, dest_dir)
  puts "  Extracting..."
  system("unzip -q -o #{zip_file} -d #{dest_dir}")
  $?.success?
end

# =============================================================================
# Main
# =============================================================================

puts "=" * 60
puts "RunAnywhere iOS Framework Downloader"
puts "=" * 60
puts ""
puts "Commons Version: #{COMMONS_VERSION}"
puts "Core Version: #{CORE_VERSION}"
puts "Target Directory: #{FRAMEWORKS_DIR}"
puts ""

# Parse arguments
commons_only = ARGV.include?('--commons-only')

# Clean and create frameworks directory
if File.exist?(FRAMEWORKS_DIR)
  puts "Cleaning existing frameworks directory..."
  FileUtils.rm_rf(FRAMEWORKS_DIR)
end
FileUtils.mkdir_p(FRAMEWORKS_DIR)

# Download each framework
success_count = 0
fail_count = 0

DOWNLOADS.each do |name, config|
  # Skip optional frameworks if commons-only
  if commons_only && name != "RACommons"
    puts "⏭️  Skipping #{name} (commons-only mode)"
    next
  end

  puts ""
  puts "📦 Downloading #{name}..."
  puts "   Repository: #{config[:repo]}"

  zip_file = File.join(FRAMEWORKS_DIR, "#{name}.zip")

  begin
    if download_file(config[:url], zip_file)
      if extract_zip(zip_file, FRAMEWORKS_DIR)
        FileUtils.rm(zip_file)
        puts "✅ #{name} installed"
        success_count += 1
      else
        puts "❌ Failed to extract #{name}"
        fail_count += 1
      end
    else
      if config[:required]
        puts "❌ FAILED to download required framework #{name}"
        fail_count += 1
      else
        puts "⚠️  Optional framework #{name} not available"
      end
    end
  rescue => e
    if config[:required]
      puts "❌ FAILED: #{e.message}"
      fail_count += 1
    else
      puts "⚠️  Optional framework #{name} not downloaded: #{e.message}"
    end
  end
end

# Write version file
version_file = File.join(FRAMEWORKS_DIR, ".version")
File.write(version_file, "#{COMMONS_VERSION}-#{CORE_VERSION}")

# Summary
puts ""
puts "=" * 60
puts "Summary"
puts "=" * 60
puts "✅ Successful: #{success_count}"
puts "❌ Failed: #{fail_count}"
puts ""

if fail_count > 0
  puts "Some required frameworks failed to download!"
  puts "Please check the URLs and try again."
  exit 1
else
  puts "All frameworks downloaded to #{FRAMEWORKS_DIR}"

  # List installed frameworks
  puts ""
  puts "Installed frameworks:"
  Dir.glob("#{FRAMEWORKS_DIR}/*.xcframework").each do |framework|
    name = File.basename(framework)
    puts "  - #{name}"
  end
end
