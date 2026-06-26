#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
module_rel="nebula-core-module"
module_src="$repo_root/$module_rel"
build_dir="$repo_root/build/module"
stage_dir="$build_dir/stage"
version="$(sed -n 's/^nebulaVersion=//p' "$repo_root/gradle.properties" | head -n 1)"
version_code="$(sed -n 's/^nebulaVersionCode=//p' "$repo_root/gradle.properties" | head -n 1)"
source_ref="$(git -C "$repo_root" rev-parse --short=12 "HEAD:$module_rel" 2>/dev/null || git -C "$repo_root" rev-parse --short=12 HEAD 2>/dev/null || printf unknown)"
zip_path="$build_dir/Droidspaces-Nebula-Core-$version.zip"

if [[ -z "$version" || -z "$version_code" ]]; then
  echo "missing nebulaVersion or nebulaVersionCode in gradle.properties" >&2
  exit 1
fi

rm -rf "$stage_dir"
mkdir -p "$stage_dir" "$build_dir"

cp -a "$module_src"/. "$stage_dir"/
sed -i "s/^version=.*/version=$version/" "$stage_dir/module.prop"
sed -i "s/^versionCode=.*/versionCode=$version_code/" "$stage_dir/module.prop"

printf '%s\n' "$source_ref" > "$stage_dir/config/git-commit.txt"
find "$stage_dir" -type f -exec chmod 0644 {} +
chmod 0755 "$stage_dir"/*.sh "$stage_dir/bin/nebula-core"
find "$stage_dir" -exec touch -d '@0' {} +

rm -f "$zip_path"
(
  cd "$stage_dir"
  LC_ALL=C find . -type f | sed 's#^\./##' | sort | zip -X -q "$zip_path" -@
)

printf '%s\n' "$zip_path"
