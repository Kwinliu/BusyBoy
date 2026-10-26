#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
project_root="$(pwd -P)"
case "$project_root" in
  *OneDrive*|*CloudStorage*|*Mobile\ Documents*|*Dropbox*)
    echo '请先把开发工作树放到非同步的本地短路径，再运行编译。' >&2
    exit 1
    ;;
esac
mkdir -p .build

# Some CLT installations contain obsolete private PackageDescription interfaces.
# Prefer a project-local copy of the public interfaces; never alter the toolchain.
toolchain_pm="$(xcrun --find swift | xargs dirname)/../lib/swift/pm"
toolchain_include="$(xcrun --find swift | xargs dirname)/../include/swift"
manifest_copy="$PWD/.build/manifest-libs"
if [ -d "$toolchain_pm/ManifestAPI" ]; then
  mkdir -p "$manifest_copy"
  rsync -a --exclude='*.private.swiftinterface' "$toolchain_pm/" "$manifest_copy/"
  export SWIFTPM_CUSTOM_LIBS_DIR="$manifest_copy"
fi

# CLT upgrades may also leave the old SwiftBridging module map beside its
# replacement. Hide only that duplicate through a compiler VFS overlay.
# System files remain untouched.
compiler_flags=()
if [ -f "$toolchain_include/module.modulemap" ] && [ -f "$toolchain_include/bridging.modulemap" ] &&
   /usr/bin/grep -q 'module SwiftBridging' "$toolchain_include/module.modulemap" &&
   /usr/bin/grep -q 'module SwiftBridging' "$toolchain_include/bridging.modulemap"; then
  mkdir -p .build/toolchain
  : > .build/toolchain/empty.modulemap
  include_real="$(cd "$toolchain_include" && pwd -P)"
  cat > .build/toolchain/overlay.yaml <<YAML
{"version":0,"roots":[{"type":"file","name":"$include_real/module.modulemap","external-contents":"$PWD/.build/toolchain/empty.modulemap"}]}
YAML
  overlay="$PWD/.build/toolchain/overlay.yaml"
  compiler_flags=(-vfsoverlay "$overlay" -Xcc -ivfsoverlay -Xcc "$overlay")
fi

case "${1:-}" in
  --compile)
    shift
    exec swiftc "${compiler_flags[@]}" "$@"
    ;;
  build|test|run)
    package_flags=()
    for flag in "${compiler_flags[@]}"; do package_flags+=(-Xswiftc "$flag"); done
    exec swift "$@" "${package_flags[@]}"
    ;;
  *) exec swift "${compiler_flags[@]}" "$@" ;;
esac
