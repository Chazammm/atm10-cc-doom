# Agartha V2 media

The V2 binaries are hosted as **GitHub Release assets**, not committed into the repository. This keeps ~0.5 GB of generated binary video out of Git history.

Release tag:

`agartha-v2`

Expected assets:

`agartha-v2-part01.32vid` through `agartha-v2-part50.32vid`.

## Automatic Windows upload

Put all ten downloaded ZIP packs in **Downloads**, **Desktop**, or one folder, then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\upload-v2.ps1
```

The script:
- installs GitHub CLI with winget when needed;
- asks for a one-time GitHub browser login when needed;
- finds and extracts all ten ZIPs;
- verifies all 50 files;
- creates the `agartha-v2` release if necessary;
- uploads all assets automatically;
- supports safe reruns with `--clobber`.

You may also specify a source folder:

```powershell
.\upload-v2.ps1 -Source "C:\Users\you\Downloads"
```

After upload:

```
wget run https://raw.githubusercontent.com/Chazammm/atm10-cc-doom/main/youtube-video/install.lua
agartha-v2
```
