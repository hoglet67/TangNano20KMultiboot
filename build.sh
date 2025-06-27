#!/bin/bash

# Kill child processes on ^C
trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT

# Core 0 - BeebFpga (Master)
# Core 1 - BeebFpga (Beeb)
# Core 2 - ElectronFpga
# Core 3 - AtomFPGA


flavours=(
    tang20k_nodebugger_pitube
    tang20k_nodebugger_vga
    tang20k_debugger_pitube
    tang20k_debugger_vga
)

names=(
    Master
    Beeb
    Electron
    Atom
)

dirs=(
    BeebFpga/src/gowin/tang20k
    MasterFpga/src/gowin/tang20k
    ElectronFpga/gowin/ElectronFpga_TangNano20K
    AtomFpga/gowin/AtomFpga_TangNano20K
)

roots=(
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

######################################################
# Compile Core background function
######################################################

compile_core () {

    flavour=$1
    core=$2

    name=${names[${core}]}
    dir=${dirs[${core}]}
    nextaddr=${nextaddrs[${core}]}
    root=${roots[${core}]}
    target=${root}/${build}/${core}

    echo "Flavour ${flavour}: Core ${core}: Starting build of ${name} core"

    cd ${dir}/${flavour}

    # Make sure the subproject is clean
    git checkout -q .
    git clean -f -q .

    # Patch in local source for multiboot.vhd
    sed -i "s#path=\".*multiboot.vhd#path=\"${root}/src/multiboot.vhd#" tang20k.gprj

    # Patch in the next SPI address
    sed -i "s/\(MULTIBOOT_SPI_FLASH_ADDRESS.*:\).*/\1 \"${nextaddr}\",/" impl/tang20k_process_config.json

    # Patch in a 41.666 SPI clock speed
    sed -i "s/\(DOWNLOAD_SPEED.*:\).*/\1 \"250\/6\",/" impl/tang20k_process_config.json

    # Patch in the core ID
    sed  -i "s/\(G_CORE_ID.*:=\).*/\1 ${core};/" src/board_config_pack.vhd

    # For the Master core, disable the beeb personality
    if [ "${core}" == "0" ]; then
        sed -i "s/\(G_CONFIG_BEEB.*:=\).*/\1 false;/" src/board_config_pack.vhd
    fi

    # For the Beeb core, disable the beeb personality
    if [ "${core}" == "1" ]; then
        sed -i "s/\(G_CONFIG_MASTER.*:=\).*/\1 false;/" src/board_config_pack.vhd
        sed -i "s/set_false_path.*m128_mode.*//" src/board_timings.sdc
    fi

    echo "Flavour ${flavour}: Core ${core}: Local changes:"
    git diff . | grep "^+ "

    echo "Flavour ${flavour}: Core ${core}: Calling Gowin gw_sh (this takes a few minutes...)"

    # Clean the pnr directory to make sure no stale files
    rm -rf impl/pnr

    # Build the project
    gw_sh >${target}.log 2>&1 <<EOF
    open_project tang20k.gprj
    run all
    run close
EOF

    echo "Flavour ${flavour}: Core ${core}: Ending build of ${name} core"

    # Note, I couldn't find a way to return a value from run_all
    # (try/trap didn't seem to work), so instead just check for the
    # bitstream files

    if [[ -f impl/pnr/tang20k.fs && impl/pnr/tang20k.bin ]]; then
        echo "Flavour ${flavour}: Core ${core}: Build successful"
        ret=0
        # Copy the bin and fs files
        cp impl/pnr/tang20k.fs ${target}.fs
        cp impl/pnr/tang20k.bin ${target}.bin
        chmod 644 ${target}.fs
        chmod 644 ${target}.bin
        truncate -s 1M ${target}.bin
    else
        echo "Flavour ${flavour}: Core ${core}: Build failed"
        ret=1
    fi

    # Revert any local changes
    git checkout -q .
    git clean -f -q .

    cd ${root}
    return ${ret}
}

######################################################
# Main program
######################################################

# Allow flavour to be passed in as a positional argument
if [[ "$1" != "" ]]; then
    flavour=$1
else
    flavour=tang20k_nodebugger_pitube
fi

if [[ ${flavours[@]} =~ "${flavour}" ]]; then
    echo "Building multiboot core for flavour: ${flavour}"
else
    echo "Unknown flavour: ${flavour}, supported flavours are:" >&2
    echo "${flavours[@]}" | tr " " "\n" >&2
    exit 1
fi

# Before doing anthing, check gw_sh is available
type gw_sh >/dev/null 2>&1
if [[ "$?" != "0" ]]; then
    echo "Gowin gw_sh not found on the PATH" >&2
    exit 1
fi

build=build/${flavour}

mkdir -p ${build}
rm -rf ${build}/*

######################################################
# Build ROM images
######################################################

root=../..

# 512KB
cd BeebFpga/roms
./make_rom_image_tangnano.sh >> ${root}/${build}/roms.log
cp tmp/tang_image_combined_MMFS.bin ${root}/${build}/rom_image_beeb.bin
cd ${root}

# 256KB
cd AtomFpga/roms
./make_ramrom_tang_image.sh >> ${root}/${build}/roms.log
cp 16K_avr.bin ${root}/${build}/rom_image_atom.bin
cd ${root}

# 256KB
cd ElectronFpga/roms
./make_rom_image.sh >> ${root}/${build}/roms.log
cp tmp/rom_image.bin ${root}/${build}/rom_image_electron.bin
cd ${root}

######################################################
# Build Cores
######################################################

# Time the build
start=$(date +'%s')

echo "Flavour ${flavour}: Started"

for core in 0 1 2 3
do
    compile_core ${flavour} ${core} &
    pid[${core}]=$!
    sleep 2
done

echo "Flavour ${flavour}: Waiting for background tasks to complete"...

# This pattern will work, regardless of the order in which the child processes exit
for core in 0 1 2 3
do
    wait ${pid[${core}]}
    ret[${core}]=$?
done

end=$(date +'%s')

echo "Flavour ${flavour}: Ended - build time $(($end - $start))s - results: ${ret[@]}"

if [[ "${ret[0]}" != "0" || "${ret[1]}" != "0" || "${ret[2]}" != "0" || "${ret[3]}" != "0" ]]; then

    echo "Flavour ${flavour}: Build failed - not compiling multiboot image"

    exit 1

else

    echo "Flavour ${flavour}: Build succeeded - compiling multiboot image"

    cd ${build}
    truncate -s 64K  pad1
    truncate -s 176K pad2
    truncate -s 1M   pad3

    cat 0.bin 1.bin 2.bin 3.bin \
        > multiboot_cores.bin

    cat rom_image_beeb.bin pad1 rom_image_atom.bin pad2 rom_image_electron.bin \
        > multiboot_roms.bin

    cat multiboot_cores.bin pad3 multiboot_roms.bin \
        > multiboot_cores_and_roms.bin

    rm -f pad1 pad2 pad3

    cd ../..

    ls -l ${build}

    exit 0

fi
