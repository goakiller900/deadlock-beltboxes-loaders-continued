# Automatic releases

The workflow in `.github/workflows/build-release.yml` builds and validates a Factorio-ready release archive on every pull request.

## Required repository secret

Add a GitHub Actions repository secret named:

```text
FACTORIO_API_KEY
```

Use a Factorio API key belonging to an account that can publish `deadlock-beltboxes-loaders-continued` on the Factorio Mod Portal.

Repository secrets are configured under:

**Settings → Secrets and variables → Actions → Repository secrets**

The same Factorio API key may be reused across repositories owned by the same Factorio account, but it must be added separately to each GitHub repository unless an organization-level secret is used.

## Publishing behavior

For every successful push to `main`, the workflow:

1. Reads the mod name and version from `info.json`.
2. Creates a deterministic archive named `<name>_<version>.zip`.
3. Ensures the ZIP contains exactly one correctly named top-level folder.
4. Creates or reuses an immutable GitHub Release named `v<version>`.
5. Checks whether the version already exists on the Factorio Mod Portal.
6. Uploads the ZIP when the portal version is missing.
7. Skips the upload safely when that version is already present.

The workflow can also be started manually from:

**Actions → Build and release Factorio mod → Run workflow**

## Releasing a new version

Before merging changed mod contents to `main`:

1. Increase `version` in `info.json`.
2. Add the matching entry to `changelog.txt`.
3. Test the mod in the target Factorio version.
4. Merge the changes to `main`.

Published GitHub and Mod Portal versions are treated as immutable. Do not reuse an existing version number for changed mod contents.
