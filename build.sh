#!/bin/zsh
#
# Kernel + package build script for Radxa Qcom platforms
#

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
clear='\033[0m'

KERNEL_PATH=$PWD
ARCH=arm64
OUT_DIR="out"
PKGREL="${PKGREL:-$(date -u +%Y%m%d%H%M)}"
ARM64_SCRIPTS_DIR="${KERNEL_PATH}/${OUT_DIR}/arm64-scripts-bin"
ARM64_SCRIPTS_IMAGE="${ARM64_SCRIPTS_IMAGE:-inferno0230/arm64-kernel-build-tools:latest}"
CONFIGS=(
    alarm.config
    qcom_module.config
    radxa-qcom.config
)

if command -v ccache >/dev/null 2>&1 && [ -d /usr/lib/ccache ]; then
    case ":$PATH:" in
        *:/usr/lib/ccache:*) ;;
        *) export PATH="/usr/lib/ccache/bin:$PATH" ;;
    esac
fi

DO_PACKAGE=false
CLEAN_BUILD=false
REGENERATE_SCRIPTS=false

regenerate_arm64_scripts() {
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${red}docker is required for --regenerate-scripts${clear}"
        exit 1
    fi

    echo -e "${blue}Regenerating arm64 scripts with Docker...${clear}"
    mkdir -p "$ARM64_SCRIPTS_DIR"

    docker run --privileged --rm tonistiigi/binfmt --install all || {
        echo -e "${red}Failed to install binfmt handlers${clear}"
        exit 1
    }

    docker run --rm \
        --platform linux/arm64 \
        -v "$ARM64_SCRIPTS_DIR:/aarch64_kernel_scripts" \
        -v "$KERNEL_PATH:/work/kernel" \
        "$ARM64_SCRIPTS_IMAGE" \
        bash -lc '
            set -e

            tmpdir=$(mktemp -d)
            trap '\''rm -rf "$tmpdir"'\'' EXIT

            cd /work/kernel
            make ARCH=arm64 LLVM=1 O="$tmpdir" qcom_module_defconfig
            make ARCH=arm64 LLVM=1 O="$tmpdir" modules_prepare

            rm -rf /aarch64_kernel_scripts/*
            cp -r "$tmpdir/scripts" /aarch64_kernel_scripts
        ' || {
        echo -e "${red}Failed to regenerate arm64 scripts${clear}"
        exit 1
    }

    echo -e "${green}arm64 scripts saved to ${ARM64_SCRIPTS_DIR}${clear}"
}

overlay_arm64_scripts() {
    local src_scripts_dir="$ARM64_SCRIPTS_DIR/scripts"
    local dest_scripts_dir="$OUT_DIR/build-pkg/scripts"
    local rel

    if [ ! -d "$src_scripts_dir" ]; then
        echo -e "${yellow}${src_scripts_dir} is missing; regenerating arm64 script binaries...${clear}"
        regenerate_arm64_scripts
    fi

    if [ ! -d "$dest_scripts_dir" ]; then
        echo -e "${red}Missing ${dest_scripts_dir}; cannot replace packaged script binaries.${clear}"
        exit 1
    fi

    echo -e "${blue}Replacing packaged script binaries with arm64 versions...${clear}"
    while IFS= read -r rel; do
        rel="${rel#./}"
        if [ -e "$dest_scripts_dir/$rel" ] || [ -L "$dest_scripts_dir/$rel" ]; then
            cp -a "$src_scripts_dir/$rel" "$dest_scripts_dir/$rel" || exit 1
        fi
    done < <(
        cd "$src_scripts_dir"
        find . \( -name '.*.cmd' -o -name '*.o' \) -prune -o \
            \( -type f -o -type l \) -print
    )
}

build_kernel() {
    cd "$KERNEL_PATH"
    start=$(date +%s)

    echo -e "${blue}Generating defconfig...${clear}"
    rm out/.config
    for cfg in "${CONFIGS[@]}"; do
        make O="$OUT_DIR" ARCH="$ARCH" LLVM=1 "$cfg"
        make O="$OUT_DIR" ARCH="$ARCH" LLVM=1 olddefconfig
    done

    echo -e "${blue}Building kernel...${clear}"

    make ARCH=$ARCH LLVM=1 \
        O=$OUT_DIR -j$(nproc) \
        Image Image.gz dtbs modules || exit 1

    echo -e "${green}Kernel build successful!${clear}"

    echo -e "${blue}Installing modules...${clear}"
    rm -rf $KERNEL_PATH/$OUT_DIR/modinst
    make ARCH=$ARCH LLVM=1 \
        O=$OUT_DIR \
        INSTALL_MOD_PATH="$KERNEL_PATH/$OUT_DIR/modinst" \
        INSTALL_MOD_STRIP=1 DEPMOD=true modules_install

    echo -e "${blue}Copying DTBs...${clear}"
    rm -rf $KERNEL_PATH/$OUT_DIR/dtbinst
    mkdir -p "$KERNEL_PATH/$OUT_DIR/dtbinst/qcom"
    find "$KERNEL_PATH/$OUT_DIR/arch/arm64/boot/dts" -name '*radxa*' ! -name '.*' -exec cp -a {} "$KERNEL_PATH/$OUT_DIR/dtbinst/qcom/" \;

    echo -e "${blue}Preparing headers payload...${clear}"
    rm -rf $KERNEL_PATH/$OUT_DIR/build-pkg
    rm -rf "$OUT_DIR/build-pkg"
    (
        cd "$OUT_DIR"
        srctree="$KERNEL_PATH" \
        SRCARCH="$ARCH" \
        MAKE=make \
        "$KERNEL_PATH/scripts/package/install-extmod-build" \
        "$KERNEL_PATH/$OUT_DIR/build-pkg"
    )
    overlay_arm64_scripts

    echo -e "${blue}Writing metadata...${clear}"
    BUILD_TS=$(date -u +%Y%m%d%H%M)
    cat > "$OUT_DIR/metadata.env" <<EOF
KERNELRELEASE=$(make -s O=$OUT_DIR ARCH=$ARCH LLVM=1 kernelrelease)
PKGREL=1
PKGVER=$BUILD_TS
EOF

    echo -e "${green}Build done in $(($(date +%s) - start))s${clear}"
}

package_kernel() {
    echo -e "${blue}Running makepkg...${clear}"

    export CARCH=aarch64

    makepkg -f || {
        echo -e "${red}Packaging failed!${clear}"
        exit 1
    }

    echo -e "${green}Package build complete${clear}"
}

# ---------------- ARG PARSE ----------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean)
            CLEAN_BUILD=true
            ;;
        --pkg)
            DO_PACKAGE=true
            ;;
        --regenerate-scripts)
            REGENERATE_SCRIPTS=true
            ;;
        *)
            echo "$1: unknown arg"
            exit 1
            ;;
    esac
    shift
done

# ---------------- EXECUTION ----------------

if [ "$CLEAN_BUILD" = true ]; then
    echo -e "${yellow}Cleaning output...${clear}"
    rm -rf "$OUT_DIR"
fi

if [ "$REGENERATE_SCRIPTS" = true ]; then
    regenerate_arm64_scripts
fi

build_kernel

if [ "$DO_PACKAGE" = true ]; then
    package_kernel
fi
