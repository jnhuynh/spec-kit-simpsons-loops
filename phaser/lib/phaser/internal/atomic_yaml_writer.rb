# frozen_string_literal: true

require 'psych'
require 'fileutils'
require 'securerandom'

module Phaser
  module Internal
    # Shared YAML serialization + atomic-write helpers used by the
    # manifest writer and the status writer.
    #
    # Both writers must produce byte-identical YAML across hosts
    # (FR-002, SC-002 for the manifest; the status writer follows the
    # same convention so its `timestamp` field is comparable to the
    # log records emitted alongside it). Both also write atomically so
    # a crash mid-write can never leave a half-written or corrupt
    # file at the destination.
    #
    # The `dump_yaml` contract:
    #   * `line_width: -1` disables Psych's default 80-column wrapping
    #     (long commit subjects / decomposition messages MUST stay on
    #     a single line so byte-identical determinism holds).
    #   * The `---` document header is suppressed by marking the
    #     underlying document node implicit. We build the YAMLTree
    #     directly instead of relying on `Psych.dump`'s `header:`
    #     keyword because that keyword is silently ignored on current
    #     Psych releases — going through the tree is the supported way
    #     to omit the header on every Psych version Ruby 3.2+ ships
    #     with.
    #
    # The `atomic_write` contract: write to a temp file under the
    # destination directory then rename it over the destination. If
    # either step fails, the previous destination content is preserved
    # and any temp file is cleaned up before the exception is re-raised.
    module AtomicYamlWriter
      module_function

      def dump_yaml(hash)
        visitor = Psych::Visitors::YAMLTree.create(line_width: -1)
        visitor << hash
        stream = visitor.tree
        document = stream.children.first
        document.implicit = true
        document.implicit_end = true
        stream.to_yaml
      end

      def atomic_write(path, content)
        destination_dir = File.dirname(path)
        FileUtils.mkdir_p(destination_dir)
        temp_path = File.join(
          destination_dir,
          ".#{File.basename(path)}.#{SecureRandom.hex(8)}.tmp"
        )

        begin
          File.binwrite(temp_path, content)
          File.rename(temp_path, path)
        rescue StandardError
          FileUtils.rm_f(temp_path)
          raise
        end
      end
    end
  end
end
