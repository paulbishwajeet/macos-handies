# Packaging: Redact Personals .pkg installer

Builds a single, double-clickable, self-contained `.pkg` for the
"Redact Personals" Finder Quick Action — no Python, Homebrew, or pip
required on the recipient's machine. The PDF redaction engine is frozen
into the package itself.

## Build

Prerequisites:
- Xcode Command Line Tools (`xcode-select --install`) for `pkgbuild` /
  `productbuild`.
- Rosetta 2, for building the x86_64 leg on Apple Silicon
  (`softwareupdate --install-rosetta --agree-to-license` if not already
  installed).
- Internet access (installs PyMuPDF + PyInstaller for each architecture
  automatically).

```bash
cd pdf_redactor/packaging
./build-binary.sh   # freezes redact.py into a universal (arm64 + x86_64) binary
./build-pkg.sh       # assembles the .pkg
```

Output: `pdf_redactor/packaging/build/RedactPersonals.pkg` — this is the
only file you need to share with a recipient. Nothing else from this
repo is required on their end.

## For recipients

This installer is **unsigned** (no Apple Developer ID). On first launch,
macOS Gatekeeper will likely block it. To open it anyway:

1. Right-click `RedactPersonals.pkg` and choose **Open** (instead of
   double-clicking), then confirm **Open** in the dialog that appears.
2. If it's still blocked, go to **System Settings > Privacy & Security**,
   scroll to the security section, and click **Open Anyway** next to the
   blocked-app message, then try opening the `.pkg` again.

The installer does not require an admin password — it installs only into
your own user account (`~/Library/Services`), not system-wide.

After installing, right-click any `.pdf` file in Finder and choose
**Quick Actions > Redact Personals**. If the menu item doesn't appear
immediately, log out and back in, or run:
`/System/Library/CoreServices/pbs -flush`

## Uninstall

There is no uninstaller `.pkg`. To remove it, delete:
`~/Library/Services/Redact Personals.workflow`
