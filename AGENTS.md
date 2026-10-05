# Versioning

- Evaluate whether each change requires a version bump.
- New features: increment the minor version and reset the patch version (for example, `0.1.4` -> `0.2.0`).
- Bug fixes and small improvements: increment the patch version (for example, `0.1.4` -> `0.1.5`).
- Documentation-only changes do not require a version bump.
- The single source of truth is `Sources/kvinta/Resources/AppMetadata.plist`. Update `CFBundleShortVersionString` there and increment `CFBundleVersion` for each version bump. Do not hardcode the version in Swift or duplicate it elsewhere.
