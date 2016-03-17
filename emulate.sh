#!/bin/bash
# Based on a test script from avsm/ocaml repo https://github.com/avsm/ocaml

MIRROR=http://ftp.debian.org/debian
VERSION=wheezy

# Debian package dependencies for the host
HOST_DEPENDENCIES="debootstrap qemu-user-static binfmt-support sbuild"

# Debian package dependencies for the chrooted environment
GUEST_DEPENDENCIES="build-essential autotools-dev autoconf m4 git"

# Command used to run the tests
TEST_COMMAND="./travis-ci.sh"

CHROOT_ARCH=$1

QEMU_ARCH=$2

CHROOT_DIR="/tmp/${CHROOT_ARCH}-chroot"

ENV_FILE="${CHROOT_ARCH}-env.sh"

function setup_chroot {

    # Host dependencies
    echo "Installing host dependencies"
    sudo apt-get install -qq -y ${HOST_DEPENDENCIES}

    # Create chrooted environment
    sudo mkdir ${CHROOT_DIR}
    sudo debootstrap --foreign --no-check-gpg --include=fakeroot,build-essential \
        --arch=${CHROOT_ARCH} ${VERSION} ${CHROOT_DIR} ${MIRROR}
    sudo cp /usr/bin/qemu-${QEMU_ARCH}-static ${CHROOT_DIR}/usr/bin/
    sudo chroot ${CHROOT_DIR} ./debootstrap/debootstrap --second-stage
    sudo sbuild-createchroot --arch=${CHROOT_ARCH} --foreign --setup-only \
        ${VERSION} ${CHROOT_DIR} ${MIRROR}

    # Create file with environment variables which will be used inside chrooted
    # environment
    echo "export ARCH=${ARCH}" > ${ENV_FILE}
    echo "export TRAVIS_BUILD_DIR=${TRAVIS_BUILD_DIR}" >> ${ENV_FILE}
    chmod a+x ${ENV_FILE}

    # Install dependencies inside chroot
    echo "Installing guest dependencies"
    sudo chroot ${CHROOT_DIR} apt-get update
    sudo chroot ${CHROOT_DIR} apt-get --allow-unauthenticated install \
        -qq -y ${GUEST_DEPENDENCIES}

    # Create build dir and copy travis build files to our chroot environment
    sudo mkdir -p ${CHROOT_DIR}/${TRAVIS_BUILD_DIR}
    sudo rsync -av ${TRAVIS_BUILD_DIR}/ ${CHROOT_DIR}/${TRAVIS_BUILD_DIR}/

    # Indicate chroot environment has been set up
    sudo touch ${CHROOT_DIR}/.chroot_is_done

    # Call ourselves again which will cause tests to run
    sudo chroot ${CHROOT_DIR} /bin/bash -c "cd ${TRAVIS_BUILD_DIR} && ./emulate.sh ${CHROOT_ARCH} ${QEMU_ARCH} chroot_done"
}

if [ "$3" = "chroot_done" ]; then
  # We are inside chroot
  echo "Running inside chrooted environment"

  source ./${ENV_FILE}

else
  if [ ! "$1" = "amd64" ]; then
    echo "Setting up chrooted ${CHROOT_ARCH} environment"
    setup_chroot
  fi
fi

echo "Running tests"
echo "Environment: $(uname -a)"

${TEST_COMMAND}
