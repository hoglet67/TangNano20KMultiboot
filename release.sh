#!/bin/bash -eu

# Before doing anything, check gw_sh is available
type gw_sh >/dev/null 2>&1 || (
    echo "Error: Gowin gw_sh not found on the PATH" >&2;
    exit 1
    )

# Time the build
start=$(date +'%s')

flavours=(
    tang20k_nodebugger_pitube
    tang20k_nodebugger_vga
    tang20k_debugger_pitube
    tang20k_debugger_vga
)

mkdir -p build
mkdir -p releases

for flavour in ${flavours[@]}
do
    ./build.sh ${flavour} |& tee build/${flavour}.log
done

cd build
release=$(date +"%Y%m%d")_$(git rev-parse --short=8 HEAD)
zip -r ../releases/${release}.zip */multiboot_cores_and_roms.bin
cd ..

end=$(date +'%s')
echo "Build time: $(($end - $start)) seconds"
