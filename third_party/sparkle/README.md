# Sparkle

Trickpad vendors `Sparkle.framework` from the official 2.9.5 release of
https://github.com/sparkle-project/Sparkle.

Source archive: `Sparkle-2.9.5.tar.xz`
SHA-256: `015336b601493e05c237964954bff6191370003d94edefe663724c88840d73cc`

Sparkle is MIT-licensed. Its license is included in this folder.

The framework is committed prebuilt rather than as source, which differs from
the other vendored dependency here. Sparkle is Swift and Objective-C with XPC
service targets and nested helper executables, and building it needs Xcode.
This project builds through a single `clang` invocation and has no Xcode
project, so the compiled framework is what can be pinned. Committing it keeps a
clean checkout buildable offline at a known version.

The framework carries nested code that must be signed along with the app:
`Updater.app`, `XPCServices/Downloader.xpc`, `XPCServices/Installer.xpc`, and
`Autoupdate`. The `codesign --force --deep` call in `scripts/build.sh` covers
them. Verify with `codesign --verify --deep --strict` against the built bundle
after changing anything about signing.

The release tools that live alongside the framework in that archive
(`generate_appcast`, `sign_update`, `generate_keys`, `BinaryDelta`) are not
vendored here. They are needed to publish a release, not to build the app.

To update: download the release archive, verify its checksum, replace
`Sparkle.framework`, and record the new version and checksum above.
