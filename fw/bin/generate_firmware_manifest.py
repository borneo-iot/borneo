#!/usr/bin/env python3
import json
import os
import sys
import shutil
import argparse
import hashlib
import datetime
import gzip

def main():
    parser = argparse.ArgumentParser(description='Generate firmware manifest and copy binary')
    parser.add_argument('base_path', help='The base directory path (e.g., ./borneo/fw/lyfi)')
    parser.add_argument('-o', '--output', help='Output directory (default: ./build)')
    args = parser.parse_args()

    base_dir = args.base_path

    if not os.path.exists(base_dir):
        print(f"Directory {base_dir} does not exist")
        sys.exit(1)

    output_dir = args.output
    if output_dir is None:
        output_dir = os.path.join(base_dir, "build")

    os.makedirs(output_dir, exist_ok=True)

    # Read build/project_description.json and extract project_version
    project_description_file = os.path.join(base_dir, "build", "project_description.json")
    if not os.path.exists(project_description_file):
        print(f"Project description file {project_description_file} does not exist")
        sys.exit(1)

    with open(project_description_file, 'r') as f:
        project_description = json.load(f)

    version = project_description.get("project_version")
    if not version:
        print(f"`project_version` not found in {project_description_file}")
        sys.exit(1)

    # Read sdkconfig.json
    sdkconfig_file = os.path.join(base_dir, "build", "config", "sdkconfig.json")
    if not os.path.exists(sdkconfig_file):
        print(f"SDK config file {sdkconfig_file} does not exist")
        sys.exit(1)

    with open(sdkconfig_file, 'r') as f:
        sdkconfig = json.load(f)

    idf_target = sdkconfig.get("IDF_TARGET")
    product_id = sdkconfig.get("BORNEO_PRODUCT_ID")
    device_name = sdkconfig.get("BORNEO_DEVICE_NAME_DEFAULT")
    board_name = sdkconfig.get("BORNEO_BOARD_NAME")
    vendor = sdkconfig.get("BORNEO_VENDOR_DEFAULT")
    compatible = sdkconfig.get("BORNEO_DEVICE_COMPATIBLE")

    if not idf_target:
        print("`IDF_TARGET` not found in `sdkconfig.json`")
        sys.exit(1)

    if not product_id:
        print("`BORNEO_PRODUCT_ID` not found in `sdkconfig.json`")
        sys.exit(1)

    if not device_name:
        print("`BORNEO_DEVICE_NAME_DEFAULT` not found in `sdkconfig.json`")
        sys.exit(1)

    if not board_name:
        print("`BORNEO_BOARD_NAME` not found in `sdkconfig.json`")
        sys.exit(1)

    if not vendor:
        print("`BORNEO_VENDOR_DEFAULT` not found in `sdkconfig.json`")
        sys.exit(1)

    if not compatible:
        print("`BORNEO_DEVICE_COMPATIBLE` not found in `sdkconfig.json`")
        sys.exit(1)

    # Map IDF_TARGET to chipFamily by extracting ESP32 prefix and adding hyphen
    if idf_target.lower().startswith("esp32"):
        # Extract the part after "esp32" and format it
        suffix = idf_target.lower()[5:]  # Remove "esp32" prefix
        if suffix:
            chip_family = f"ESP32-{suffix.upper()}"
        else:
            chip_family = "ESP32"
    else:
        # Fallback for non-ESP32 targets
        chip_family = idf_target.upper()

    # Source binary
    source_bin = os.path.join(base_dir, "build", "merged-binary.bin")
    if not os.path.exists(source_bin):
        print(f"Source binary {source_bin} does not exist")
        sys.exit(1)

    # Destination binary name
    merged_bin_name = f"{product_id.replace('/', '-')}_firmware_ce_v{version}.bin"
    merged_dest_bin = os.path.join(output_dir, merged_bin_name)

    # Copy the binary
    shutil.copy2(source_bin, merged_dest_bin)
    print(f"Copied {source_bin} to {merged_dest_bin}")

    # Calculate sha256 of the copied binary
    sha256_hash = hashlib.sha256()
    with open(merged_dest_bin, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            sha256_hash.update(chunk)
    merged_binary_sha256 = sha256_hash.hexdigest()
    print(f"SHA256 of {merged_dest_bin}: {merged_binary_sha256}")

    # Handle optional "app" binary which should be compressed and hashed
    app_source = os.path.join(
        base_dir, 'build', f"{product_id.replace('/', '_')}.bin")
    if not os.path.exists(app_source):
        print(f"App binary {app_source} does not exist")
        sys.exit(1)

    ota_filename = f"{product_id.replace('/', '-')}_ota_ce_v{version}.bin.gz"
    ota_dest = os.path.join(output_dir, ota_filename)

    # gzip-compress the app binary
    with open(app_source, "rb") as src, gzip.open(ota_dest, "wb") as dst:
        shutil.copyfileobj(src, dst)
    print(f"Compressed {app_source} to {ota_dest}")

    # Calculate sha256 of the compressed app
    ota_sha256 = hashlib.sha256()
    with open(ota_dest, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            ota_sha256.update(chunk)
    ota_hash = ota_sha256.hexdigest()
    print(f"SHA256 of {ota_dest}: {ota_hash}")

    # Generate manifest
    # timestamp in milliseconds since epoch
    timestamp_ms = int(datetime.datetime.utcnow().timestamp() * 1000)
    # The manifest now includes an optional gzip-compressed "app" binary
    # alongside the merged firmware.  app_path is the filename (relative to
    # output_dir) and app_hash is the SHA256 of the compressed file.

    manifest = {
        "name": device_name,
        "product_id": product_id,
        "board_name": board_name,
        "vendor": vendor,
        "compatible": compatible,
        "version": version,
        "sha256": merged_binary_sha256,
        "ota_filename": ota_filename,
        "ota_sha256": ota_hash,
        "merged_filename": merged_bin_name,
        "timestamp": timestamp_ms,
        "new_install_prompt_erase": True,
        "new_install_improv_wait_time": 0,
        "builds": [
            {
                "chipFamily": chip_family,
                "parts": [
                    {
                        "path": "/firmware/" + merged_bin_name,
                        "offset": 0
                    }
                ]
            }
        ]
    }

    # Manifest file name
    manifest_name = f"{product_id.replace('/', '-')}_firmware_ce_v{version}.manifest.json"
    manifest_file = os.path.join(output_dir, manifest_name)

    with open(manifest_file, 'w') as f:
        json.dump(manifest, f, indent=4)

    print(f"Generated manifest {manifest_file}")

if __name__ == "__main__":
    main()