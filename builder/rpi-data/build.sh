#!/bin/bash
set -ex
# this script should be run only inside of a Docker container
if [ ! -f /.dockerenv ]; then
  echo "ERROR: script works only in a Docker container!"
  exit 1
fi

### setting up some important variables to control the build process
BUILD_RESULT_PATH="/workspace"
IMAGE_PATH="rpi-raw-data.img"
SD_CARD_SIZE=7000 # MB
BOOT_PARTITION_SIZE=100 
ROOT_PARTITION_SIZE=4000 # MB

# create empty BOOT/ROOTFS image file
# - SD_CARD_SIZE in MByte
# - DD uses 256 Bytes
# - sector block size is 512Bytes
# - MBR size is 512 Bytes, so we start at sector 2048 (1MByte reserved space)
BOOTFS_START=2048
BOOTFS_SIZE=$((BOOT_PARTITION_SIZE * 2048))

ROOTFS_START=$((BOOTFS_SIZE + BOOTFS_START))
ROOTFS_SIZE=$((ROOT_PARTITION_SIZE * 1024 * 1024 / 512))

DATAFS_START=$((ROOTFS_START + ROOTFS_SIZE))
SD_MINUS_DD=$((SD_CARD_SIZE * 1024 * 1024 - 256))
DATAFS_SIZE=$((SD_MINUS_DD / 512 - DATAFS_START))

dd if=/dev/zero of=${IMAGE_PATH} bs=1MiB count=${SD_CARD_SIZE}
# ls
# give some time to system to refresh
sleep 3

DEVICE=$(losetup -f --show ${IMAGE_PATH})

echo "Image ${IMAGE_PATH} created and mounted as ${DEVICE}."

# create partions
sfdisk --force "${DEVICE}" <<PARTITION
unit: sectors

/dev/loop0p1 : start= ${BOOTFS_START}, size= ${BOOTFS_SIZE}, Id= c, bootable
/dev/loop0p2 : start= ${ROOTFS_START}, size= ${ROOTFS_SIZE}, Id=83
/dev/loop0p3 : start= ${DATAFS_START}, size= ${DATAFS_SIZE}, Id=83
/dev/loop0p4 : start= 0, size= 0, Id= 0
/dev/loop0p5 : start= 0, size= 0, Id= 0
PARTITION

losetup -d "${DEVICE}"
DEVICE=$(kpartx -va ${IMAGE_PATH} | head -1 | grep -Eo 'loop[0-9]+') # prev sed has problems on ubuntu
dmsetup --noudevsync mknodes
BOOTP="/dev/mapper/${DEVICE}p1"
ROOTP="/dev/mapper/${DEVICE}p2"
DATAP="/dev/mapper/${DEVICE}p3"
DEVICE="/dev/${DEVICE}"

# give some time to system to refresh
sleep 3

# create file systems
mkfs.vfat "${BOOTP}" -n HypriotOS
mkfs.ext4 "${ROOTP}" -L root -i 4096 # create 1 inode per 4kByte block (maximum ratio is 1 per 1kByte)
mkfs.ext4 "${DATAP}" -L data -i 4096 # create 1 inode per 4kByte block (maximum ratio is 1 per 1kByte)

echo "### remove dev mapper devices for image partitions"
kpartx -vds ${IMAGE_PATH} || true

# ensure that the travis-ci user can access the sd-card image file
umask 0000

# compress image
zip "${BUILD_RESULT_PATH}/${IMAGE_PATH}.zip" "${IMAGE_PATH}"
sleep 2
cd ${BUILD_RESULT_PATH} && sha256sum "${IMAGE_PATH}.zip" > "${IMAGE_PATH}.zip.sha256" && cd -

fdisk -l /${IMAGE_PATH}
# test raw image that we have built
rspec --format documentation --color /builder/rpi-data/test
