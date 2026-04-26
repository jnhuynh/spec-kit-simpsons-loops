# frozen_string_literal: true

require 'time'

module Phaser
  module Internal
    # Default wall-clock used by `Phaser::Observability` and
    # `Phaser::StatusWriter` when no `now:` callable is injected.
    # Returns ISO-8601 UTC with millisecond precision and a `Z` suffix
    # so the format matches `contracts/observability-events.md`
    # "Common Fields" exactly. Time#iso8601(3) emits the `+00:00`
    # suffix on a UTC time, so we substitute the `Z` suffix the
    # contract requires.
    module Iso8601Clock
      module_function

      def now
        Time.now.utc.iso8601(3).sub(/\+00:00\z/, 'Z')
      end
    end
  end
end
