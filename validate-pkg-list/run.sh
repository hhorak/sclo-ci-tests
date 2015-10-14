#!/bin/bash

# Setup a vagrant infra we can use
# ToDo: check we are on centos7
# ToDo: check we are being run as root

#set -ex

source common.sh

if [ $# -lt 2 ] ; then
  echo "Usage: `basename $0` <collection> <el_version{6|7|..}>" >&2
  exit 1
fi

collection="$1"
el_version="$2"
arch=${3-x86_64}
retval=0

# construct repoquery arguments
namespace=$(get_scl_namespace "$collection" "$el_version")
repo="sclo${el_version}-${collection}-${namespace}-candidate"
rq_args="--disablerepo=* --repofrompath=$collection,http://cbs.centos.org/repos/${repo}/${arch}/os/ --enablerepo=$collection"
#for c in `get_depended_collections "$collection"` ; do
#  rq_args="$rq_args --repofrompath=$c,http://cbs.centos.org/repos/sclo${el_version}-${c}-${namespace}-candidate/${arch}/os/ --enablerepo=$c"
#done

# check that all packages use expected arch or noarch
bad_arch=$(repoquery $rq_args --qf '%{ARCH} %{NVR}' -a 2>/dev/null | grep -v -e '^noarch ' -e "$arch " &>/dev/null) || :
if [ -n "$bad_arch" ] ; then
  echo "[FAIL] Repository $repo includes unexpectedd arches packages:"
  echo "$bad_arch"
  retval=1
else
  echo "[PASS] Repository $repo includes only expected arches"
fi

# check we have what we think we should have in the repo (note that this ignores versions of packages)
pkgs_available=$(mktemp /tmp/pkgs-available-XXXXXX)
pkgs_missing=$(mktemp /tmp/pkgs-missing-XXXXXX)
pkgs_extra=$(mktemp /tmp/pkgs-extra-XXXXXX)
repoquery $rq_args --qf '%{NAME}' -a 2>/dev/null | sort >$pkgs_available
touch "$pkgs_missing"
touch "$pkgs_extra"
cat ../PackageLists/${collection}/all | while read line ; do
  pkg=$(echo "$line" | awk '{print $1}')
  only_el_version=$(echo "$line" | awk '{print $2}')
  if [[ "$only_el_version" =~ rhel-.* ]] && [ "$only_el_version" != "rhel-$el_version" ] ; then
    continue
  fi
  if ! grep -e "^$pkg$" "$pkgs_available" &>/dev/null ; then
    echo "[FAIL] Package $pkg missing in $repo" >>$pkgs_missing
  fi
done

# check whether there are some more packages, in the repo (but ignore extra packages from this collection)
cat "$pkgs_available" | grep -v -e "^$collection" | while read pkg ; do
  grep -e "^[[:space:]]*$pkg[[:space:]]*\(?rhel.*\)\?[[:space:]]*$" ../PackageLists/${collection}/all &>/dev/null || echo "[FAIL] Package $pkg should not be in $repo" >>$pkgs_extra
done

# print results
missing=$(cat $pkgs_missing)
if [ -n "$missing" ] ; then
  echo "$missing"
  retval=1
fi
extra=$(cat $pkgs_extra)
if [ -n "$extra" ] ; then
  echo "$extra"
  retval=1
fi

# clean temporary files
rm -f "$pkgs_available"
rm -f "$pkgs_missing"
rm -f "$pkgs_extra"

if [ "$retval" -eq 0 ] ; then
  echo "[PASS] The package list looks fine"
fi

exit $retval
