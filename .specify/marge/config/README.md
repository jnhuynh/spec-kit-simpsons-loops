# Gate config data

Data files (`*.yml`, `*.json`) consumed by **config-backed packs** in `../checks/`.

A config-backed pack names its data file (e.g. `Config: .specify/marge/config/sync-groups.yml`) and reads it as rule data. Keeping the data here — separate from the rule prose in `../checks/` — lets one pack serve many groups/cases without editing the rule itself.

If a pack's config file is absent or empty, the pack emits zero findings (inert by default). Add your data files here to activate config-backed project gates.

See `../gates/README.md` for the full project-gate contract (both script gates and config-backed packs).
