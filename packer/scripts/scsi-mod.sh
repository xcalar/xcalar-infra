#!/bin/bash

. /etc/default/grub

if [ -n "$GRUB_CMDLINE_LINUX" ]; then
	GRUB_CMDLINE_LINUX="${GRUB_CMDLINE_LINUX//scsi_mod.use_blk_mq=?/}scsi_mod.use_blk_mq=Y"
	GRUB_CMDLINE_LINUX="${GRUB_CMDLINE_LINUX// rhgb quiet/}"
	GRUB_CMDLINE_LINUX="${GRUB_CMDLINE_LINUX//rhgb quiet/}"

	sed -i '/GRUB_CMDLINE_LINUX=/d' /etc/default/grub
	cat >> /etc/default/grub <<-EOF
	GRUB_CMDLINE_LINUX="$GRUB_CMDLINE_LINUX"
	EOF
elif [ -n "$GRUB_CMDLINE_LINUX_DEFAULT" ]; then
	GRUB_CMDLINE_LINUX_DEFAULT="${GRUB_CMDLINE_LINUX_DEFAULT//scsi_mod.use_blk_mq=?/}scsi_mod.use_blk_mq=Y"
	GRUB_CMDLINE_LINUX_DEFAULT="${GRUB_CMDLINE_LINUX_DEFAULT// rhgb quiet/}"
	GRUB_CMDLINE_LINUX_DEFAULT="${GRUB_CMDLINE_LINUX_DEFAULT//rhgb quiet/}"
	GRUB_CMDLINE_LINUX_DEFAULT="${GRUB_CMDLINE_LINUX_DEFAULT// splash/}"
	GRUB_CMDLINE_LINUX_DEFAULT="${GRUB_CMDLINE_LINUX_DEFAULT//splash/}"

	sed -i '/GRUB_CMDLINE_LINUX_DEFAULT=/d' /etc/default/grub
	cat >> /etc/default/grub <<-EOF
	GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT"
	EOF
else
	cat >> /etc/default/grub <<-EOF
	GRUB_CMDLINE_LINUX="scsi_mod.use_blk_mq=Y"
	EOF
fi
. /etc/os-release

grub2-mkconfig -o /boot/grub2/grub.cfg
if test -e /boot/efi/EFI/$ID/grub.cfg; then
	grub2-mkconfig -o /boot/efi/EFI/$ID/grub.cfg
fi
