# Rockchip RK3568 quad core 1-8GB SoC GBe eMMC USB3
BOARD_NAME="100ASK DshanPi R1 / R1+"
BOARD_VENDOR="dongshanpi"
BOARDFAMILY="rk35xx"
BOARD_MAINTAINER=""
INTRODUCED="2024"
BOOTCONFIG="dshanpi-r1-rk3568_defconfig"
KERNEL_TARGET="current,edge,vendor"
KERNEL_TEST_TARGET="current,vendor"
FULL_DESKTOP="yes"
BOOT_LOGO="desktop"
BOOT_FDT_FILE="rockchip/rk3568-dshanpi-r1.dtb"
BOOT_SCENARIO="spl-blobs"
IMAGE_PARTITION_TABLE="gpt"
# The R1+ M.2 E-key slot takes whatever WiFi card the user picks, so ship
# the full linux-firmware set instead of the default selection.
BOARD_FIRMWARE_INSTALL="-full"

# WiFi/BT wiring (SDMMC2 + UART8) serves the onboard AP6256 on the R1 and
# the M.2 E-key slot on the R1+. Both nodes stay disabled by default; add
# "overlays=wlan-ap6256" to armbianEnv.txt to enable them. A PCIe WiFi or
# NVMe card in the R1+ slot works without any overlay. Add
# "overlays=disable-pcie" when no PCIe card is used: the mainline PCIe
# driver keeps an unused PHY powered, which costs about 0.6 W at idle.

function post_family_config__dshanpi-r1_overlay_prefix() {
	# The rk35xx family config resets OVERLAY_PREFIX after the board file runs.
	declare -g OVERLAY_PREFIX="rk3568-dshanpi-r1"
}

function post_family_config__dshanpi-r1_vendor_console_cmdline() {
	# extlinux builds ship no boot.cmd; the cmdline comes from SRC_CMDLINE
	# (cf. radxa-e24c). Serial last keeps /dev/console on the debug UART.
	[[ $BRANCH == legacy || $BRANCH == vendor ]] || return 0
	declare -g SRC_CMDLINE="${SRC_CMDLINE:+${SRC_CMDLINE} }console=tty1 console=ttyFIQ0,1500000n8"
}

function post_family_tweaks__dshanpi-r1_serial_console_last() {
	# Append the serial console after HDMI tty1 so /dev/console (initramfs,
	# systemd, printk) stays on the debug UART: ttyFIQ0 on vendor, ttyS2 on mainline.
	if [[ $SRC_EXTLINUX == yes ]]; then
		# extlinux images ship no boot.cmd; console comes from SRC_CMDLINE above.
		display_alert "$BOARD" "extlinux build: console handled via SRC_CMDLINE, skipping boot.cmd tweak" "info"
		return 0
	fi
	local serial_console="ttyS2,1500000"
	[[ $BRANCH == legacy || $BRANCH == vendor ]] && serial_console="ttyFIQ0,1500000"
	display_alert "$BOARD" "Putting console=${serial_console%%,*} last in boot.cmd cmdline" "info"
	if ! grep -qF 'setenv consoleargs "console=ttyS2,1500000 ${consoleargs}"' "${SDCARD}/boot/boot.cmd"; then
		exit_with_error "dshanpi-r1: boot.cmd console template changed; update the sed in post_family_tweaks__dshanpi-r1_serial_console_last"
	fi
	sed -i "s/setenv consoleargs \"console=ttyS2,1500000 \${consoleargs}\"/setenv consoleargs \"\${consoleargs} console=${serial_console}\"/" \
		"${SDCARD}/boot/boot.cmd"
	mkimage -C none -A arm -T script -d "${SDCARD}/boot/boot.cmd" "${SDCARD}/boot/boot.scr"
}

function pre_config_uboot_target__dshanpi-r1_boot_sd_first() {
	# mmc0 is the TF slot and mmc1 is eMMC. rk356x-u-boot.dtsi swaps those
	# aliases; the board u-boot dtsi puts them back. No "spi" target - the
	# board carries no SPI-NOR flash.
	declare -a rockchip_uboot_targets=("mmc0" "mmc1" "nvme" "scsi" "usb" "pxe" "dhcp")
	display_alert "u-boot for ${BOARD}/${BRANCH}" "u-boot: adjust boot order to '${rockchip_uboot_targets[*]}'" "info"
	if ! grep -q '^[[:space:]]*#define BOOT_TARGETS' include/configs/rockchip-common.h; then
		exit_with_error "dshanpi-r1: BOOT_TARGETS define not found in include/configs/rockchip-common.h; the U-Boot release moved or renamed it - update pre_config_uboot_target__dshanpi-r1_boot_sd_first"
	fi
	sed -i -e "s/#define BOOT_TARGETS.*/#define BOOT_TARGETS \"${rockchip_uboot_targets[*]}\"/" include/configs/rockchip-common.h
	regular_git diff -u include/configs/rockchip-common.h || true
}

function post_family_config__dshanpi-r1_use_mainline_uboot() {
	display_alert "$BOARD" "Mainline U-Boot overrides for $BOARD - $BRANCH" "info"
	declare -g BOOTCONFIG="dshanpi-r1-rk3568_defconfig"
	declare -g BOOTDELAY=1
	declare -g BOOTSOURCE="https://github.com/u-boot/u-boot"
	declare -g BOOTBRANCH="tag:v2026.07"
	declare -g BOOTPATCHDIR="v2026.07"
	declare -g BOOTDIR="u-boot-${BOARD}"
	declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"
	# rockchip64_common's postprocess hooks fight binman here; drop them.
	unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

	# The binman-provided u-boot-rockchip.bin is ready to flash as-is.
	function write_uboot_platform() {
		dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
	}
}
