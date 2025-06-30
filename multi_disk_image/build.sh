#!/bin/bash -e

# This script builds a 2GB(ish) SD Card image for use with TangNano20KMultiboot
#
# In contains two partitions
# - a 800MB FAT32 partition containing
#     - a 2-extent MMB file (Beeb then Elk)
#     - the Atom Software Archive
# - a 1023MB ADFS partition containing
#     - DOS Plus 2.1
#     - Panos 1.4
#
# The resultant image should compress well
#
# This script is not really intended to be portable!
#
# It does loopback mounting so needs root access at one point
#
# The following are needed on the part
#    sfdisk
#    beeb from https://github.com/sweharris/MMB_Utils
#    afscp/scsi2ide from https://github.com/SteveFosdick/AcornFsUtils

ASA_ZIP=AtomSoftwareArchive_20240505_1129_V13.00.zip
ASA_URL=https://github.com/hoglet67/AtomSoftwareArchive/releases/download/V13_00/${ASA_ZIP}

ELK_MMB_ZIP=elkbig.zip
ELK_MMB_URL=http://ramtop-retro.uk/files/${ELK_MMB_ZIP}

BEEB_MMB_ZIP=BEEB.MMB.zip
BEEB_MMB_URL=https://github.com/hoglet67/BeebFpga/releases/download/specnext_beta1/${BEEB_MMB_ZIP}

BLANK_ADFS_ZIP=BeebSCSI_Quickstart_LUN_2_5.zip
BLANK_ADFS_URL=https://github.com/simoninns/BeebSCSI/raw/refs/heads/master/support/${BLANK_ADFS_ZIP}
BLANK_ADFS_PATH=BeebSCSI_Quickstart_LUN_2_5/BeebSCSI_Quickstart_LUN/BeebSCSI0/scsi0.dat

#Disk multi.img: 1.8 GiB, 1913348096 bytes, 3737008 sectors
#Units: sectors of 1 * 512 = 512 bytes
#Sector size (logical/physical): 512 bytes / 512 bytes
#I/O size (minimum/optimal): 512 bytes / 512 bytes
#Disklabel type: dos
#Disk identifier: 0xebc4a2d1
#
#Device     Boot   Start     End Sectors    Size Id Type
#multi.img1         2048 1640447 1638400    800M  c W95 FAT32 (LBA)
#multi.img2      1640448 3737007 2096560 1023.7M ad unknown

mkdir -p build
cd build

echo "Downloading archive URLs"

wget -N --quiet ${ASA_URL}

wget -N --quiet ${ELK_MMB_URL}
unzip -q -o ${ELK_MMB_ZIP}
mv BEEB.MMB ELK.MMB

wget -N --quiet ${BEEB_MMB_URL}
unzip -q -o ${BEEB_MMB_ZIP}

wget -N --quiet ${BLANK_ADFS_URL}

##################################################################
# Make partion 1 - 800MB FAT32
##################################################################

echo "Merging BEEB.MMB and ELK.MMB into a 2-extent MMB file"
rm -f MERGED.MMB
beeb dmerge_mmb -f MERGED.MMB BEEB.MMB ELK.MMB

echo "Formatting 800MB FAT32 partition"
mkdir -p partition1
rm -f partition1.img
truncate -s $((1638400*512)) partition1.img
mkfs.vfat -n MMFS partition1.img

# Note: Fuse appeared to work, but MMFS gave an Image not found! error
#fusefat partition1.img partition1 -o rw+
#cp MERGED.MMB partition1/BEEB.MMB
#ls -l partition1
#fusermount -u partition1

echo "Mounting FAT32 partition (root access requires)"
sudo mount partition1.img partition1 -t vfat -o loop
echo "Copying files to FAT32 partition"
sudo cp MERGED.MMB partition1/BEEB.MMB
sudo unzip -q -o -d partition1 ${ASA_ZIP}
echo "Unmounting FAT32 partition"
sudo umount partition1

rm -rf partition1

##################################################################
# Make partion 2 - 511MB (x2 as it's IDE 16-bit format) ADFS
##################################################################

rm -f partition2.img

#echo "Unpacking 512MB ADFS partition"
#7z e ../partition2.7z > /dev/null

echo "Formatting 512MB ADFS partition"
rm -rf scsi0
mkdir -p scsi0
unzip -d scsi0 -o -a -q ${BLANK_ADFS_ZIP}
cp scsi0/${BLANK_ADFS_PATH} partition2.dat
rm -rf scsi0

echo "Copying files to ADFS partition"
afscp -r ../adfs_files/* partition2.dat:

echo "Converting from 8-bit to 16-bit format"
scsi2ide partition2.dat partition2.img

##################################################################
# Make multi disk image
##################################################################

echo "Making multi disk image"
rm -f multi.img
truncate -s $((3737008*512)) multi.img
sfdisk multi.img <<EOF > /dev/null 2>&1
label: dos
label-id: 0xebc4a2d1
device: multi.img
unit: sectors

multi.img1 : start=        2048, size=     1638400, type=c
multi.img2 : start=     1640448, size=     2096560, type=ad
EOF

# Now truncate it to the end of the partition table
truncate -s $((2048*512)) multi.img

# Assemble the final image
cat multi.img partition1.img partition2.img > multi_disk_image.img
ls -l multi_disk_image.img
fdisk -l multi_disk_image.img
