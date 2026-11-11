# Recover the locked private source

The public repository contains independent Godot code, import tools and a source
hash ledger. It does **not** contain the licensed StackCraft source or generated
content. A cloud reset can therefore require a fresh private source import.
Keep a legally obtained ZIP in storage you control; this tool does not create a
durable backup or upload anything.

## Recommended: an existing ZIP, with no network access

Use Python 3.10+ and Git. From the project root:

```sh
python3 tools/fetch_stackcraft_source.py \
  --archive /private/path/CardLoop-source.zip \
  --output source/StackCraft \
  --acknowledge-license
python3 tools/check_source_lock.py source/StackCraft
```

The archive must contain `Assets/StackCraft`, either at its root or inside one
top-level directory, as GitHub repository ZIPs normally do. Other repository
files are inspected for unsafe archive entries but are not extracted. A ZIP of
only the subtree is supported when it preserves the `Assets/StackCraft/` prefix.
The tool always uses the checked-in `docs/source-lock.json`, and accepts only the
fixed source repository `zhuanggenhua/CardLoop`, commit
`a11a89b04cea8370476f2559b639bb9b4cbc08d8`. Changing the archive filename or its
wrapper directory does not prove provenance: all 1,327 file paths, lengths and
SHA-256 digests must match the trusted lock.

`--archive` never downloads anything. With neither `--archive` nor `--download`,
the tool exits with usage help instead of implicitly using the network.
`--acknowledge-license` acknowledges entitlement to use the supplied copy
privately. It is not a purchase, license grant or redistribution clearance.
GitHub's public repository status is not evidence of such clearance.

The default destination is the ignored `source/StackCraft` directory. A custom
destination inside **any** Git repository must be ignored and contain no tracked
files. A destination outside Git is also permitted; keep it private. Nothing is
force-added, committed or uploaded. Do not share the source ZIP, extracted
originals or generated data/assets without separate redistribution permission.

## Optional: explicitly request the official archive

```sh
python3 tools/fetch_stackcraft_source.py \
  --download --output source/StackCraft --acknowledge-license
```

This makes an unauthenticated HTTPS request only to the fixed GitHub API ZIP
archive endpoint for the locked commit. Redirects are restricted to the exact
locked repository/commit ZIP paths on GitHub's official `codeload.github.com`
host. It has no configurable URL, credentials, token discovery, authentication
flow, retry loop, mirror fallback or TLS bypass. It respects the environment's
network restrictions. HTTP authentication/rate-limit/access errors stop the
download; an authorized ZIP supplied with `--archive` is the independent offline
option, not an automatic workaround for a denied action.

**Network validation limit:** GitHub's repository API was checked and exposes
the official archive endpoint template. A complete live archive download has
not been exercised in this cloud environment, whose shell network allowlist
does not include GitHub. The optional transport and redirect rules have
synthetic tests, not a claim of verified live connectivity. No large repository
archive was downloaded just to test the transport.

## Verification and fail-closed behavior

- Every selected file is decompressed into a private temporary staging directory
  and checked against the lock before the destination is changed.
- Existing matching files are preserved. A partial matching destination can be
  completed. A mismatched, unexpected, symlink or special destination file
  refuses recovery; the tool never deletes or overwrites it.
- Archive traversal, absolute paths, backslashes, control characters, portable
  filename hazards, duplicate/case-colliding names, file/directory collisions,
  symlinks, special files, encrypted entries and unsupported compression are
  refused, including in unselected parts of the archive.
- ZIP budgets are 512 MiB compressed, 16 MiB central directory, 30,000 members,
  256 MiB per member, 2 GiB declared total uncompressed, and a maximum 1,000:1
  member expansion ratio. Selected files additionally have exact locked size
  limits while streaming. Ordinary stored/deflated single-volume ZIPs are
  supported; split archives and ZIP64 end records are refused. Legitimate
  archives exceeding these conservative limits fail rather than relaxing them.
- The optional download has a 30-second socket timeout and a checked 300-second
  streaming budget. Temporary downloads and staging are removed on normal
  success/failure. An abruptly killed process can leave private temporary files.
- Final verification checks every destination file again. Use a private,
  exclusively controlled destination during recovery. Do not run concurrent
  writers against it. An I/O interruption while completing an existing partial
  directory can leave additional verified files; rerunning completes it safely.

Archives are data only. Neither original scripts nor Unity are executed.
Successful recovery does not run importers, launch Godot, update game data or
establish gameplay, visual or audio parity.

## Continue the private migration

Only after recovery succeeds:

```sh
python3 tools/import_stackcraft.py --source source/StackCraft --output data
python3 tools/verify_source.py --data data --source source/StackCraft
python3 tools/import_visual_assets.py --source source/StackCraft --acknowledge-license
```

Use the normal strict import, without `--allow-missing-visual-assets`. Generated
`data/` and `assets/imported/` remain ignored. The full locked source yields
150 PNG, 19 WAV and 4 FBX assets, including the original music. See
[data import](data-import.md), [visual import](visual-import.md) and
[audio import](audio-import.md) for their separate validation limits.

## Source-free tests

```sh
python3 -m unittest discover -s tests -p 'test_fetch_stackcraft_source.py' -v
```

Tests create synthetic ZIPs and hashes; no original source, art, audio, passwords
or tokens are embedded. They cover exact/idempotent/partial recovery, existing
file preservation, hash and size failures, missing/extra entries, path/link
attacks, resource budgets, malformed ZIPs, ignored-destination enforcement,
license/source arguments, offline behavior and mocked transport restrictions.

A separate local-only roundtrip was also verified on 2026-11-11: the existing
hash-verified private source was packaged into a temporary 31,869,481-byte ZIP,
recovered to a separate temporary destination, and checked with
`check_source_lock.py`. All 1,327 files matched; a second recovery restored zero
files and preserved the existing matching copy. The temporary ZIP and copy were
removed afterward. This exercises real locked file sizes/content but does not
validate live GitHub archive transport or future availability.
