# What's new in 1.2.1

- **Windows fix:** the zips now bundle the Visual C++ runtime DLLs (`msvcp140`, `vcruntime140`, `vcruntime140_1`), so Clean Mind launches on machines that don't already have the redistributable installed. Previously, a fresh Windows install failed with "VCRUNTIME140.dll was not found".

Nothing else changed since [1.2.0](https://github.com/MS-Teja/clean-mind/releases/tag/v1.2.0) — macOS and Linux builds are identical apart from the version number.
