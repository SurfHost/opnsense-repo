#!/bin/sh
#
# Copyright (c) 2026 SurfHost.nl
# SPDX-License-Identifier: MIT
#
# Publish packages to the shared SurfHost package repository, served by
# GitHub Pages from the gh-pages branch of SurfHost/opnsense-repo:
#
#   https://surfhost.github.io/opnsense-repo/${ABI}
#
# Run it ON an OPNsense box (FreeBSD): `pkg repo` must run on the ABI the
# packages target. Each plugin's release script fetches this file standalone
# and calls it with the packages it built:
#
#   fetch -o /tmp/publish.sh https://raw.githubusercontent.com/SurfHost/opnsense-repo/main/tools/publish.sh
#   sh /tmp/publish.sh /path/os-foo-1.0.pkg [/path/dependency-2.3.pkg ...]
#
# Unlike a wholesale replace, this only swaps the packages it is given: for
# every package passed in, files in the ABI directory that carry the same
# package NAME (any version) are removed first, and every other package stays.
# That is what lets several plugins, released independently, share one repo.
# The catalogue is then regenerated over the whole directory, as is the
# index.html listing.
#
# The single interactive moment is the push: enter SurfHost and paste a
# fine-grained PAT (Contents: write on SurfHost/opnsense-repo) as password.
#
# Environment overrides:
#   REPO_URL     git remote          (default the GitHub HTTPS URL)
#   PAGES_CLONE  working clone       (default /tmp/surfhost-opnsense-repo)
#   CONF_URL     surfhost.conf to publish at the Pages root
#   DRY_RUN      set to 1 to prepare the clone and commit nothing

set -eu

REPO_URL=${REPO_URL:-https://github.com/SurfHost/opnsense-repo.git}
PAGES_CLONE=${PAGES_CLONE:-/tmp/surfhost-opnsense-repo}
CONF_URL=${CONF_URL:-https://raw.githubusercontent.com/SurfHost/opnsense-repo/main/surfhost.conf}
DRY_RUN=${DRY_RUN:-0}

die() {
    echo "!!! $*" >&2
    exit 1
}

[ $# -gt 0 ] || die "usage: sh publish.sh <package.pkg> [<package.pkg> ...]"

ABI=$(pkg config abi)

# repository metadata also ends in .pkg; it is never a package to publish
is_metadata() {
    case "$(basename "$1")" in
    packagesite.*|data.*|meta|meta.*|filesite.*|digests.*) return 0 ;;
    esac
    return 1
}

NAMES=""
for FILE in "$@"; do
    [ -f "${FILE}" ] || die "${FILE} does not exist"
    is_metadata "${FILE}" && die "${FILE} is repository metadata, not a package"
    NAME=$(pkg query -F "${FILE}" '%n') || die "${FILE} is not a package"
    NAMES="${NAMES} ${NAME}"
done
echo "==> publishing${NAMES} for ${ABI}"

rm -rf "${PAGES_CLONE}"
if git ls-remote --exit-code --heads "${REPO_URL}" gh-pages >/dev/null 2>&1; then
    git clone --branch gh-pages --depth 1 "${REPO_URL}" "${PAGES_CLONE}"
else
    echo "    gh-pages does not exist yet, starting it"
    mkdir -p "${PAGES_CLONE}"
    git -C "${PAGES_CLONE}" init -q
    git -C "${PAGES_CLONE}" checkout -q -b gh-pages
    git -C "${PAGES_CLONE}" remote add origin "${REPO_URL}"
fi
git -C "${PAGES_CLONE}" config user.name >/dev/null 2>&1 || git -C "${PAGES_CLONE}" config user.name "SurfHost"
git -C "${PAGES_CLONE}" config user.email >/dev/null 2>&1 || git -C "${PAGES_CLONE}" config user.email "hans@surfhost.nl"

DEST="${PAGES_CLONE}/${ABI}"
mkdir -p "${DEST}"

# drop every version of the packages being published, nothing else
for OLD in "${DEST}"/*.pkg; do
    [ -f "${OLD}" ] || continue
    is_metadata "${OLD}" && continue
    OLDNAME=$(pkg query -F "${OLD}" '%n' 2>/dev/null) || continue
    for NAME in ${NAMES}; do
        if [ "${OLDNAME}" = "${NAME}" ]; then
            echo "    replacing $(basename "${OLD}")"
            rm -f "${OLD}"
        fi
    done
done
for FILE in "$@"; do
    cp "${FILE}" "${DEST}/"
done

pkg repo "${DEST}"

fetch -qo "${PAGES_CLONE}/surfhost.conf" "${CONF_URL}" || die "could not fetch ${CONF_URL}"
touch "${PAGES_CLONE}/.nojekyll"

html() {
    # escape for HTML text and attribute values
    printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'
}

{
    cat <<'EOF'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>SurfHost OPNsense plugins</title>
<style>
  :root { color-scheme: light dark; }
  body { font-family: system-ui, -apple-system, "Segoe UI", sans-serif; line-height: 1.6;
         max-width: 46rem; margin: 3rem auto; padding: 0 1rem; }
  code, pre { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
  pre { background: rgba(127,127,127,.12); padding: 1rem; border-radius: .5rem; overflow-x: auto; }
  h1 { font-size: 1.6rem; }
  li { margin-bottom: .5rem; }
  .muted, footer { font-size: .9rem; opacity: .75; }
  footer { margin-top: 3rem; }
</style>
</head>
<body>
<h1>SurfHost OPNsense plugins</h1>
<p>Package repository for OPNsense plugins published by SurfHost. Add it on your
firewall once, then install the plugins from <em>System &gt; Firmware &gt; Plugins</em>
as usual.</p>
<pre>fetch -o /usr/local/etc/pkg/repos/surfhost.conf \
    https://surfhost.github.io/opnsense-repo/surfhost.conf
pkg update</pre>
EOF
    for ABIDIR in "${PAGES_CLONE}"/*:*:*; do
        [ -d "${ABIDIR}" ] || continue
        printf '<h2>Plugins for %s</h2>\n<ul>\n' "$(html "$(basename "${ABIDIR}")")"
        for P in "${ABIDIR}"/os-*.pkg; do
            [ -f "${P}" ] || continue
            N=$(pkg query -F "${P}" '%n')
            V=$(pkg query -F "${P}" '%v')
            C=$(pkg query -F "${P}" '%c')
            W=$(pkg query -F "${P}" '%w')
            printf '  <li><strong>%s</strong> %s: %s' "$(html "${N}")" "$(html "${V}")" "$(html "${C}")"
            case "${W}" in
            https://*) printf ' (<a href="%s">source and documentation</a>)' "$(html "${W}")" ;;
            esac
            printf '</li>\n'
        done
        printf '</ul>\n'
        OTHERS=""
        for P in "${ABIDIR}"/*.pkg; do
            [ -f "${P}" ] || continue
            is_metadata "${P}" && continue
            case "$(basename "${P}")" in os-*) continue ;; esac
            OTHERS="${OTHERS} $(pkg query -F "${P}" '%n-%v')"
        done
        if [ -n "${OTHERS}" ]; then
            printf '<p class="muted">Dependencies mirrored from FreeBSD because OPNsense does not build them:%s</p>\n' \
                "$(html "${OTHERS}")"
        fi
    done
    cat <<'EOF'
<footer>
  Served from the <code>gh-pages</code> branch of
  <a href="https://github.com/SurfHost/opnsense-repo">SurfHost/opnsense-repo</a>.
</footer>
</body>
</html>
EOF
} > "${PAGES_CLONE}/index.html"

cd "${PAGES_CLONE}"
git add -A
if git diff --cached --quiet; then
    echo "==> nothing changed"
    exit 0
fi
echo "==> changes:"
git diff --cached --stat
if [ "${DRY_RUN}" = "1" ]; then
    echo "==> DRY_RUN=1, not committed; inspect ${PAGES_CLONE}"
    exit 0
fi
git commit -q -m "Publish${NAMES} for ${ABI}"
echo "==> pushing: enter SurfHost and paste the PAT at the git prompt"
git push -u origin gh-pages
echo "==> published; firewalls pick it up after 'pkg update'"
