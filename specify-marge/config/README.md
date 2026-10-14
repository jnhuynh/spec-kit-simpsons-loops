# Config data for project packs

Data files (`*.yml`, `*.json`) read by **config-backed prose packs** in `../project/`.

A config-backed prose pack names its data file (e.g. `Config: .specify/marge/config/linked-files.yml`) and treats it as rule data. Keeping the data here — separate from the rule prose in `../project/` — lets one pack serve many cases without editing the rule.

If a pack's config file is absent or empty, the pack emits zero findings (inert by default). Add data files here to activate config-backed project packs.

See `../README.md` for the full pack contract and the glossary (pack, `PROJECT_GATE`, quality gate).

Two files are seeded here by `setup.sh` and read by the standards engine (`.specify/scripts/bash/speckit-standards.sh`, run by `../baseline/standards.sh`): `damage-levels.yml` (levels, reviewer lines, checklists, `aliases`, `unit_dirs`, `boundaries`) and `lexicon.yml` (`banned`, `prefer`, `soft_verbs`, `invented_phrases`, `known_terms`, `exempt_paths`). They are yours: updates never overwrite them. Delete `damage-levels.yml` and the engine goes silent.
