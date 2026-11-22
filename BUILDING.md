# Building release versions

The game is exported for five targets, the presets in `export_presets.cfg`:

| Platform    | Preset            | Output                                     |
|-------------|-------------------|--------------------------------------------|
| macOS       | `macOS`           | universal `.app` (Apple Silicon and Intel) |
| Windows     | `Windows Desktop` | x86_64 `.exe` + `.pck`                     |
| Linux       | `Linux`           | x86_64 binary + `.pck`                     |
| Linux ARM64 | `Linux ARM64`     | arm64 binary + `.pck`                      |
| Android     | `Android`         | arm64 `.apk` (landscape, touch controls)   |

## Requirements

- Godot **4.5.1 stable** (the editor's version; `Godot --version`) and its
  export templates: Godot editor > Editor > Manage Export Templates >
  Download and Install. They go to `~/Library/Application Support/Godot/export_templates/4.5.1.stable/`
  (macOS), `~/.local/share/godot/export_templates/` (Linux) or
  `%APPDATA%\Godot\export_templates\` (Windows). One download covers every platform.
- For the native library (`native/`, C++ GDExtension): CMake 3.17+, a C++17
  compiler (Xcode command line tools, GCC/Clang, or Visual Studio) and Python 3.
  godot-cpp is the `native/godot-cpp` submodule (`godot-4.5-stable`):
  `git submodule update --init`.
- For the Windows and Linux native libraries on any host (macOS included):
  [Docker](https://www.docker.com/products/docker-desktop/) running
  (Docker Desktop on macOS/Windows). See [Native libraries in Docker](#native-libraries-in-docker).

- For Android: a JDK 17, the Android SDK and, for the native library, the
  Android NDK. See [Android](#android).

## Local build

```sh
tools/build.sh                 # every platform whose templates are installed
tools/build.sh macos           # only some: macos, windows, linux, linux-arm64, android
tools/build.sh --debug         # debug builds
tools/build.sh --native        # rebuild the native library for this OS first
tools/build.sh --docker        # rebuild the Windows/Linux native libraries in Docker first
tools/build.sh --no-docker     # never use Docker
tools/build.sh --native-only   # only the native libraries (add --docker for Windows/Linux), no export
tools/build.sh --no-zip        # leave the folders unzipped
```

With Docker running, `tools/build.sh all` makes the four desktop builds with
their native libraries (and Android's, with its tools installed). It builds the native library for the current OS when it is
missing (its own compiler, `native/build` folder), the missing Windows and
Linux ones in Docker, imports the project, exports each preset and zips it.
Outputs (the `build/` folder is not in git):

```
build/<platform>/Voxel Engine Godot Edition/                    the game folder
build/<platform>/Voxel Engine Godot Edition <version>-<platform>.zip
build/export-<platform>.log                                       Godot's export log
```

A platform whose library is missing in `bin/` (Docker not running, say) is
still exported, without it: the game then uses the slower GDScript code
(the build says so). The macOS library needs a Mac (Xcode command line tools).

`bin/voxel_native.gdextension` lists them:
`bin/libvoxel_native.framework` (macOS, universal),
`bin/voxel_native.windows.x86_64.dll`, `bin/libvoxel_native.linux.x86_64.so`,
`bin/libvoxel_native.linux.arm64.so`, `bin/libvoxel_native.android.arm64.so`.

## Android

The game on a phone is the same game with the Phone control mode (Options >
Controls > Control Mode, the default on Android): touch controls and larger
windows. On a PC the same mode works with the mouse as a finger.

Install once (none of it is needed for the desktop builds):

1. **JDK 17** - for example `brew install --cask temurin@17` (macOS), or
   Android Studio's own (`JAVA_HOME` pointing at it).
2. **Android SDK** - Android Studio installs it into `~/Library/Android/sdk`
   (macOS), `~/Android/Sdk` (Linux) or `%LOCALAPPDATA%\Android\Sdk` (Windows).
   Without Android Studio, with the command line tools:

   ```sh
   sdkmanager --sdk_root="$HOME/Library/Android/sdk" \
     "platform-tools" "build-tools;35.0.0" "platforms;android-35" "ndk;28.1.13356709"
   ```

   (the versions Godot 4.5 names; the NDK is only for the native library).
3. The export templates (the same download as for the desktop builds).

`tools/build.sh` finds the SDK in `$ANDROID_HOME` / `$ANDROID_SDK_ROOT` or
the default folders above, the NDK in `$ANDROID_NDK_ROOT` / `$ANDROID_NDK_HOME`
or the newest in the SDK's `ndk/` folder, the JDK in `$JAVA_HOME` or the
system's, and passes them to Godot. Once the editor has saved its own
Editor Settings > Export > Android > Java SDK Path (even empty), that setting
wins: set it there to the JDK (`/usr/libexec/java_home` prints it on macOS);
the build says so when it is missing.

```sh
tools/build.sh --native-only android   # only bin/libvoxel_native.android.arm64.so
tools/build.sh android                 # the library when missing, then the .apk
```

- The library is built with the NDK's CMake toolchain (arm64-v8a, Android 7.0
  and later, the C++ library linked statically) in `native/build-android/`.
  Without the NDK the `.apk` is still made, with the slower GDScript code.
- Output: `build/android/Voxel Engine Godot Edition <version>-android.apk`.
- A release `.apk` must be signed with your own key: set
  `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`, `GODOT_ANDROID_KEYSTORE_RELEASE_USER`
  and `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`. Without them the build makes
  a debug-signed `.apk` (Godot's debug keystore), good for testing:
  `adb install -r "build/android/Voxel Engine Godot Edition <version>-android.apk"`.
- With no JDK or SDK, `tools/build.sh` (everything) skips Android and says
  so; `tools/build.sh android` then fails.

## Native libraries in Docker

`native/docker/Dockerfile` is an Ubuntu 20.04 image (glibc 2.31, so the Linux
libraries run on distributions from 2020 on) with CMake, Ninja, Python 3,
g++ for the host's arch, the cross g++ for the other Linux arch and
MinGW-w64 (posix threads) for Windows. It works on Apple Silicon and x86_64
hosts alike, natively (no emulation).

```sh
tools/build.sh --native-only --docker                  # all three
tools/build.sh --native-only --docker windows linux    # only some
```

- The first run builds the image: it downloads about 350 MB (Ubuntu and
  the compilers) and takes a few minutes; later runs reuse Docker's cache.
  `docker image rm voxel-native-build` frees the space (~1.5 GB).
- Each target has its own build folder, `native/build-docker-<platform>/`
  (not in git), so a rebuild compiles only what changed; the first compiles
  godot-cpp, several minutes per target.
- The container runs as your user, so the files it writes in the repository
  are yours. Toolchains: `native/docker/toolchain-*.cmake`.
- Release builds with libgcc and libstdc++ linked statically (and winpthread
  on Windows): the `.dll` needs only Windows' own DLLs, the `.so` only glibc.
- Outputs: `bin/voxel_native.windows.x86_64.dll`,
  `bin/libvoxel_native.linux.x86_64.so`, `bin/libvoxel_native.linux.arm64.so`.

## What is in each zip

```
Voxel Engine Godot Edition/
  Voxel Engine Godot Edition(.app|.exe|.x86_64|.arm64)   (+ .pck, + the native library on Windows/Linux)
  CHANGELOG.md, SERVER.md
  start-server.*, server.properties.example                the dedicated server
```

`CHANGELOG.md` and `SERVER.md` are also inside the game's pack (the Help &
News screen reads the changelog). Godot cannot place loose files next to the
executable, so `tools/build.sh` copies the server files from `tools/server/`
after the export: `start-server.command` and `start-server.sh` for macOS,
`start-server.bat` for Windows, `start-server.sh` for Linux, and
`server.properties.example` for all. A file missing there is reported and
skipped.

## Notes

- macOS builds are signed ad-hoc and not notarized: on another Mac, the first
  start needs right-click > Open (or `xattr -dr com.apple.quarantine "Voxel Engine Godot Edition.app"`).
  Signing and notarization are set in the `macOS` preset (codesign/notarization).
- Windows builds are unsigned: SmartScreen asks once (More info > Run anyway).
