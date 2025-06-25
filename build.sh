#!/bin/bash

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
    );

dirs=(
    BeebFpga/src/gowin/tang20k
    BeebFpga/src/gowin/tang20k
    ElectronFpga/gowin/ElectronFpga_TangNano20K
    AtomFpga/gowin/AtomFpga_TangNano20K
    );

nextaddrs=(
    00100000
    00200000
    00300000
    00000000
    )

rm -rf build
mkdir build

# Set build to the absolute path of the build directory
build=`pwd`/build

for core in 0 1 2 3
do
    name=${names[$core]}
    dir=${dirs[$core]}
    nextaddr=${nextaddrs[$core]}

    echo "Core 0 = ${name}; flavour = ${flavour}"

    cd ${dir}/${flavour}

    # Patch in the next SPI address
    sed -i "s/\(MULTIBOOT_SPI_FLASH_ADDRESS.*:\).*/\1 \"${nextaddr}\",/" impl/tang20k_process_config.json

    # Patch in the core ID
    sed  -i "s/\(G_CORE_ID.*:=\).*/\1 ${core};/" src/board_config_pack.vhd

    # For the Master core, disable the beeb personality
    if [ "$core" == "0" ]; then
        sed -i "s/\(G_CONFIG_BEEB.*:=\).*/\1 false;/" src/board_config_pack.vhd
    fi

    # For the Beeb core, disable the beeb personality
    if [ "$core" == "1" ]; then
        sed -i "s/\(G_CONFIG_MASTER.*:=\).*/\1 false;/" src/board_config_pack.vhd
    fi

    echo "Local changes:"
    grep MULTIBOOT_SPI_FLASH_ADDRESS impl/tang20k_process_config.json
    grep G_CORE_ID src/board_config_pack.vhd
    if [ "$core" == "0" ]; then
        grep G_CONFIG_BEEB src/board_config_pack.vhd
    fi
    if [ "$core" == "1" ]; then
        grep G_CONFIG_MASTER src/board_config_pack.vhd
    fi

    echo "Calling gw_sh to build the project (this takes a few minutes...)"

    # Build the project
    gw_sh >${build}/${core}.log 2>&1 <<EOF
    open_project tang20k.gprj
    run all
    run close
EOF

    # Copy the bin file
    cp impl/pnr/tang20k.bin ${build}/${core}.bin

    # Revert any local changes
    git clean -f

    cd -
done

# Build ROM images

cd BeebFpga/roms
./make_rom_image_tangnano.sh
cp tmp/tang_image_combined_MMFS.bin ${build}/rom_image_beeb.bin
cd -

cd AtomFpga/roms
./make_ramrom_tang_image.sh
cp 16K_avr.bin ${build}/rom_image_atom.bin

cd ElectronFpga/roms
./make_rom_image.sh
cp tmp/rom_image.bin ${build}/rom_image_electron.bin
cd -

cd build
