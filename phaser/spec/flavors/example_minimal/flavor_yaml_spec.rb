# frozen_string_literal: true

require 'phaser'

# Specs for the shipped `example-minimal` flavor catalog at
# `phaser/flavors/example-minimal/flavor.yaml` (feature
# 007-multi-phase-pipeline; T037).
#
# `example-minimal` is the toy flavor that proves the engine is truly
# flavor-agnostic — no domain knowledge from a real-world stack leaks
# into the engine, the example-minimal catalog is the only flavor a
# fresh checkout exercises end-to-end, and the
# `ExampleMinimalFixture` recipe (`phaser/spec/fixtures/repos/
# example-minimal/recipe.rb`, T029) is constructed against the exact
# task-type / inference-rule / precedent-rule shape declared here.
#
# This spec pins the catalog's externally observable contract so a
# future edit to `flavor.yaml` cannot silently desynchronise from the
# recipe or the engine pipeline. Concretely it asserts:
#
#   1. The shipped file exists at the canonical path.
#   2. `Phaser::FlavorLoader#load('example-minimal')` returns a
#      validated `Phaser::Flavor` value object — i.e., the catalog is
#      schema-valid per `contracts/flavor.schema.yaml` and passes every
#      cross-field rule in `data-model.md`.
#   3. The catalog declares exactly the two task types
#      (`schema` :alone and `misc` :groups), one inference rule
#      (`schema-by-path` for `db/migrate/*.rb`), and one precedent rule
#      (`misc-after-schema`) that the recipe and the example-minimal
#      engine fixture rely on (per the recipe header in T029).
RSpec.describe 'example-minimal flavor catalog' do # rubocop:disable RSpec/DescribeClass
  let(:flavor_path) do
    File.expand_path('../../../flavors/example-minimal/flavor.yaml', __dir__)
  end

  let(:flavor) { Phaser::FlavorLoader.new.load('example-minimal') }

  it 'ships at phaser/flavors/example-minimal/flavor.yaml' do
    expect(File.file?(flavor_path)).to be(true)
  end

  it 'loads as a Phaser::Flavor via the production FlavorLoader' do
    expect(flavor).to be_a(Phaser::Flavor)
  end

  it 'declares the canonical name, version, and default_type' do
    expect(flavor.name).to eq('example-minimal')
    expect(flavor.version).to eq('0.1.0')
    expect(flavor.default_type).to eq('misc')
  end

  it 'declares the two task types the recipe expects with the documented isolation' do
    by_name = flavor.task_types.to_h { |t| [t.name, t] }
    expect(by_name.keys).to contain_exactly('schema', 'misc')
    expect(by_name.fetch('schema').isolation).to eq(:alone)
    expect(by_name.fetch('misc').isolation).to eq(:groups)
  end

  it 'declares the schema-by-path inference rule the recipe relies on' do
    rule = flavor.inference_rules.find { |r| r.name == 'schema-by-path' }

    expect(rule).not_to be_nil
    expect(rule.task_type).to eq('schema')
    expect(rule.match).to include('kind' => 'file_glob', 'pattern' => 'db/migrate/*.rb')
  end

  it 'declares the misc-after-schema precedent rule' do
    rule = flavor.precedent_rules.find { |r| r.name == 'misc-after-schema' }

    expect(rule).not_to be_nil
    expect(rule.subject_type).to eq('misc')
    expect(rule.predecessor_type).to eq('schema')
  end

  it 'ships an empty forbidden_operations registry (toy flavor has no domain bans)' do
    expect(flavor.forbidden_operations).to eq([])
  end

  it 'ships a non-empty stack_detection signals list so flavor-init can match it' do
    expect(flavor.stack_detection.signals).not_to be_empty
  end
end
