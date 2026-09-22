# Release archive

On 2026-09-22 this project deleted 40 GitHub Releases and 36 git tags, and corrected the
`docker pull` line in two more releases. This directory is the record of what was removed,
because a deleted GitHub Release is not recoverable from GitHub.

## Why they were deleted

Until [#50](https://github.com/magicalyak/transmissionvpn/pull/50), the `create-release` job
ran `release-drafter` with `publish: true`, and `.github/release-drafter.yml` set both
`name-template` and `tag-template` to `v$NEXT_PATCH_VERSION`. The drafter therefore ignored
the tag that was actually pushed and invented a version by incrementing the previous
release's name. Pushing `v4.1.2-r9` published a release called `v4.1.16` and created that as
a second git tag on the same commit.

Those invented versions never matched an image. Every image tag is matched out of
`v(\d+\.\d+\.\d+-r\d+)` in the `prepare` job, so only the `-rN` form is ever published. The
result was two-sided:

- Every release from `v4.1.3` to `v4.1.16`, and `v4.0.11` to `v4.0.25` before it, advertised
  a `docker pull` command that returned a 404.
- Because the drafter consumed each tag push and published its own invention instead, no
  `-rN` tag ever received a release. Not one version this project actually shipped had a
  release of its own until `v4.1.2-r9` was published by hand on 2026-09-22.

Each deletion was verified first: the version had no image on Docker Hub, and the git tag
pointed at a commit reachable from `main`, so no history was orphaned.

## What is here

| Path | Contents |
| --- | --- |
| `deleted/<tag>.md` | One file per deleted release: its name, publish date, creator, the git tag SHA it pointed at, and its full original body. 40 files. |
| `deleted-tags.txt` | `<commit-sha> <ref>` for each of the 36 deleted git tags. |
| `edited/<tag>.md` | The two releases that were kept but corrected, as they read before the edit. |

## Restoring

A git tag comes back with the SHA recorded in `deleted-tags.txt`:

```sh
git push origin <sha>:refs/tags/<tag>
```

A release body is the text under `## Original release body` in its `deleted/<tag>.md`:

```sh
gh release create <tag> --title "<name>" --notes-file <body-file> --verify-tag
```

Recreating a release does not make its image exist. These versions were never built, which
is why they were deleted; restore one only to recover the text, not to republish it.

## What was deliberately kept

- **`4.0.6-r5`** advertises an image that was never built, so it met the deletion criteria,
  but its body is human-written and is the only surviving record of why the `v4.0.7`+ tags
  were removed back in 2025. It was corrected rather than deleted.
- **`v0.1.7`'s git tag** was the only ref holding commit `771e4078`; no branch contains it,
  and Docker Hub has an image `sha-771e407` built from it. The release was deleted and the
  tag deliberately left in place, so the commit stays reachable.
- **`v4.0.8`, `v4.0.9` and `v4.0.10`** had releases but no git tags. Those tags were already
  removed by the 2025 cleanup that `4.0.6-r5` documents, so only the releases were deleted.

## Preventing a recurrence

`create-release` now builds the release from `${{ github.ref_name }}` and the pushed tag's
own annotation, and passes `--verify-tag` so `gh` refuses to create a release for a tag that
does not already exist. The job cannot invent a version.
