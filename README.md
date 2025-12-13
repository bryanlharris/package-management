# Package Management Utilities

## Mirror integrity baseline and verification
Use `mirror-integrity-check.ps1` to capture a baseline manifest and later verify that
mirror contents for a single mirror root have not changed unexpectedly. The manifest is
always written inside the mirror directory.

- Create a baseline for one mirror (manifest defaults to `<MirrorRoot>\\integrity-baseline.json`):
  ```powershell
  .\\mirror-integrity-check.ps1 -Mode baseline -MirrorRoot "C:\\admin\\pip_mirror"
  ```
- Verify a mirror against an existing baseline (exit code is non-zero when issues are found):
  ```powershell
  .\\mirror-integrity-check.ps1 -Mode verify -MirrorRoot "C:\\admin\\pip_mirror"
  ```

The script logs to the console and writes success/failure entries to the Windows Application
event log under the `MirrorIntegrityCheck` source.
