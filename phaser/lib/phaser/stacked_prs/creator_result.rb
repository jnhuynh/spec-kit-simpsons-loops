# frozen_string_literal: true

module Phaser
  module StackedPrs
    # Value object + builders for the Result returned by
    # `Phaser::StackedPrs::Creator#create` (feature
    # 007-multi-phase-pipeline; T075, FR-026, FR-039, FR-040).
    #
    # Why this lives in its own file:
    #
    #   The Creator class has a single load-bearing responsibility (walk
    #   the manifest, decide skip/create/halt for each phase, persist
    #   failures). The Result-building boilerplate — "fill in the same
    #   six fields, vary which ones get sentinel nils" — is independent
    #   of that walk and pulling it out keeps the Creator under the
    #   community-default Metrics/ClassLength ceiling without losing
    #   the per-builder documentation each variant deserves.
    #
    #   The three builders correspond to the three terminal states the
    #   Creator can reach:
    #
    #     1. **Success** — every phase in the manifest is created or
    #        skipped because it already existed.
    #
    #     2. **Failure** — at least one phase failed to create; the
    #        Creator wrote `phase-creation-status.yaml` naming the
    #        failed phase as `first_uncreated_phase` (FR-039).
    #
    #     3. **Manifest missing** — the precondition gate at the top of
    #        `#create` short-circuited because the input manifest is
    #        absent. The CLI maps this distinct outcome to exit 3
    #        ("operational error") per `contracts/stacked-pr-creator-cli.md`,
    #        whereas regular failures map to exit 1 or 2.
    module CreatorResult
      # The result object returned by `Phaser::StackedPrs::Creator#create`.
      # A successful result carries the lists of phases that were created
      # in this run and the phases that were skipped because both their
      # branch and PR already existed with the expected base. A failed
      # result carries whichever phases were successfully completed
      # BEFORE the failure (so an operator scanning the result sees
      # exactly what is on the host) and the resume point.
      Value = Data.define(
        :success?,
        :phases_created,
        :phases_skipped_existing,
        :failure_class,
        :first_uncreated_phase,
        :manifest_path
      )

      module_function

      # Build a successful Result. `failure_class` and
      # `first_uncreated_phase` are nil on success so a downstream
      # consumer can pattern-match on `success?` without having to
      # check those fields for sentinel values.
      def success(phases_created:, phases_skipped_existing:, manifest_path:)
        Value.new(
          success?: true,
          phases_created: phases_created,
          phases_skipped_existing: phases_skipped_existing,
          failure_class: nil,
          first_uncreated_phase: nil,
          manifest_path: manifest_path
        )
      end

      # Build a failed Result. The phases_created list reflects only
      # the phases that were fully created BEFORE the failure (FR-039:
      # phases 1..K-1 are left intact; phase K is the resume point).
      def failure(phases_created:, phases_skipped_existing:, failure_class:,
                  first_uncreated_phase:, manifest_path:)
        Value.new(
          success?: false,
          phases_created: phases_created,
          phases_skipped_existing: phases_skipped_existing,
          failure_class: failure_class,
          first_uncreated_phase: first_uncreated_phase,
          manifest_path: manifest_path
        )
      end

      # Build the Result returned when no manifest is present. The
      # CLI maps this distinct outcome to exit 3 ("operational
      # error"); no status file is written and gh is never invoked.
      def manifest_missing(manifest_path)
        Value.new(
          success?: false,
          phases_created: [],
          phases_skipped_existing: [],
          failure_class: nil,
          first_uncreated_phase: nil,
          manifest_path: manifest_path
        )
      end
    end
  end
end
