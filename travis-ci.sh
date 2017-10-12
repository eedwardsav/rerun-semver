#!/usr/bin/env bash

# Fail fast on errors and unset variables.
set -eu

# Prepare.
# --------
# set version patch number to build number from travis
sed -i -r 's,^VERSION=([0-9]+\.[0-9]+)\.0$,VERSION=\1.'"${TRAVIS_BUILD_NUMBER:?SetupTravisCorrectly}"',g' metadata
export VERSION="$(awk -F= '/VERSION/ {print $2}' metadata)"
mymod="$(awk -F= '/NAME/ {print $2}' metadata)"

echo "Building version ${VERSION:?"Corrupt metadata file"} of ${mymod:?"Corrupt metadata file"}..."
# Create a scratch directory and change directory to it.
WORK_DIR=$(mktemp -d "/tmp/build-${mymod}.XXXXXX")
mkdir "${WORK_DIR:?'Unable to create temp dir'}/${mymod}"

git clone "file://${TRAVIS_BUILD_DIR:?SetupTravisCorrectly}" "${WORK_DIR}/${mymod}"
cp -p metadata "${WORK_DIR}/${mymod}"/
# Bootstrap
# ---------

# Setup the rerun execution environment.
export RERUN_MODULES="${WORK_DIR}:${RERUN_MODULES:-/usr/lib/rerun/modules}"

# Test.
# --------
rerun stubbs: test --module ${mymod}

# Build the module.
# -----------------
echo "Packaging the build..."

# Build the archive!
rerun stubbs:archive --modules "${mymod}"
BIN="rerun.sh"
[ ! -f "${BIN}" ] && {
    echo >&2 "ERROR: ${BIN} archive was not created."; exit 1
}

# Test the archive by making it do a command list.
./${BIN} "${mymod}"

# Build a deb
#-------------
rerun stubbs:archive --modules "${mymod}" --format deb --version "${VERSION}" --release "${RELEASE:=1}"
sysver="${VERSION}-${RELEASE}"
DEB="rerun-${mymod}_${sysver}_all.deb"
[ ! -f "${DEB}" ] && {
    echo >&2 "ERROR: ${DEB} file was not created."
    files=( *.deb )
    echo >&2 "ERROR: ${#files[*]} files matching .deb: ${files[*]}"
    exit 1
}
# Build a rpm
#-------------
rerun stubbs:archive --modules "${mymod}" --format rpm --version "${VERSION}" --release "${RELEASE}"
RPM=rerun-${mymod}-${sysver}.linux.noarch.rpm
[ ! -f "${RPM}" ] && {
    echo >&2 "ERROR: ${RPM} file was not created."
    files=( *.rpm )
    echo >&2 "ERROR: ${#files[*]} files matching .rpm: ${files[*]}"
    exit 1
}

if [[ "${TRAVIS_BRANCH}" == "master" && "${TRAVIS_PULL_REQUEST}" == "false" ]]; then

  echo "Files to publish"
  ls -1 rerun.sh rerun-${mymod}*

  export USER=${BINTRAY_USER:?"Setup Travis with BINTRAY_USER env variable"}
  export APIKEY=${BINTRAY_APIKEY:?"Setup Travis with BINTRAY_APIKEY env variable"}
  export ORG=${BINTRAY_ORG:?"Setup Travis with BINTRAY_ORG env variable"}
  export PACKAGE="${mymod}"
  
  # Upload and publish to bintray
  echo "Uploading ${BIN} to bintray: /${BINTRAY_ORG}/rerun-modules/${mymod}/${VERSION}..."
  export REPO="rerun-modules"
  rerun bintray:package-upload --file "${BIN}"

  echo "Uploading debian package ${DEB} to bintray: /${BINTRAY_ORG}/rerun-deb ..."
  export PACKAGE="rerun-${mymod}"
  export REPO="rerun-deb"
  rerun bintray:package-upload-deb --version "${sysver}" --file "${DEB}" --deb_architecture all
  rerun bintray:package-upload --version "${sysver}" --file "${PACKAGE}_${VERSION}.orig.tar.gz"
  rerun bintray:package-upload --version "${sysver}" --file "${PACKAGE}_${sysver}.debian.tar.gz"
  rerun bintray:package-upload --version "${sysver}" --file "${PACKAGE}_${sysver}_amd64.build"
  rerun bintray:package-upload --version "${sysver}" --file "${PACKAGE}_${sysver}_amd64.changes"
  rerun bintray:package-upload --version "${sysver}" --file "${PACKAGE}_${sysver}.dsc"

  echo "Uploading rpm package ${RPM} to bintray: /${BINTRAY_ORG}/rerun-rpm ..."
  export REPO="rerun-rpm"
  rerun bintray:package-upload --version "${sysver}" --file "${RPM}"

else
  echo "***************************"
  echo "***                     ***"
  echo "*** Travis-CI sayz LGTM ***"
  echo "***                     ***"
  echo "***************************"
fi


echo "Done."
