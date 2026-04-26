# frozen_string_literal: true

module Phaser
  module Internal
    # Small string helpers shared across stacked-PR surfaces.
    module TextHelpers
      module_function

      # First non-empty line of `text`, with the trailing newline
      # chomped. Returns an empty string when `text` is nil or empty
      # so callers serialising the value (e.g., into the
      # `phase-creation-failed` event's `summary` field) always carry
      # a defined string.
      def first_line(text)
        return '' if text.nil? || text.empty?

        text.each_line.first.to_s.chomp
      end
    end
  end
end
