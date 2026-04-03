#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTERS_DIR="${ROOT_DIR}/clusters"

if [[ ! -d "${CLUSTERS_DIR}" ]]; then
  echo "ERROR: clusters directory not found at ${CLUSTERS_DIR}" >&2
  exit 2
fi

shopt -s nullglob
files=( "${CLUSTERS_DIR}"/*.yml "${CLUSTERS_DIR}"/*.yaml )
shopt -u nullglob

if [[ ${#files[@]} -eq 0 ]]; then
  echo "ERROR: no cluster definitions found in ${CLUSTERS_DIR}" >&2
  exit 2
fi

if ! command -v ruby >/dev/null 2>&1; then
  echo "ERROR: ruby is required to validate cluster definitions" >&2
  exit 2
fi

# shellcheck disable=SC2016
ruby -e '
  require "yaml"

  REQUIRED_STRING_KEYS = %w[
    cluster_name
    cloud_vendor
    environment
    tenant_repository
    tenant_revision
    tenant_path
    tenant_cost_center
    platform_repository
    platform_revision
    platform_path
    cluster_type
    tenant
  ].freeze

  OPTIONAL_MAPPING_KEYS = %w[labels annotations].freeze

  ALLOWED_CLOUD_VENDORS = %w[aws gcp azure].freeze
  ALLOWED_CLUSTER_TYPES = %w[standalone hub spoke].freeze

  URL_RE = /\A(https:\/\/|http:\/\/|ssh:\/\/|git@)[\w.\-:\/~]+(\.git)?\/?\z/i

  def nonempty_string?(v)
    v.is_a?(String) && !v.strip.empty?
  end

  def validate_map_of_strings(doc, key, path, errors)
    return if doc[key].nil?
    unless doc[key].is_a?(Hash)
      errors << "#{path}: `#{key}` must be a mapping of string:string"
      return
    end
    doc[key].each do |k, v|
      if !k.is_a?(String) || k.strip.empty?
        errors << "#{path}: `#{key}` contains a non-string/empty key: #{k.inspect}"
      end
      unless v.is_a?(String)
        errors << "#{path}: `#{key}.#{k}` must be a string (got #{v.class})"
      end
    end
  end

  errors = []
  ARGV.each do |file|
    path = file
    stem = File.basename(file, File.extname(file))
    raw = File.read(file, encoding: "UTF-8")

    doc = begin
      YAML.safe_load(raw, permitted_classes: [], permitted_symbols: [], aliases: false)
    rescue => e
      errors << "#{path}: invalid YAML: #{e.message}"
      next
    end

    unless doc.is_a?(Hash)
      errors << "#{path}: expected a YAML mapping at document root"
      next
    end

    expected = (REQUIRED_STRING_KEYS + OPTIONAL_MAPPING_KEYS).to_h { |k| [k, true] }
    unknown = doc.keys.reject { |k| expected.key?(k) }.sort
    unless unknown.empty?
      errors << "#{path}: unknown keys not allowed: #{unknown.join(", ")}"
    end

  REQUIRED_STRING_KEYS.each do |k|
    if !doc.key?(k)
      errors << "#{path}: missing required key `#{k}`"
      next
    end
    if k == "tenant_path"
      errors << "#{path}: `#{k}` must be a string" unless doc[k].is_a?(String)
    else
      errors << "#{path}: `#{k}` must be a non-empty string" unless nonempty_string?(doc[k])
    end
  end

    if doc["cluster_name"].is_a?(String) && doc["cluster_name"] != stem
      errors << "#{path}: `cluster_name` must match filename stem (#{stem.inspect}), got #{doc["cluster_name"].inspect}"
    end

    if doc["cloud_vendor"].is_a?(String) && !ALLOWED_CLOUD_VENDORS.include?(doc["cloud_vendor"])
      errors << "#{path}: `cloud_vendor` must be one of #{ALLOWED_CLOUD_VENDORS.sort.inspect}, got #{doc["cloud_vendor"].inspect}"
    end

    if doc["cluster_type"].is_a?(String) && !ALLOWED_CLUSTER_TYPES.include?(doc["cluster_type"])
      errors << "#{path}: `cluster_type` must be one of #{ALLOWED_CLUSTER_TYPES.sort.inspect}, got #{doc["cluster_type"].inspect}"
    end

    %w[tenant_repository platform_repository].each do |k|
      v = doc[k]
      if v.is_a?(String) && !v.strip.empty? && !(v.strip =~ URL_RE)
        errors << "#{path}: `#{k}` does not look like a valid git URL: #{v.inspect}"
      end
    end

    if doc["platform_path"].is_a?(String) && doc["platform_path"].strip.empty?
      errors << "#{path}: `platform_path` must be a non-empty string"
    end

    validate_map_of_strings(doc, "labels", path, errors)
    validate_map_of_strings(doc, "annotations", path, errors)
  end

  if errors.any?
    warn "Cluster definition validation failed:"
    errors.each { |e| warn "- #{e}" }
    exit 1
  end

  puts "OK: validated #{ARGV.length} cluster definition(s)"
' "${files[@]}"

