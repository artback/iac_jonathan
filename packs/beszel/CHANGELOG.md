# Changelog

## 0.0.1 (2026-07-23)

- Initial pack: hub + agent in one Nomad job, migrated from hand-run docker
  containers (volumes `beszel_vol` / `beszel_agent_data` reused).
- Agent enriched: docker stats, temperature sensors (cpu_thermal primary),
  `/mnt/usbdrive` extra filesystem, S.M.A.R.T. via privileged mode, NIC filter.
- Images pinned to 0.18.7.
