# Companion packaging constraints for Windows 11 and Kubuntu 26.04 LTS

## Question

What production constraints govern signing, custom-URI registration, terminal launch, PowerShell 7, browser discovery, installation, upgrades, and rollback for a GDAP Acceptor companion on Windows 11 and Kubuntu 26.04 LTS?

## Decision summary

Ship one versioned application contract in two native packages:

- a per-machine, Authenticode-signed Windows MSI containing a small signed launcher executable plus the PowerShell payload; and
- an `amd64` Debian package installed through a dedicated, signed APT repository, containing a launcher, PowerShell payload, and freedesktop desktop entry.

The launchers—not an installer command string containing PowerShell—must receive the untrusted URI, strictly parse `m365internals-gdap://v1/accept/<GUID>`, serialize/queue requests, and then invoke a fixed payload path. On both platforms the package should depend on an in-support PowerShell 7 LTS rather than bundle PowerShell. At the time of this research, PowerShell 7.6 is the current LTS and is supported until November 2028; Microsoft explicitly lists Ubuntu 26.04 as supported through April 2031, subject to PowerShell itself remaining supported ([PowerShell lifecycle](https://learn.microsoft.com/en-us/lifecycle/products/powershell), [PowerShell on Linux](https://learn.microsoft.com/en-us/powershell/scripting/install/linux-overview?view=powershell-7.6)).

## Windows 11

### Installation and signing

Use a conventional MSI if MSI/Intune administration is a requirement. Windows supports both packaged and unpackaged desktop applications; unpackaged applications continue to use MSI/EXE installers and have unrestricted file-system, registry, and process access ([Windows packaging overview](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/packaging/)). This companion does not need MSIX identity-gated features, so adding MSIX or a sparse identity would increase release complexity without solving a requirement.

Sign both the MSI and every executable/script-host binary exposed to Windows with the same publicly trusted code-signing identity. Use SHA-256 file digests and an RFC 3161 SHA-256 timestamp, and make CI fail unless `signtool verify /pa` succeeds. Microsoft's SignTool documentation says signing protects against tampering and identifies the signer, requires an explicit digest algorithm, recommends SHA-256, supports RFC 3161 timestamps, and verifies certificate trust and revocation ([SignTool](https://learn.microsoft.com/en-us/windows/win32/seccrypto/signtool)). Keep the private signing key in a managed signing service or hardware-backed store, not in GitHub repository secrets as an exported PFX.

Signing is a production gate, not proof that Microsoft SmartScreen will immediately assign reputation. The design must not promise warning-free first-run behavior solely because the package is signed.

### URI registration

Register the proprietary URI scheme during MSI installation and remove only this application's registration during uninstall. Windows supports custom URI activation and allows more than one application to register a scheme; ultimately the user determines the selected handler ([URI activation](https://learn.microsoft.com/en-us/windows/apps/develop/launch/handle-uri-activation), [launching URI handlers](https://learn.microsoft.com/en-us/windows/apps/develop/launch/launch-default-app)). Per-user associations take precedence over machine-level registrations ([Default Programs](https://learn.microsoft.com/en-us/windows/win32/shell/default-programs)). Therefore installation must verify registration by actually querying/launch-testing under the target user's context; writing an HKLM key is not sufficient evidence that this launcher is the effective handler.

The registration command must be a fixed quoted executable path followed by exactly one quoted `%1` argument. The launcher must treat that argument as attacker-controlled input. Microsoft's URI guidance explicitly warns that any app or website can invoke a scheme and that URI data must be validated ([URI activation security considerations](https://learn.microsoft.com/en-us/windows/apps/develop/launch/handle-uri-activation#security-considerations)). It must reject extra path segments, query parameters, fragments, decoded control characters, non-canonical GUIDs, oversized input, and every scheme/version/action outside the v1 grammar before starting PowerShell. Never interpolate the URI into a shell command.

### Terminal launch

The protocol executable should create the interactive terminal session itself. Prefer `wt.exe -w new ...` when Windows Terminal is available; Microsoft documents `wt` as the supported command-line entry point and `-w new`/`-1` as the way to force a new window ([Windows Terminal command line](https://learn.microsoft.com/en-us/windows/terminal/command-line-arguments)). Fall back to a visible console-hosted `pwsh.exe` process if `wt.exe` is unavailable or disabled. Do not make the protocol registry command depend directly on `wt.exe`: Windows Terminal settings can redirect launches to an existing window/tab, and nested quoting of a URI through registry, `wt`, and PowerShell creates an avoidable injection surface.

The launcher must resolve `pwsh.exe` from a trusted installation location and verify its major/minimum supported version, not execute the first untrusted `pwsh` found on `PATH`.

### PowerShell prerequisite

Require an in-support PowerShell LTS, currently 7.6. PowerShell 7.6 LTS ends support in November 2028; 7.4 LTS ends in November 2026 ([PowerShell lifecycle](https://learn.microsoft.com/en-us/lifecycle/products/powershell)). Microsoft provides MSI/MSIX/WinGet installation, supports managed updates through Microsoft Update/WSUS/Configuration Manager, and notes that newer PowerShell 7 versions replace earlier versions when the same installation method is used ([Install PowerShell on Windows](https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell-on-windows?view=powershell-7.6)).

The companion installer should detect PowerShell and stop with an exact official remediation command rather than download or install it implicitly. This preserves enterprise control and keeps the companion MSI rollback independent of the PowerShell product. Do not require Windows PowerShell 5.1 compatibility.

### Upgrade and rollback

Use one stable MSI `UpgradeCode`, a new `ProductCode` for each major-upgrade package, and versions meaningful in the first three MSI version fields. Microsoft states that MSI major upgrades locate related products through the Upgrade table/UpgradeCode, normally remove the previous product, cannot cross per-user/per-machine install contexts, and ignore the fourth product-version field ([MSI major upgrades](https://learn.microsoft.com/en-us/windows/win32/msi/major-upgrades)). Install all releases per-machine, reject downgrades during ordinary installation, and preserve user configuration/logs as separately versioned data.

Rollback means an explicit, signed previous MSI retained in the release channel: uninstall the current product, then install the selected prior version with an explicit downgrade/recovery switch or a separately authored recovery procedure. Test that protocol ownership, trusted CIPP allowlists, logs, and queued work survive a failed upgrade and intentional rollback. Do not model an MSI major-upgrade patch as rollback; Microsoft recommends installing the full updated product rather than applying a major upgrade as a patch ([MSI major upgrades](https://learn.microsoft.com/en-us/windows/win32/msi/major-upgrades)).

## Kubuntu 26.04 LTS

### Installation and repository trust

Publish an `amd64` `.deb` through a dedicated HTTPS APT repository. Sign the repository's `InRelease` metadata with a repository-specific OpenPGP key, distribute that public key in a scoped keyring, and use a `signed-by=` source entry. APT authenticates the signed Release/InRelease metadata and the checksums that lead to package files; it does not normally authenticate an embedded signature on each `.deb` ([Debian package authentication](https://www.debian.org/doc/manuals/debian-reference/ch02), [apt-secure](https://manpages.debian.org/testing/apt/apt-secure.8.en.html)). Thus “signed Debian package” should mean a package delivered by an authenticated repository; a detached GitHub Release checksum alone is not equivalent.

The `.deb` should install immutable application files under `/opt/gdap-acceptor` or an equivalent architecture-independent application path, a stable launcher under `/usr/bin`, and its desktop entry under `/usr/share/applications`. Put mutable per-user allowlists, queues, and sanitized logs beneath XDG user config/state locations. Package maintainer scripts must update desktop/MIME caches through the distribution's normal helper mechanisms and must be idempotent on install, upgrade, removal, and abort.

### URI and terminal registration

Install a desktop entry that declares:

```ini
[Desktop Entry]
Type=Application
Name=GDAP Acceptor
Exec=/usr/bin/gdap-acceptor %u
TryExec=/usr/bin/gdap-acceptor
Terminal=true
MimeType=x-scheme-handler/m365internals-gdap;
NoDisplay=true
```

The freedesktop Desktop Entry Specification defines `Exec`, `TryExec`, `Terminal`, and URI field codes; `%u` represents one URI, and field codes must be standalone arguments rather than embedded inside another argument ([Desktop Entry Specification](https://specifications.freedesktop.org/desktop-entry/latest-single/)). `Terminal=true` delegates visible terminal creation to the desktop environment, so the package should not hard-code Konsole. This is the portable Kubuntu contract and respects the user's configured terminal.

Register/query the handler in the logged-in desktop session. `xdg-mime default <desktop-id> x-scheme-handler/m365internals-gdap` may be subject to desktop policy or user approval, requires the application desktop file to declare the MIME type, and should not be run as root; `xdg-mime query default` verifies the effective handler ([xdg-mime](https://portland.freedesktop.org/doc/xdg-mime.html)). Consequently, a root `.deb` maintainer script should install the system-wide candidate but must not overwrite every user's association. First-run setup should request/verify the association as the user and explain KDE System Settings remediation when policy prevents it.

As on Windows, the launcher receives untrusted `%u` data, parses the exact v1 grammar without a shell, and starts a fixed PowerShell payload. Do not put `sh -c`, `bash -c`, or `pwsh -Command` in the desktop file.

### PowerShell prerequisite

Depend on `powershell` at an in-support LTS floor, currently 7.6, and document Microsoft's package repository as the supported prerequisite source. Microsoft lists Ubuntu 26.04 as supported until April 2031, subject to PowerShell reaching its own end of support first, recommends LTS for compatibility, and publishes `.deb` packages through `packages.microsoft.com` ([PowerShell on Linux](https://learn.microsoft.com/en-us/powershell/scripting/install/linux-overview?view=powershell-7.6)).

This is evidence for Ubuntu 26.04 compatibility, not a specific Microsoft certification of every Kubuntu desktop component. The PowerShell/runtime layer is Ubuntu-supported; the KDE URI/terminal layer therefore needs an explicit Kubuntu 26.04 integration test before release.

### Upgrade and rollback

Use monotonically increasing Debian versions and let APT/dpkg own replacement of package-managed files. Keep at least the current and one known-good previous package version in the signed repository. Upgrade with APT; roll back explicitly by installing an exact retained version, then pin/hold it only for the recovery interval. Configuration migrations must be forward-compatible or preserve a versioned backup because package downgrade does not inherently reverse mutable data.

APT's security boundary is the signed repository metadata and package hashes, and APT refuses a repository that unexpectedly loses authenticated status ([apt-secure](https://manpages.debian.org/testing/apt/apt-secure.8.en.html)). Never instruct operators to use `--allow-unauthenticated` or `allow-downgrade-to-insecure`. Test interrupted installation, failed maintainer scripts, exact-version downgrade, association preservation, and configuration migration reversal.

## Browser discovery and authentication profile

Opening an `https:` URL invokes the user's configured default browser on Windows ([Windows default apps platform](https://learn.microsoft.com/en-us/windows/apps/develop/windows-integration/default-apps-platform)); the corresponding Linux desktop mechanism is also suitable for the final return-to-CIPP URL. That does **not** make an arbitrary default browser usable for the acceptance automation.

The acceptance flow needs a browser process launched with a dedicated temporary profile and a private local DevTools endpoint. Chrome changed its behavior in version 136: `--remote-debugging-port` and `--remote-debugging-pipe` are ignored for the default Chrome data directory unless `--user-data-dir` points to a non-standard directory; Google recommends the custom directory to isolate debugging from real profiles ([Chrome remote-debugging change](https://developer.chrome.com/blog/remote-debugging-port)). This supports the agreed ephemeral-session design and rules out attaching to a normal remembered browser profile.

Therefore browser selection must:

1. determine whether the OS default for HTTP(S) maps to a supported Chrome, Chromium, or Edge executable;
2. if supported, prefer that executable; otherwise discover supported vendor locations/package commands in deterministic order;
3. display the selected browser before launch and allow the operator to choose another discovered supported browser;
4. launch it directly with a newly created, permission-restricted `--user-data-dir` and loopback-only, dynamically allocated debugging port;
5. wait for readiness, complete the run, terminate only the process tree it created, and recursively remove that profile after closing handles; and
6. fail closed with prerequisite instructions when only Firefox or no supported Chromium executable is available.

Do not copy cookies from or attach DevTools to the normal profile. Do not infer an executable by parsing a shell command and then reusing that command verbatim. On managed Edge installations, policy can override `--user-data-dir`, so startup must verify that the actual DevTools endpoint/profile is the one created for this run and abort if policy defeats isolation ([Edge UserDataDir policy](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/userdatadir)).

Use the OS default-browser mechanism only after acceptance to open the trusted, installer-configured CIPP return URL. No browser automation is needed for that handoff.

## Production release gates derived from these constraints

- Build reproducibly from a tagged commit; publish immutable hashes and an SBOM alongside both packages.
- Verify Authenticode signatures/timestamps on MSI and Windows binaries, and verify APT repository signature plus package hashes on a clean Kubuntu machine.
- Test fresh install, upgrade, interrupted upgrade, uninstall, and explicit rollback on clean Windows 11 and Kubuntu 26.04 systems.
- Verify protocol activation from every supported CIPP browser, including hostile/oversized URI cases and quote/metacharacter payloads.
- Verify handler ownership in the real non-admin user session after installation and after upgrade/rollback.
- Verify terminal fallback on Windows without a usable `wt.exe`, and `Terminal=true` behavior under Kubuntu's configured terminal.
- Verify PowerShell minimum/in-support version detection without trusting `PATH` alone.
- Verify Chrome, Chromium, and Edge discovery; Firefox-only failure; Chrome 136+ temporary-profile behavior; managed-browser policy conflicts; and complete temporary-profile deletion.
- Retain one signed known-good MSI and Debian version plus documented recovery commands before promoting a release.

## Blockers and uncertainties

1. **Kubuntu 26.04 validation cannot be replaced by Ubuntu documentation.** Microsoft documents Ubuntu 26.04 PowerShell support, while freedesktop specifies the desktop contract. A release VM must still prove Plasma's URI association and `Terminal=true` behavior.
2. **The final browser-control mechanism determines browser constraints.** These conclusions assume the existing DevTools-based acceptance approach. If the companion moves to a supported OAuth/native API contract, direct Chromium discovery may no longer be necessary.
3. **Signing identities and infrastructure are not selected.** Production needs a Windows code-signing certificate/service and a separately governed APT repository signing key, with rotation and revocation procedures.
4. **Per-machine versus per-user MSI is now a product decision.** This research recommends per-machine for Intune and consistent upgrades; if non-admin self-service installation is mandatory, a second per-user package/upgrade path must be designed and tested because MSI cannot major-upgrade across contexts.
