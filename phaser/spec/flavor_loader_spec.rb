# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'yaml'
require 'phaser'

# Specs for Phaser::FlavorLoader — the surface that reads a shipped
# flavor catalog from `phaser/flavors/<name>/flavor.yaml`, validates it
# against `contracts/flavor.schema.yaml` (data-model.md "Flavor"
# Validation rules), requires the optional Ruby pattern modules the
# catalog references (`inference_module`, `forbidden_module`,
# `validators`), and returns a Phaser::Flavor value object the engine
# can consume (feature 007-multi-phase-pipeline; T018/T019, plan.md
# "Pattern: Flavor Loader" / D-002, research.md R-003).
#
# The loader is the single ingress for flavor data. Its contract is the
# behavior listed in T018:
#
#   1. Well-formed flavors load successfully and surface every catalog
#      attribute the engine needs (task types, precedent rules,
#      inference rules, forbidden operations, default type, version,
#      stack-detection signals).
#
#   2. Malformed flavors raise a descriptive error AT LOAD TIME — the
#      validation surface is fail-fast, so a flavor that would corrupt
#      the manifest never reaches the engine. The error message names
#      the flavor and the specific violation so the operator can fix
#      it without grepping the schema.
#
#   3. An unknown flavor name (e.g., from a project's
#      `.specify/flavor.yaml` selecting a flavor that has not been
#      shipped) produces a descriptive error that LISTS the shipped
#      flavors, so the operator can correct the typo or pick a real
#      flavor name without inspecting the source tree.
#
# The loader is stateless; the tests below build per-example fixture
# directories to keep test runs independent and to allow injecting
# malformed catalogs without touching `phaser/flavors/` on disk.
RSpec.describe Phaser::FlavorLoader do # rubocop:disable RSpec/SpecFilePathFormat
  # Per-example fixtures directory acting as the `phaser/flavors/` root
  # the loader is pointed at. Using a temp directory (rather than the
  # real `phaser/flavors/` tree) keeps the suite hermetic — malformed
  # fixtures can be written without polluting the shipped catalog and
  # the cleanup is automatic.
  # The system-under-test: a loader pointed at the per-example fixture
  # root. Loaders are stateless, so a single instance per example is
  # sufficient. Declared before the `around` hook to satisfy
  # rubocop-rspec's LeadingSubject cop.
  subject(:loader) { described_class.new(flavors_root: flavors_root) }

  attr_reader :flavors_root

  around do |example|
    Dir.mktmpdir('phaser-flavor-loader-spec') do |tmp|
      @flavors_root = tmp
      example.run
    end
  end

  # A canonical well-formed flavor body that the happy-path tests
  # write to disk. Mirrors the shape of the `example-minimal` flavor
  # the engine ships (T037/T038): two task types, one precedent rule,
  # one inference rule, an empty forbidden-operations registry, and a
  # single stack-detection signal.
  let(:well_formed_catalog) do
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

  # Helper: write the given catalog Hash as `flavor.yaml` under a
  # per-flavor subdirectory of the fixture root. Returns the directory
  # path so callers can drop adjacent Ruby modules alongside the YAML
  # when a test needs to exercise the optional `inference_module` or
  # `forbidden_module` resolution.
  def write_flavor(name, catalog)
    flavor_dir = File.join(flavors_root, name)
    FileUtils.mkdir_p(flavor_dir)
    File.write(File.join(flavor_dir, 'flavor.yaml'), YAML.dump(catalog))
    flavor_dir
  end

  describe '#load — happy path on a well-formed flavor' do
    before { write_flavor('example-minimal', well_formed_catalog) }

    it 'returns a Phaser::Flavor value object for a well-formed catalog' do
      flavor = loader.load('example-minimal')

      expect(flavor).to be_a(Phaser::Flavor)
    end

    it 'exposes the top-level identity attributes (name, version, default_type)' do
      flavor = loader.load('example-minimal')

      expect(flavor.name).to eq('example-minimal')
      expect(flavor.version).to eq('0.1.0')
      expect(flavor.default_type).to eq('misc')
    end

    it 'exposes the task_types catalog with isolation and description fields' do
      flavor = loader.load('example-minimal')

      schema = flavor.task_types.find { |t| t.name == 'schema' }
      expect(schema.isolation).to eq(:alone)
      expect(schema.description).to eq('Schema-level change requiring its own phase.')
    end

    it 'exposes the precedent_rules with subject and predecessor type names' do
      flavor = loader.load('example-minimal')

      rule = flavor.precedent_rules.first
      expect(rule.name).to eq('misc-after-schema')
      expect(rule.subject_type).to eq('misc')
      expect(rule.predecessor_type).to eq('schema')
    end

    it 'exposes the inference_rules with precedence and match payloads' do
      flavor = loader.load('example-minimal')

      rule = flavor.inference_rules.first
      expect(rule.name).to eq('schema-by-path')
      expect(rule.precedence).to eq(100)
      expect(rule.task_type).to eq('schema')
      expect(rule.match).to include('kind' => 'file_glob', 'pattern' => 'db/migrate/*.rb')
    end

    it 'exposes the stack_detection signals so flavor-init can reuse the surface' do
      flavor = loader.load('example-minimal')

      signal = flavor.stack_detection.signals.first
      expect(signal).to include('type' => 'file_present', 'path' => 'Gemfile', 'required' => true)
    end

    it 'returns an empty forbidden_operations list when the catalog declares none' do
      flavor = loader.load('example-minimal')

      expect(flavor.forbidden_operations).to eq([])
    end
  end

  describe '#load — schema validation against contracts/flavor.schema.yaml' do
    # The data-model.md "Validation rules" section enumerates the
    # cross-field checks the loader is responsible for. Each test below
    # writes a fixture that violates one rule and asserts the loader
    # raises a descriptive error at load time. The errors all surface
    # under a single Phaser::FlavorLoadError ancestor so callers can
    # rescue the loader surface uniformly.
    it 'rejects a flavor whose name field is missing' do
      catalog = well_formed_catalog.dup
      catalog.delete('name')
      write_flavor('example-minimal', catalog)

      expect { loader.load('example-minimal') }
        .to raise_error(Phaser::FlavorLoadError, /name/)
    end

    it 'rejects a flavor whose version field is missing' do
      catalog = well_formed_catalog.dup
      catalog.delete('version')
      write_flavor('example-minimal', catalog)

      expect { loader.load('example-minimal') }
        .to raise_error(Phaser::FlavorLoadError, /version/)
    end

    it 'rejects a flavor whose default_type is not present in task_types' do
      catalog = well_formed_catalog.dup
      catalog['default_type'] = 'unknown-type'
      write_flavor('example-minimal', catalog)

      expect { loader.load('example-minimal') }
        .to raise_error(Phaser::FlavorLoadError, /default_type.*unknown-type|unknown-type.*task_types/i)
    end

    it 'rejects a flavor whose precedent_rule references an unknown subject_type' do
      catalog = well_formed_catalog.dup
      catalog['precedent_rules'] = [
        { 'name' => 'bad-subject', 'subject_type' => 'phantom',
          'predecessor_type' => 'schema',
          'error_message' => 'phantom not in catalog' }
      ]
      write_flavor('example-minimal', catalog)

      expect { loader.load('example-minimal') }
        .to raise_error(Phaser::FlavorLoadError, /phantom/)
    end

    it 'rejects a flavor whose precedent_rule references an unknown predecessor_type' do
      catalog = well_formed_catalog.dup
      catalog['precedent_rules'] = [
        { 'name' => 'bad-predecessor', 'subject_type' => 'misc',
          'predecessor_type' => 'phantom',
          'error_message' => 'phantom not in catalog' }
      ]
      write_flavor('example-minimal', catalog)

      expect { loader.load('example-minimal') }
        .to raise_error(Phaser::FlavorLoadError, /phantom/)
    end

    it 'rejects a self-loop precedent_rule (subject == predecessor)' do
      catalog = well_formed_catalog.dup
      catalog['precedent_rules'] = [
        { 'name' => 'self-loop', 'subject_type' => 'schema',
          'predecessor_type' => 'schema',
          'error_message' => 'must not self-loop' }
      ]
      write_flavor('example-minimal', catalog)

      expect { loader.load('example-minimal') }
        .to raise_error(Phaser::FlavorLoadError, /self.?loop|reflexive|same|subject/i)
    end

    it 'rejects a flavor whose inference_rule references an unknown task_type' do
      catalog = well_formed_catalog.dup
      catalog['inference_rules'] = [
        { 'name' => 'bad-rule', 'precedence' => 1, 'task_type' => 'phantom',
          'match' => { 'kind' => 'file_glob', 'pattern' => '*.rb' } }
      ]
      write_flavor('example-minimal', catalog)

      expect { loader.load('example-minimal') }
        .to raise_error(Phaser::FlavorLoadError, /phantom/)
    end

    it 'rejects a flavor with an empty task_types list (schema requires minItems: 1)' do
      catalog = well_formed_catalog.dup
      catalog['task_types'] = []
      catalog['default_type'] = 'misc' # still present but unsatisfiable
      write_flavor('example-minimal', catalog)

      expect { loader.load('example-minimal') }
        .to raise_error(Phaser::FlavorLoadError, /task_types/)
    end

    it 'rejects a flavor whose name does not match the directory it ships under' do
      catalog = well_formed_catalog.dup
      catalog['name'] = 'mismatched-name'
      write_flavor('example-minimal', catalog)

      expect { loader.load('example-minimal') }
        .to raise_error(Phaser::FlavorLoadError, /mismatched-name|directory|name/)
    end

    it 'raises a descriptive error when the YAML payload is not parseable' do
      flavor_dir = File.join(flavors_root, 'example-minimal')
      FileUtils.mkdir_p(flavor_dir)
      File.write(File.join(flavor_dir, 'flavor.yaml'), ":\n  not valid yaml: [unclosed")

      expect { loader.load('example-minimal') }
        .to raise_error(Phaser::FlavorLoadError, /yaml|parse|invalid/i)
    end
  end

  describe '#load — unknown flavor name surface (FlavorConfiguration / Edge Case)' do
    # A project's `.specify/flavor.yaml` may reference a flavor that
    # was never shipped (typo, removal). The loader's contract is to
    # raise a descriptive error that LISTS the shipped flavors so the
    # operator can correct the typo or pick a real flavor name without
    # inspecting the source tree.
    before do
      write_flavor('example-minimal', well_formed_catalog)
      write_flavor('rails-postgres-strong-migrations',
                   well_formed_catalog.merge('name' => 'rails-postgres-strong-migrations'))
    end

    it 'raises FlavorNotFoundError when the requested flavor is not shipped' do
      expect { loader.load('nonexistent-flavor') }
        .to raise_error(Phaser::FlavorNotFoundError)
    end

    it 'names the missing flavor in the error message' do
      loader.load('nonexistent-flavor')
    rescue Phaser::FlavorNotFoundError => e
      expect(e.message).to include('nonexistent-flavor')
    end

    it 'lists every shipped flavor in the error message so the operator can pick one' do
      loader.load('nonexistent-flavor')
    rescue Phaser::FlavorNotFoundError => e
      expect(e.message).to include('example-minimal')
      expect(e.message).to include('rails-postgres-strong-migrations')
    end

    it 'returns the shipped-flavor list via #shipped_flavor_names for flavor-init reuse' do
      expect(loader.shipped_flavor_names).to contain_exactly(
        'example-minimal', 'rails-postgres-strong-migrations'
      )
    end
  end

  describe 'class hierarchy — error types descend from FlavorLoadError' do
    # Both the schema-validation surface and the unknown-flavor surface
    # raise errors a caller can rescue uniformly. FlavorNotFoundError is
    # a subclass of FlavorLoadError so a single `rescue
    # Phaser::FlavorLoadError` clause in the engine wrapper handles all
    # load-time failures.
    it 'declares Phaser::FlavorLoadError as the rescuable ancestor' do
      expect(Phaser::FlavorLoadError).to be < StandardError
    end

    it 'declares Phaser::FlavorNotFoundError as a FlavorLoadError subclass' do
      expect(Phaser::FlavorNotFoundError).to be < Phaser::FlavorLoadError
    end
  end
end
