#!/bin/sh
# Retarget inter-repo Gewerber git dependencies.
#
# Rewrites the `ref:` of every `git:` dependency in pubspec.yaml /
# pubspec_overrides.yaml under the current directory that points at
# https://github.com/Gewerber/<repo> to the target ref (first argument).
# Other dependencies, `repository:` metadata and all remaining content are
# untouched.
#
# Used by the branch deploys (Dockerfile ARG GEWERBER_DEP_REF) so that a
# deployment of `develop` consumes the `develop` branches of the other
# Gewerber repositories end-to-end; `main` deployments keep the committed
# `ref: main` (the Dockerfile does not call this script for them).
#
# Usage: retarget_gewerber_refs.sh <git-ref>   (run from the build root)
set -eu

target=${1:-}
if [ -z "$target" ]; then
  echo "usage: $0 <git-ref>" >&2
  exit 64
fi

count=0
# Skip generated trees; they may contain copied manifests.
for manifest in $(find . \
    \( -path '*/.dart_tool' -o -path '*/build' \) -prune -o \
    \( -name pubspec.yaml -o -name pubspec_overrides.yaml \) -print); do
  awk -v ref="$target" '
    # A git-dependency block starts at an indented url: line pointing at a
    # Gewerber repository; its ref: line (optionally preceded by path:) is
    # the only thing rewritten.
    /^[[:space:]]+url:[[:space:]]*https:\/\/github\.com\/Gewerber\// {
      pending = 1
      print
      next
    }
    pending && /^[[:space:]]+ref:/ {
      sub(/ref:.*/, "ref: " ref)
      pending = 0
      print
      next
    }
    pending && /^[[:space:]]+(path|version):/ {
      print
      next
    }
    {
      pending = 0
      print
    }
  ' "$manifest" > "$manifest.retarget.tmp"
  if cmp -s "$manifest" "$manifest.retarget.tmp"; then
    rm -f "$manifest.retarget.tmp"
  else
    mv "$manifest.retarget.tmp" "$manifest"
    count=$((count + 1))
    echo "retargeted Gewerber git deps in $manifest -> ref: $target"
  fi
done

echo "retarget_gewerber_refs: done ($count manifest file(s) updated, target ref: $target)"
