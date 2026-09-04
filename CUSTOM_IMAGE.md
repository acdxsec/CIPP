# Custom CIPP image

This fork builds a thin derivative of the official CIPP NG image. It replaces
only the compiled frontend under `/app/Frontend`; the official Craft runtime
and CIPP API remain unchanged.

The custom frontend adds an **Accept and onboard** action to each GDAP invite.
It launches `m365internals-gdap://accept/<relationship-id>`, which requires the
M365Internals GDAP protocol handler to be installed on the technician's device.

## Publish

Run the **Build custom CIPP image** workflow or push a relevant change to
`main`. Images are published as:

```text
ghcr.io/acdxsec/cipp-custom:<cipp-version>-<workflow-run-number>
ghcr.io/acdxsec/cipp-custom:edge
```

Use the immutable versioned tag in Azure App Service. The package must either
be public or Azure must be configured with GHCR credentials.

## Upgrade

When updating from upstream CIPP:

1. Merge the new upstream release.
2. Confirm `public/version.json` matches the intended official base image.
3. Pull that official image and resolve its linux/amd64 digest.
4. Update the final `FROM` digest in `Dockerfile.custom`.
5. Build and test before updating the versioned tag in Azure.

Do not point production at `edge`; retain the previous versioned tag for
rollback.
