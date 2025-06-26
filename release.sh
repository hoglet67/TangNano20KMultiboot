#!/bin/bash

trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT

flavours=(
    tang20k_nodebugger_pitube
    tang20k_nodebugger_vga
    tang20k_debugger_pitube
    tang20k_debugger_vga
)

mkdir -p build

for flavour in ${flavours[@]}
do
    echo "Building ${flavour} in the background..."
    ./build.sh ${flavour} > build/${flavour}.log 2>&1 &
    sleep 5
done

echo "Waiting for background tasks to complete"...
wait $(jobs -p)

cd build
release=$(date +"%Y%m%d")_$(git rev-parse --short=8 HEAD)
zip -r ../releases/${release}.zip */multiboot_cores_and_roms.bin
cd ..
