# Original webhook body capture

Craft 10.9.1 targets .NET 8. Its request marshaler gives PowerShell a parsed JSON
object, not original request bytes. This module uses the documented ASP.NET Core
[hosting-startup mechanism](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/host/platform-specific-configuration?view=aspnetcore-8.0)
to install a filter before Craft's pipeline, without changing `Craft.dll` or adding
a proxy, port, external service, credential, or database.

The custom image contains this assembly and its dependency manifest. The image
sets `ASPNETCORE_HOSTINGSTARTUPASSEMBLIES=Cipp.Gdap.Hosting` and
`DOTNET_ADDITIONAL_DEPS=/app/Cipp.Gdap.Hosting.deps.json`. Preserve these settings;
overrides that prevent loading cause readiness to fail. Once GDAP Acceptor is
enabled, a missing extension rejects Partner Center callbacks rather than falling
back to unsigned processing. Disabling the entire feature explicitly preserves
the original CIPP webhook behavior, which is not signature-authenticated here.

## Interface and invariants

- `Installed` reports that the startup filter has joined the current pipeline.
- `Take(handle)` transfers the original byte array to PowerShell exactly once.
  Unknown, reused and expired handles yield no body. Handles are generated from
  32 random bytes; every incoming handle header is removed before processing.
- Captured buffers stay inside the process. The header contains only an opaque
  handle, never a body, signature, cookie or bearer token. It is not proof of
  Microsoft identity: the PowerShell adapter must still validate certificate and
  signature. It must never accept arbitrary raw headers or serialize parsed JSON.
- Enabled Partner Center callbacks must be POST, uncompressed, nonempty, and at
  most 1 MiB. At most 32 captures run concurrently; excess receives 503. This bound
  also applies when Content-Length is absent. Reading the body is limited to 15
  seconds. Bodies are held in memory, not disk.
- Buffers and handles are removed in `finally`, including downstream failures.
  Unrelated requests keep their original streams and behavior.

Readiness additionally requires a matching **signed** test-event receipt, not just
Partner Center's successful delivery report. The receipt uses the documented
validation-event ResourceUri; unknown shapes fail closed pending live evidence.

## Verification

```sh
dotnet run --project backend/hosting-tests
docker build -f backend/Dockerfile.host-contract -t gdap-host-contract .
docker run --rm gdap-host-contract
pwsh -File backend/Test-HostStartup.ps1 -Image <locally-built-custom-image>
```

The HTTP contract test uses the unchanged Craft marshaller and PowerShell from the
pinned image. It verifies a synthetic RSA signature over whitespace and Unicode,
rejects tampering, and prevents client handles from selecting another body. The
startup smoke test runs the actual Craft entrypoint network-isolated and confirms
the filter is installed before routing. Neither test claims Microsoft PKI trust,
Partner Center delivery, or customer onboarding was exercised. Those need a lab.

No test endpoint or test certificate is shipped in the production image.
