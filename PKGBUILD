# SPDX-License-Identifier: GPL-2.0-only

pkgbase=linux-radxa-qcom
pkgname=("${pkgbase}" "${pkgbase}-headers")

pkgdesc="Linux kernel for Radxa Qcom platforms"
url='https://github.com/inferno0230/linux-radxa-qcom'
arch=(aarch64)
license=(GPL-2.0-only)
provides=(linux)
options=('!strip')

KERNEL_PWD=${KERNEL_PWD:-$PWD}
OUT_DIR="${KERNEL_PWD}/out"

# Load metadata from build.sh
if [ ! -f "${OUT_DIR}/metadata.env" ]; then
    echo "Missing metadata.env — run ./build.sh first"
    exit 1
fi

source "${OUT_DIR}/metadata.env"

pkgver="${PKGVER}"
pkgrel="${PKGREL}"

build() {
    echo "Skipping build() — using prebuilts"
}

_package() {
    pkgdesc="Kernel and modules"
    depends=('coreutils' 'kmod' 'linux-firmware-qcom')
    optdepends=(
        'linux-firmware: firmware images needed for some devices'
        'wireless-regdb: to set the correct wireless channels of your country'
    )
    provides=("linux=${pkgver}")

    local modulesdir="${pkgdir}/usr/lib/modules/${KERNELRELEASE}"

    echo "Installing kernel images..."
    if [ -f "${OUT_DIR}/arch/arm64/boot/Image.gz" ]; then
        install -Dm644 "${OUT_DIR}/arch/arm64/boot/Image.gz" "${pkgdir}/boot/Image.gz"
    else
        echo "Warning: No Image.gz found!"
    fi

    if [ -f "${OUT_DIR}/arch/arm64/boot/Image" ]; then
        install -Dm644 "${OUT_DIR}/arch/arm64/boot/Image" "${pkgdir}/boot/Image"
        install -Dm644 "${OUT_DIR}/arch/arm64/boot/Image" "${modulesdir}/vmlinuz"
    else
        echo "Warning: No Image found!"
    fi

    echo "${pkgbase}" > "${modulesdir}/pkgbase"

    echo "Installing modules..."
    cp -a "${OUT_DIR}/modinst/lib/modules/${KERNELRELEASE}/." "${modulesdir}/"

    echo "Installing QCOM DTBs..."
    if [ -d "${OUT_DIR}/dtbinst/qcom" ]; then
        mkdir -p "${modulesdir}/dtb/qcom"
        cp -a "${OUT_DIR}/dtbinst/qcom/"* "${modulesdir}/dtb/qcom/"

        mkdir -p "${pkgdir}/boot/dtbs/qcom"
        cp -a "${OUT_DIR}/dtbinst/qcom/"* "${pkgdir}/boot/dtbs/qcom/"
    else
        echo "Warning: No QCOM DTBs found!"
    fi

    rm -f "${modulesdir}/build"
}

_package-headers() {
    pkgdesc="Kernel headers"
    provides=("linux-headers=${pkgver}")

    local builddir="${pkgdir}/usr/lib/modules/${KERNELRELEASE}/build"
    mkdir -p "${builddir}"
    cp -r "${OUT_DIR}/build-pkg/"* "${builddir}/"
    [ -f "${OUT_DIR}/System.map" ] && cp "${OUT_DIR}/System.map" "${builddir}/"
    [ -f "${OUT_DIR}/.config" ] && cp "${OUT_DIR}/.config" "${builddir}/.config"
    mkdir -p "${pkgdir}/usr/src"
    ln -sr "${builddir}" "${pkgdir}/usr/src/${pkgbase}"
}

for _p in "${pkgname[@]}"; do
    eval "package_$_p() {
        $(declare -f "_package${_p#$pkgbase}")
        _package${_p#$pkgbase}
    }"
done
