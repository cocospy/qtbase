# Native HarmonyOS build of Qt on GitHub Actions

Build Qt for OpenHarmony **natively** on a free GitHub runner, inside an
OpenHarmony container. No device, no virtual machine, no paid runner.

This is not a cross build. The compiler itself is an OpenHarmony binary, and
so are the build-time tools Qt runs during the build. That is the code path a
real device takes, and nothing else in Qt CI covers it.

## What it produces

One run builds three modules and uploads the result.

| Module | Targets | Time |
|---|---|---|
| qtbase | 1748 | 12m28s |
| qtshadertools | — | 1m19s |
| qtdeclarative | 3881 | 20m09s |
| | **whole job** | **36m18s** |

Measured on run 3. An earlier run on a different `dev` took 41m05s, so expect
36 to 41 minutes.

The artifact `qt-ohos-arm64-<sha>` is 64 MB packed, 277 MB installed. It holds
43 shared libraries and 53 entries in `bin` and `libexec`, all OpenHarmony
arm64 except a few helper scripts, including
`libQt6HarmonyExtras`, `harmonydeployqt` and `harmonyostestrunner`.

Measured on `ubuntu-24.04-arm`: 4 vCPU, 15 GiB RAM, 145 GB disk, 37 GB peak.

## Quick start

### 1. Fork qtbase

Fork `qt/qtbase` on GitHub. Keep the fork **public**. Copying only the default
branch is enough.

Public matters: `ubuntu-24.04-arm` is free and unlimited on public
repositories, and **does not work at all on private ones**. The workflow fails
there, and no amount of paid quota changes that.

### 2. Push the branch

Copy `.github/ohos/` and `.github/workflows/ohos-native.yml` onto a branch
named exactly `ohos-native-ci`, then push it to your fork.

```bash
git checkout -b ohos-native-ci
git add .github
git commit -m "CI: Add a native HarmonyOS build workflow"
git push -u fork ohos-native-ci
```

The workflow triggers on pushes to that branch name. Rename the branch and
nothing runs.

### 3. Enable Actions

Open the **Actions** tab in your fork and click *"I understand my workflows,
go ahead and enable them"*. GitHub disables workflows on new forks, so the
push alone starts nothing until you do this.

That is all. The run starts by itself.

## What the run does

**Job 1, `toolchain image`** — 6m17s the first time. Later runs reuse the
registry cache and finish in about 25 seconds unless the Dockerfile changes.

It builds the container and pushes it to
`ghcr.io/<your-name>/ohos-qt-builder`. See [the image](#the-image) below.

**Job 2, `qtbase`** — 36 to 41 minutes.

1. Frees disk by deleting dotnet, android and ghc
2. Pulls the image
3. Reports the kernel, disk, CPU, and whether `/dev/kvm` exists
4. Runs the `file(GLOB)` probe (see [Troubleshooting](#troubleshooting))
5. Configures and builds qtbase
6. Installs it, then builds and installs qtshadertools and qtdeclarative into
   the same prefix
7. Packs the prefix and uploads it
8. On failure only: runs `qvkgen` under `lldb` and prints the CMake logs

The image carries the toolchain only. Qt is built outside it, in a
bind-mounted tree, so the build stays on the runner's disk and the image stays
small.

## The image

Base is `hqzing/dockerharmony`, an OpenHarmony userland: musl, toybox, mksh.
The Dockerfile adds, in order:

1. **zsh, ncurses and pcre2 bottles, unpacked by hand.** Harmonybrew's `brew`
   begins with `#!/usr/bin/zsh`, but the rootfs ships only mksh. This breaks
   the bootstrap cycle.
2. **Harmonybrew**, then `cmake ninja python git pkgconf ohos-sdk-native`.
3. **`llvm-ar` and `llvm-ranlib` from the SDK.** The rootfs has no `ar`,
   `ranlib` or `strip` at all.
4. **Qt's third-party packages**, static, into the SDK sysroot. Even used
   natively the SDK clang searches only its own sysroot, never `/usr`.
5. **`CC` and `CXX` pointed at the SDK clang.** This is what makes the build
   native: no toolchain file, no `CMAKE_SYSTEM_NAME`.
6. **OpenHarmony platform libraries.** See below.
7. **`LD_LIBRARY_PATH`** set to Harmonybrew's lib directory.

Toolchain in the image: cmake 4.4.3, Ninja 1.13.2, Python 3.14.7, clang 15.0.4.

### Why the platform libraries need work

dockerharmony is a userland, not a system image. It ships no OpenHarmony
platform libraries, so `libQt6Core.so` cannot be loaded and every build-time
tool that links it dies with exit code 127.

The rule that works:

- **Copy the real library** where its dependency closure is shallow: 11 files,
  680 KB, the closure of `libdeviceinfo_ndk`, `libtime_service_ndk` and
  `libhilog_ndk`.
- **Generate a no-op stub** for every other link-time stub the SDK declares.
  `gen-shims.py` produced 130 and skipped 5 that already had a real
  implementation.

Chasing libraries one at a time does not end. QtCore needs six; QtGui adds
EGL, GLES and libpixelmap; the closure of `libEGL` and `libGLESv3` alone is 58
libraries and 11 MB, reaching IPC, samgr and the account services.

Two deliberate choices in `gen-shims.py`:

- **Stubs return an error, not success.** A fake success would hand the caller
  uninitialised out-parameters.
- **`OHOS_SHIM_TRACE=1` names any stub that is called.** The build sets it.

In a full run of all three modules, **not one stub was ever called**. For
these modules the stubs exist only to satisfy the dynamic loader.

## The two flags passed by hand

The configure line carries two workarounds. Both belong upstream.

```
-DOHOS=ON
-DCMAKE_C_FLAGS=-DOHOS_PLATFORM=OHOS
-DCMAKE_CXX_FLAGS=-DOHOS_PLATFORM=OHOS
```

**`-DOHOS=ON`.** `QtAutoDetectHelpers.cmake` enables OHOS by itself only when
`CMAKE_HOST_SYSTEM_NAME` is `HarmonyOS`. That works on a device, which runs
the HongMeng kernel and answers `uname -s` with `HarmonyOS`. It cannot work in
a container: `uname` is answered by the Linux host kernel, and CMake reads it
through `uname(2)` in its own C++ before `CMakeDetermineSystem.cmake` runs, so
a `uname` shim on `PATH` has no effect.

Consequence worth knowing: **container CI never exercises the auto-detect path
that every real device takes.** `ohos-probe.yml` measures this; see
[The probe](#the-probe).

**`-DOHOS_PLATFORM=OHOS`.** `QtMkspecHelpers.cmake` tests `LINUX` before
`OHOS`, and `LINUX` is set on HarmonyOS, so the `OHOS` arm is unreachable even
with `OHOS` explicitly on. Without the define, the SDK's `EGL/eglplatform.h`
falls through to the generic `__unix__` branch and `qohosegl.h` fails to
compile. Tracked as **QTBUG-150691**.

Note this define fixes the header only, **not** the mkspec. The build still
uses `linux-clang` instead of `ohos-clang`, so Qt is compiled against the
wrong `qplatformdefs.h`. The build is green; it is not yet the correct native
build.

## The probe

`ohos-probe.yml` answers one question: can Qt's native auto-detect ever fire?
It runs in about 90 seconds because it reuses the image the build pushed.

It runs `hostprobe.cmake` in the container and also configures qtbase *without*
`-DOHOS=ON` to see whether Qt turns OHOS on by itself.

Trigger it by pushing a branch named `ohos-probe`. It uses a branch trigger
because GitHub offers the **Run workflow** button only for workflows that
exist on the repository's default branch.

`hostprobe.cmake` is a plain script with no dependencies, so the same file can
be run on a real device to compare:

```bash
cmake -P .github/ohos/hostprobe.cmake
```

Measured results so far:

| Environment | Kernel | `uname -s` | Auto-detect |
|---|---|---|---|
| HarmonyOS device | HongMeng | `HarmonyOS` | fires |
| Container on a GitHub runner | Linux | `Linux` | cannot fire |

## Running it locally

You do **not** need a Linux desktop. You need an **arm64 CPU**, because a
container shares the host CPU and these are `aarch64-linux-ohos` binaries. An
Apple Silicon Mac works through Docker Desktop's Linux VM. An x86_64 Linux
desktop does not, short of slow emulation.

```bash
docker build -t ohos-qt-builder .github/ohos

docker run --rm --user "$(id -u):$(id -g)" \
  -e HOME=/build/home -e TMPDIR=/build/tmp \
  -v "$PWD:/src:ro" -v /var/tmp/qtbase-ohos-build:/build \
  ohos-qt-builder cmake -S /src -B /build -G Ninja -DOHOS=ON
```

Allow at least 50 GB of free disk. On a Mac, move Docker Desktop's disk image
to a volume with room: **Settings → Resources → Advanced → Disk image
location**.

Run the glob probe first; see below.

## Troubleshooting

**"The CXX compiler identification is unknown", early in configure.**

The host kernel is missing `CONFIG_ANON_VMA_NAME`. OpenHarmony musl names its
heap regions with `prctl(PR_SET_VMA)`; without that kernel option the call
fails and leaves `errno` set, kwsys checks `errno` after a readdir loop that
allocates, and `file(GLOB)` silently returns nothing for any directory over
about 48 entries.

Check it before anything else:

```bash
cmake -DWORKDIR=/tmp/globtest -P .github/ohos/globtest.cmake
```

The workflow runs this automatically. Hosted arm64 runners have the option, so
CI is unaffected. Inside Docker Desktop's VM there is no `/boot/config-*`, so
the probe is the only way to check there.

**An old "Smoke build" workflow fails on every push.**

`qtbase/dev` contains `.github/workflows/ninja-build.yml`, last touched in
2021. Its trigger is a bare `on: push` and its runner images were retired, so
it fails at once. Disable it: **Actions → Smoke build → ⋯ → Disable
workflow**.

**`libpcre2-16.so.0` not found after install.**

Qt links some third-party libraries from Harmonybrew, pcre2 among them,
because the additional-packages archive ships none. Brew's lib directory is on
no default search path. During the build, CMake's RPATH covers it; installing
replaces that RPATH. Set `LD_LIBRARY_PATH`.

Editing `/etc/ld-musl-aarch64.path` does **not** help: OpenHarmony musl
resolves through the namespace config in
`/etc/ld-musl-namespace-aarch64.ini`, and the path file is inert.

**Can I run Qt tests in the container?**

No. That needs a booted OpenHarmony system, which needs QEMU with KVM, and
hosted arm64 runners have no `/dev/kvm`. The container is a build environment
only.

## Files

| File | Purpose |
|---|---|
| `ohos/Dockerfile` | The toolchain image |
| `ohos/gen-shims.py` | Generates no-op OpenHarmony libraries from the SDK's own stubs |
| `ohos/globtest.cmake` | Probes the `CONFIG_ANON_VMA_NAME` kernel trap |
| `ohos/hostprobe.cmake` | Prints what CMake reports about the host |
| `workflows/ohos-native.yml` | The build |
| `workflows/ohos-probe.yml` | The auto-detect measurement |

## Related tickets

- QTBUG-150573 — investigate using a Docker environment to build Qt in GitHub Actions
- QTBUG-150205 — support native HarmonyOS builds on device
- QTBUG-150323 — `qvkgen` abort in native builds. Fixed; merged to `dev`
- QTBUG-150691 — `OHOS` branch in `QtMkspecHelpers` unreachable because `LINUX` is set

## Credits

The container, the shim approach and the original workflow are Joerg
Bornemann's work on the `ohos-native-ci` branch of `jobor/qtbase`.
