# Config data for project packs

Data files (`*.yml`, `*.json`) read by **config-backed prose packs** in `../project/`.

A config-backed prose pack names its data file (e.g. `Config: .specify/marge/config/linked-files.yml`) and treats it as rule data. Keeping the data here — separate from the rule prose in `../project/` — lets one pack serve many cases without editing the rule.

If a pack's config file is absent or empty, the pack emits zero findings (inert by default). Add data files here to activate config-backed project packs.

See `../README.md` for the full pack contract and the glossary (pack, `PROJECT_GATE`, quality gate).
