# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'yaml'
require 'phaser'

# Specs for Phaser::FlavorInit::StackDetector — the stack-detection
# surface the `phaser-flavor-init` CLI consults to suggest a shipped
# flavor for a project that has not yet opted in (feature
# 007-multi-phase-pipeline; T079/T081, FR-031, data-model.md
# "StackDetection" / "Signal", contracts/flavor.schema.yaml,
# contracts/flavor-init-cli.md "Auto-Detection (FR-031)").
#
# The detector is a pure function over the cross-product of:
#
#   * The set of shipped flavors under the loader's flavors root, each
#     of which declares a `stack_detection.signals` list of `file_present`
#     and `file_contains` checks (data-model.md "StackDetection").
#
#   * The project root the operator is running `phaser-flavor-init` in.
#
# Its contract is the behavior listed in T079:
#
#   1. Iterate every shipped flavor (via Phaser::FlavorLoader's
#      `shipped_flavor_names` surface so the detector reuses a single
#      source of truth for what "shipped" means).
#
#   2. For each flavor, evaluate the `stack_detection.signals` from its
#      `flavor.yaml`, checking each `required: true` signal against the
#      project root per the data-model.md StackDetection table:
#
#        * file_present   — the file exists at the given path.
#        * file_contains  — the file exists AND its contents match the
#                           given regex pattern.
#
#   3. Return the list of flavors whose required signals ALL match. The
#      list is alphabetical by flavor name so the CLI can rely on a
#      deterministic order when surfacing multi-match disambiguation
#      (R-015 / contracts/flavor-init-cli.md exit code 2).
#
# Determinism (FR-002, SC-002): the detector consults only the
# filesystem and the loaded flavor catalogs — no environment variables,
# no network, no clock. Two runs against the same project root and the
# same flavors root return identical results.
RSpec.describe 'Phaser::FlavorInit::StackDetector' do
  # The system-under-test is constructed per-example with collaborators
  # injected so the spec can swap in a hermetic flavors root and a
  # hermetic project root. Production callers use the defaults
  # (`Phaser::FlavorLoader.new` against the shipped `phaser/flavors/`
  # tree, and `Dir.pwd` as the project root); the spec injects both.
  subject(:detector) do
    Phaser::FlavorInit::StackDetector.new(flavor_loader: flavor_loader)
  end

  let(:flavor_loader) { Phaser::FlavorLoader.new(flavors_root: flavors_root) }

  # Canonical well-formed catalog the happy-path tests build on. Mirrors
  # `phaser/flavors/example-minimal/flavor.yaml` but lets each test
  # override `stack_detection` to exercise specific signal combinations.
  let(:base_catalog) do
    {
      'name' => 'example-minimal',
      'version' => '0.1.0',
      'default_type' => 'misc',
      'task_types' => [
        { 'name' => 'schema', 'isolation' => 'alone',
          'description' => 'Schema-level change requiring its own phase.' },
        { 'name' => 'misc', 'isolation' => 'groups',
          'description' => 'Default catch-all for unclassified commits.' }
      ],
      'precedent_rules' => [
        { 'name' => 'misc-after-schema', 'subject_type' => 'misc',
          'predecessor_type' => 'schema',
          'error_message' => 'A misc commit must follow a schema commit.' }
      ],
      'inference_rules' => [
        { 'name' => 'schema-by-path', 'precedence' => 100,
          'task_type' => 'schema',
          'match' => { 'kind' => 'file_glob', 'pattern' => 'db/migrate/*.rb' } }
      ],
      'forbidden_operations' => [],
      'stack_detection' => {
        'signals' => [
          { 'type' => 'file_present', 'path' => 'Gemfile', 'required' => true }
        ]
      }
    }
  end

  attr_reader :flavors_root, :project_root

  around do |example|
    Dir.mktmpdir('phaser-stack-detector-flavors-') do |tmp_flavors|
      Dir.mktmpdir('phaser-stack-detector-project-') do |tmp_project|
        @flavors_root = tmp_flavors
        @project_root = tmp_project
        example.run
      end
    end
  end

  # Helper: write a shipped flavor's `flavor.yaml` under the per-example
  # flavors root. Mirrors `flavor_loader_spec.rb#write_flavor` so the two
  # spec files use the same fixture-construction surface.
  def write_flavor(name, catalog)
    flavor_dir = File.join(flavors_root, name)
    FileUtils.mkdir_p(flavor_dir)
    File.write(File.join(flavor_dir, 'flavor.yaml'), YAML.dump(catalog))
    flavor_dir
  end

  # Helper: write a file under the per-example project root with the
  # given relative path and contents. Used to satisfy `file_present` /
  # `file_contains` signals from the test side.
  def write_project_file(relative_path, contents)
    absolute_path = File.join(project_root, relative_path)
    FileUtils.mkdir_p(File.dirname(absolute_path))
    File.write(absolute_path, contents)
  end

  describe '#detect — returns matching flavors for the project root' do
    # The most basic contract: a single shipped flavor whose only
    # required signal is `file_present: Gemfile`. With Gemfile present,
    # the flavor matches; without it, it does not. Pinned per FR-031.
    it 'returns the flavor when its only required file_present signal matches' do
      write_flavor('example-minimal', base_catalog)
      write_project_file('Gemfile', "source 'https://rubygems.org'\n")

      matches = detector.detect(project_root: project_root)

      expect(matches).to eq(['example-minimal'])
    end

    it 'returns an empty list when the required file_present signal does not match' do
      write_flavor('example-minimal', base_catalog)
      # No Gemfile written — the only required signal cannot match.

      matches = detector.detect(project_root: project_root)

      expect(matches).to eq([])
    end

    it 'returns the flavor when its only required file_contains signal matches' do
      catalog = base_catalog.merge(
        'stack_detection' => {
          'signals' => [
            { 'type' => 'file_contains', 'path' => 'Gemfile.lock',
              'pattern' => 'rails \\(', 'required' => true }
          ]
        }
      )
      write_flavor('example-minimal', catalog)
      write_project_file('Gemfile.lock', "GEM\n  rails (7.1.0)\n")

      matches = detector.detect(project_root: project_root)

      expect(matches).to eq(['example-minimal'])
    end

    it 'rejects a file_contains signal when the file exists but the pattern is absent' do
      catalog = base_catalog.merge(
        'stack_detection' => {
          'signals' => [
            { 'type' => 'file_contains', 'path' => 'Gemfile.lock',
              'pattern' => 'rails \\(', 'required' => true }
          ]
        }
      )
      write_flavor('example-minimal', catalog)
      write_project_file('Gemfile.lock', "GEM\n  sinatra (3.0.0)\n")

      expect(detector.detect(project_root: project_root)).to eq([])
    end

    it 'rejects a file_contains signal when the file does not exist at all' do
      catalog = base_catalog.merge(
        'stack_detection' => {
          'signals' => [
            { 'type' => 'file_contains', 'path' => 'Gemfile.lock',
              'pattern' => 'rails \\(', 'required' => true }
          ]
        }
      )
      write_flavor('example-minimal', catalog)
      # No Gemfile.lock written — the file_contains signal cannot match.

      expect(detector.detect(project_root: project_root)).to eq([])
    end
  end

  describe '#detect — multi-signal flavors require ALL required signals to match' do
    # The reference flavor `rails-postgres-strong-migrations` declares
    # four required signals (Gemfile.lock present, plus three
    # file_contains checks for pg, strong_migrations, rails). All four
    # must match for the flavor to be a candidate.
    let(:rails_pg_strong_catalog) do
      base_catalog.merge(
        'name' => 'rails-postgres-strong-migrations',
        'stack_detection' => {
          'signals' => [
            { 'type' => 'file_present', 'path' => 'Gemfile.lock',
              'required' => true },
            { 'type' => 'file_contains', 'path' => 'Gemfile.lock',
              'pattern' => 'pg \\(', 'required' => true },
            { 'type' => 'file_contains', 'path' => 'Gemfile.lock',
              'pattern' => 'strong_migrations \\(', 'required' => true },
            { 'type' => 'file_contains', 'path' => 'Gemfile.lock',
              'pattern' => 'rails \\(', 'required' => true }
          ]
        }
      )
    end

    let(:full_lock_contents) do
      <<~LOCK
        GEM
          remote: https://rubygems.org/
          specs:
            pg (1.5.4)
            rails (7.1.2)
            strong_migrations (1.7.0)
      LOCK
    end

    it 'returns the flavor when every required signal matches' do
      write_flavor('rails-postgres-strong-migrations', rails_pg_strong_catalog)
      write_project_file('Gemfile.lock', full_lock_contents)

      matches = detector.detect(project_root: project_root)

      expect(matches).to eq(['rails-postgres-strong-migrations'])
    end

    it 'rejects the flavor when any one required signal fails' do
      write_flavor('rails-postgres-strong-migrations', rails_pg_strong_catalog)
      # Drop the strong_migrations line so three of four signals match.
      partial = full_lock_contents.lines.reject { |l| l.include?('strong_migrations') }.join
      write_project_file('Gemfile.lock', partial)

      expect(detector.detect(project_root: project_root)).to eq([])
    end
  end

  describe '#detect — required: false signals do not gate matching' do
    # data-model.md "StackDetection" reads "all `required: true` signals
    # must match"; signals with `required: false` are informational and
    # MUST NOT block a flavor from being a candidate.
    it 'returns the flavor when required signals match even if a non-required signal fails' do
      catalog = base_catalog.merge(
        'stack_detection' => {
          'signals' => [
            { 'type' => 'file_present', 'path' => 'Gemfile', 'required' => true },
            { 'type' => 'file_present', 'path' => 'Dockerfile', 'required' => false }
          ]
        }
      )
      write_flavor('example-minimal', catalog)
      write_project_file('Gemfile', "source 'https://rubygems.org'\n")
      # No Dockerfile — the non-required signal does not match, but the
      # required signal does.

      matches = detector.detect(project_root: project_root)

      expect(matches).to eq(['example-minimal'])
    end
  end

  describe '#detect — multi-flavor cross-product' do
    # contracts/flavor-init-cli.md "Auto-Detection (FR-031)" instructs
    # the CLI to evaluate every shipped flavor; the detector returns the
    # full match list so the CLI can branch on zero / one / many. The
    # list is sorted alphabetically by flavor name so the CLI can render
    # a deterministic disambiguation prompt under R-015.
    let(:rails_catalog) do
      base_catalog.merge(
        'name' => 'rails-postgres-strong-migrations',
        'stack_detection' => {
          'signals' => [
            { 'type' => 'file_contains', 'path' => 'Gemfile.lock',
              'pattern' => 'rails \\(', 'required' => true }
          ]
        }
      )
    end

    let(:minimal_catalog) do
      base_catalog.merge(
        'stack_detection' => {
          'signals' => [
            { 'type' => 'file_present', 'path' => 'Gemfile', 'required' => true }
          ]
        }
      )
    end

    it 'returns multiple flavors when more than one matches the project' do
      write_flavor('example-minimal', minimal_catalog)
      write_flavor('rails-postgres-strong-migrations', rails_catalog)
      write_project_file('Gemfile', "source 'https://rubygems.org'\n")
      write_project_file('Gemfile.lock', "GEM\n  rails (7.1.2)\n")

      matches = detector.detect(project_root: project_root)

      expect(matches).to eq(
        %w[example-minimal rails-postgres-strong-migrations]
      )
    end

    it 'returns matches in alphabetical order regardless of flavor write order' do
      # Write the alphabetically-later flavor first so any iteration
      # order that depends on Dir.children traversal is exercised.
      write_flavor('rails-postgres-strong-migrations', rails_catalog)
      write_flavor('example-minimal', minimal_catalog)
      write_project_file('Gemfile', "source 'https://rubygems.org'\n")
      write_project_file('Gemfile.lock', "GEM\n  rails (7.1.2)\n")

      matches = detector.detect(project_root: project_root)

      expect(matches).to eq(
        %w[example-minimal rails-postgres-strong-migrations]
      )
    end

    it 'returns only the matching flavor when others have unsatisfied required signals' do
      write_flavor('example-minimal', minimal_catalog)
      write_flavor('rails-postgres-strong-migrations', rails_catalog)
      write_project_file('Gemfile', "source 'https://rubygems.org'\n")
      # No Gemfile.lock — only example-minimal's signal matches.

      matches = detector.detect(project_root: project_root)

      expect(matches).to eq(['example-minimal'])
    end

    it 'returns an empty list when no shipped flavor matches the project' do
      write_flavor('example-minimal', minimal_catalog)
      write_flavor('rails-postgres-strong-migrations', rails_catalog)
      # Empty project root — neither flavor's required signal matches.

      expect(detector.detect(project_root: project_root)).to eq([])
    end

    it 'returns an empty list when the flavors root has no shipped flavors' do
      # No flavors written; the loader's shipped_flavor_names is empty.
      expect(detector.detect(project_root: project_root)).to eq([])
    end
  end

  describe '#detect — determinism' do
    # FR-002 / SC-002 require deterministic output across re-runs. The
    # detector consults only the filesystem and the flavor catalogs, so
    # two consecutive runs against the same inputs return the same list.
    it 'returns the same match list across two consecutive runs' do
      write_flavor('example-minimal', base_catalog)
      write_project_file('Gemfile', "source 'https://rubygems.org'\n")

      first  = detector.detect(project_root: project_root)
      second = detector.detect(project_root: project_root)

      expect(second).to eq(first)
    end
  end
end
