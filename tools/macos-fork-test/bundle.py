#!/usr/bin/env python3
# SPDX-FileCopyrightText: (C) 2026 lxf82dev <lxf82dev@gmail.com>
# SPDX-License-Identifier: GPL-2.0-only WITH LicenseRef-OpenSSL-Exception

"""Package a local, non-bundle CMake build for a reversible two-Mac test."""

import argparse
import plistlib
import re
import shutil
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("build", type=Path)
parser.add_argument("output", type=Path, help="New output folder; never overwrites")
parser.add_argument("--macdeployqt", required=True, type=Path)
parser.add_argument("--lrelease", required=True, type=Path)
parser.add_argument("--libpath", action="append", default=[], type=Path, help="Extra Qt module library path")
args = parser.parse_args()
source = Path(__file__).resolve().parents[2]
build = args.build.resolve()
output = args.output.resolve()
revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source, text=True).strip()
dirty = subprocess.check_output(["git", "status", "--porcelain"], cwd=source, text=True).strip()
if dirty:
    raise SystemExit("Commit source changes before preparing the test package.")
cache = (build / "CMakeCache.txt").read_text().splitlines()
version = next(line.split("=", 1)[1] for line in cache if line.startswith("CMAKE_PROJECT_VERSION:STATIC="))
output.mkdir(parents=True, exist_ok=False)
app = output / "Deskflow Fork Test.app"
contents = app / "Contents"
macos = contents / "MacOS"
resources = contents / "Resources"
macos.mkdir(parents=True)
resources.mkdir()
for name in ("Deskflow", "deskflow-core"):
    shutil.copy2(build / "bin" / name, macos / name)
shutil.copy2(source / "src/apps/res/Deskflow.icns", resources)
for name in ("LICENSE", "LICENSES", "docs"):
    origin = source / name
    if origin.is_dir():
        shutil.copytree(origin, resources / name)
    else:
        shutil.copy2(origin, resources / name)
translations = resources / "translations"
translations.mkdir()
for ts in sorted((source / "translations").glob("deskflow_*.ts")):
    subprocess.run([str(args.lrelease), str(ts), "-qm", str(translations / (ts.stem + ".qm"))], check=True)
info = {
    "CFBundleExecutable": "Deskflow",
    "CFBundleIdentifier": "dev.lxf82.deskflow.forktest",
    "CFBundleName": "Deskflow Fork Test",
    "CFBundleDisplayName": "Deskflow Fork Test",
    "CFBundleIconFile": "Deskflow.icns",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": ".".join(version.split(".")[:3]),
    "CFBundleVersion": version,
    "LSMinimumSystemVersion": "27.0",
    "DeskflowForkRevision": revision,
    "NSLocalNetworkUsageDescription": "Connect this Deskflow fork to your other Mac on the local network.",
    "NSHumanReadableCopyright": "Deskflow contributors; local test fork by lxf82dev",
    "NSSupportsAutomaticTermination": False,
    "NSSupportsSuddenTermination": False,
}
with (contents / "Info.plist").open("wb") as stream:
    plistlib.dump(info, stream)
# Homebrew splits QtSvg from QtBase. Seed complete runtime-only frameworks
# explicitly; Qt's deployment tool cannot always resolve these plugin loads.
extra_images = []
for path in args.libpath:
    for framework in sorted(path.glob("Qt*.framework")):
        destination = contents / "Frameworks" / framework.name
        version = destination / "Versions/A"
        version.mkdir(parents=True)
        image = version / framework.stem
        shutil.copy2(framework / "Versions/Current" / framework.stem, image)
        shutil.copytree(framework / "Resources", version / "Resources")
        (destination / "Versions/Current").symlink_to("A", target_is_directory=True)
        (destination / framework.stem).symlink_to("Versions/Current/" + framework.stem)
        (destination / "Resources").symlink_to("Versions/Current/Resources", target_is_directory=True)
        extra_images.append(image)
subprocess.run([
    str(args.macdeployqt), str(app), "-always-overwrite", "-no-codesign",
    "-executable=" + str(macos / "deskflow-core"),
    *("-executable=" + str(path) for path in extra_images),
    *("-libpath=" + str(path) for path in args.libpath),
], check=True)
# Audit all Mach-O images, including plugins, before signing. No Homebrew paths
# are allowed as runtime dependencies; copied libraries must remain relocatable.
for path in contents.rglob("*"):
    if not path.is_file() or path.is_symlink():
        continue
    kind = subprocess.check_output(["file", "-b", str(path)], text=True)
    if "Mach-O" not in kind:
        continue
    # A dylib's own LC_ID_DYLIB is listed by `otool -L` too, but is not a load
    # dependency. macdeployqt can retain its original absolute identity.
    identities = subprocess.check_output(["otool", "-D", str(path)], text=True).splitlines()[1:]
    commands = subprocess.check_output(["otool", "-l", str(path)], text=True)
    for rpath in re.findall(r"cmd LC_RPATH\n\s*cmdsize \d+\n\s*path (.*?) \(offset", commands):
        if rpath.startswith("/") and not rpath.startswith(("/System/Library/", "/usr/lib/")):
            subprocess.run(["install_name_tool", "-delete_rpath", rpath, str(path)], check=True)
    links = subprocess.check_output(["otool", "-L", str(path)], text=True).splitlines()[1:]
    for line in links:
        dependency = line.strip().split(" (", 1)[0]
        if dependency in identities:
            continue
        if dependency.startswith("/") and not dependency.startswith(("/System/Library/", "/usr/lib/")):
            if ".framework/" in dependency:
                prefix, suffix = dependency.split(".framework/", 1)
                relative = prefix.rsplit("/", 1)[-1] + ".framework/" + suffix
            else:
                relative = Path(dependency).name
            # Rebase only to an image already included in this bundle, never
            # to a file that might happen to exist on the developer's machine.
            if not (contents / "Frameworks" / relative).is_file():
                raise SystemExit(f"Unbundled dependency in {path}: {dependency}")
            replacement = "@rpath/" + relative
            subprocess.run(["install_name_tool", "-change", dependency, replacement, str(path)], check=True)
            dependency = replacement
        if dependency.startswith("@rpath/"):
            target = contents / "Frameworks" / dependency.removeprefix("@rpath/")
        elif dependency.startswith("@loader_path/"):
            target = path.parent / dependency.removeprefix("@loader_path/")
        elif dependency.startswith("@executable_path/"):
            target = macos / dependency.removeprefix("@executable_path/")
        else:
            continue
        if not target.is_file():
            raise SystemExit(f"Missing bundled dependency in {path}: {dependency}")
subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(app)], check=True)
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
for name in ("Start Fork Test.command", "Restore Previous Setup.command", "test-session.zsh", "permanent-login.zsh", "README.md"):
    shutil.copy2(Path(__file__).parent / name, output / name)
    if name != "README.md":
        (output / name).chmod(0o755)
(output / "BUILD.txt").write_text(
    f"Source: https://github.com/lxf82dev/deskflow\nRevision: {revision}\n"
    "Architecture: arm64\nMinimum macOS: 27.0\nLocal ad-hoc signature; not notarized.\n"
    "AWDL worker and system launch daemon are retained from the existing setup.\n"
)
print(f"Prepared {output}")
