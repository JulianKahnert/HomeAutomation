# Claude Code Development Guide

## Build Commands

### Swift Package (Server/Library)
```bash
swift build
```

### FlowKitAdapter (iOS App)
```bash
cd Apps/FlowKitAdapter
xcodebuild -project "FlowKit Adapter.xcodeproj" -scheme "FlowKit Adapter" -sdk iphonesimulator -configuration Debug build
```

**Note**: After creating new Swift files in `Apps/FlowKitAdapter/Views/`, you must add them to the Xcode project manually using Xcode or update the `.pbxproj` file.

### FlowKitController (iOS App)
```bash
cd Apps/FlowKitController
xcodebuild -project "FlowKit Controller.xcodeproj" -scheme "FlowKit Controller" -sdk iphonesimulator -configuration Debug build
```

## Pre-Commit Checklist

Before committing changes that affect iOS apps:

1. Run SwiftLint:
   ```bash
   swiftlint --fix
   ```

2. Build Swift Package:
   ```bash
   swift build
   ```

3. Build affected iOS app(s):
   ```bash
   # For FlowKitAdapter changes
   cd Apps/FlowKitAdapter && xcodebuild -project "FlowKit Adapter.xcodeproj" -scheme "FlowKit Adapter" -sdk iphonesimulator -configuration Debug build

   # For FlowKitController changes
   cd Apps/FlowKitController && xcodebuild -project "FlowKit Controller.xcodeproj" -scheme "FlowKit Controller" -sdk iphonesimulator -configuration Debug build
   ```

4. Ensure all builds pass before committing

## Project Structure

- `Sources/` - Swift Package modules (HAModels, Adapter, Server, etc.)
- `Apps/FlowKitAdapter/` - HomeKit Adapter iOS app
- `Apps/FlowKitController/` - Home Automation Controller iOS app
- `Tests/` - Unit tests

## Common Issues

### "Cannot find [Type] in scope" in Xcode build

**Cause**: New Swift files not added to Xcode project

**Solution**: Open the `.xcodeproj` in Xcode and add the files to the target, or manually edit the `.pbxproj` file

### Build works with `swift build` but fails with `xcodebuild`

**Cause**: Xcode projects have separate build configuration from SPM

**Solution**: Ensure all dependencies are properly linked in Xcode project settings
