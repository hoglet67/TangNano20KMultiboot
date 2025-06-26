#!/bin/bash -e

flavour=tang20k_nodebugger_pitube

# Core 0 - BeebFpga (Master)
# Core 1 - BeebFpga (Beeb)
# Core 2 - ElectronFpga
# Core 3 - AtomFPGA

names=(
    Master
    Beeb
    Electron
    Atom
)

dirs=(
    BeebFpga/src/gowin/tang20k
    BeebFpga/src/gowin/tang20k
    ElectronFpga/gowin/ElectronFpga_TangNano20K
    AtomFpga/gowin/AtomFpga_TangNano20K
)

root_paths=(
    ../../../../..
    ../../../../..
    ../../../..
    ../../../..
)

nextaddrs=(
    00100000
    00200000
    00300000
    00000000
)

mkdir -p build
rm -rf build/*

# Set build to the absolute path of the build directory
build=`pwd`/build

######################################################
# Build ROM images
######################################################

# 512KB
cd BeebFpga/roms
./make_rom_image_tangnano.sh >> ${build}/roms.log
cp tmp/tang_image_combined_MMFS.bin ${build}/rom_image_beeb.bin
git clean -f -q
cd ../..

# 256KB
cd AtomFpga/roms
./make_ramrom_tang_image.sh >> ${build}/roms.log
cp 16K_avr.bin ${build}/rom_image_atom.bin
git clean -f -q
cd ../..

# 256KB
cd ElectronFpga/roms
./make_rom_image.sh >> ${build}/roms.log
cp tmp/rom_image.bin ${build}/rom_image_electron.bin
git clean -f -q
cd ../..

######################################################
# Build Cores
######################################################

for core in 0 1 2 3
do
    name=${names[$core]}
    dir=${dirs[$core]}
    nextaddr=${nextaddrs[$core]}
    root_path=${root_paths[$core]}

    echo "Core ${core} = ${name}; flavour = ${flavour}"

    cd ${dir}/${flavour}

    # Patch in local source for multiboot.vhd
    sed -i "s#path=\".*multiboot.vhd#path=\"${root_path}/src/multiboot.vhd#" tang20k.gprj

    # Patch in the next SPI address
    sed -i "s/\(MULTIBOOT_SPI_FLASH_ADDRESS.*:\).*/\1 \"${nextaddr}\",/" impl/tang20k_process_config.json

    # Patch in a 25MHz SPI clock speed
    sed -i "s/\(DOWNLOAD_SPEED.*:\).*/\1 \"250\/10\",/" impl/tang20k_process_config.json

    # Patch in the core ID
    sed  -i "s/\(G_CORE_ID.*:=\).*/\1 ${core};/" src/board_config_pack.vhd

    # For the Master core, disable the beeb personality
    if [ "$core" == "0" ]; then
        sed -i "s/\(G_CONFIG_BEEB.*:=\).*/\1 false;/" src/board_config_pack.vhd
    fi

    # For the Beeb core, disable the beeb personality
    if [ "$core" == "1" ]; then
        sed -i "s/\(G_CONFIG_MASTER.*:=\).*/\1 false;/" src/board_config_pack.vhd
        sed -i "s/set_false_path.*m128_mode.*//" src/board_timings.sdc
    fi

    echo "Local changes:"
    git diff | grep "^+ "

    echo "Calling gw_sh to build the project (this takes a few minutes...)"

    # Clean the pnr directory to make sure no stale files
    rm -rf impl/pnr
    
    # Build the project
    gw_sh >${build}/${core}.log 2>&1 <<EOF
    open_project tang20k.gprj
    run all
    run close
EOF

    # Copy the bin and fs files
    cp impl/pnr/tang20k.fs ${build}/${core}.fs
    cp impl/pnr/tang20k.bin ${build}/${core}.bin
    chmod 644 ${build}/${core}.fs
    chmod 644 ${build}/${core}.bin
    truncate -s 1M ${build}/${core}.bin

    # Revert any local changes
    git checkout -q .
    git clean -f -q

    echo "build successful"
    echo

    cd ${root_path}
    
done

# Build the final multiboot images

cd build
truncate -s 1M  pad1
truncate -s 64K pad2
truncate -s 176K pad3

cat 0.bin 1.bin 2.bin 3.bin > multiboot_cores.bin
cat multiboot_cores.bin pad1 rom_image_beeb.bin pad2 rom_image_atom.bin pad3 rom_image_electron.bin > multiboot_cores_and_roms.bin

rm -f pad1 pad2 pad3
cd -

ls -l build
