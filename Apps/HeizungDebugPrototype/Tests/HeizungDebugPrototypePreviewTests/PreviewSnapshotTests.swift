import SnapshottingTests

// Deliberately empty: SnapshotTest generates one test per #Preview found in the linked
// binaries at runtime and writes each render to SNAPSHOTS_EXPORT_DIR (without the
// variable, renders attach to the .xcresult). Capture through the jk:prototyper skill's
// verify-snapshots.sh — export mode swallows render failures silently.
final class PreviewSnapshotTests: SnapshotTest {}
