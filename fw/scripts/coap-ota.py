#!/usr/bin/env python3
import asyncio
import os
import hashlib
from aiocoap import Context, Message, Code
from aiocoap.numbers.constants import MAX_REGULAR_BLOCK_SIZE_EXP
from aiocoap.numbers.optionnumbers import OptionNumber
import cbor2
import aiofiles
from urllib.parse import urljoin
import traceback
import argparse

class CoAPFirmwareUpdater:
    def __init__(self, target_url, firmware_path, block_size=128):
        self.target_url = target_url
        self.firmware_path = firmware_path
        self.block_size = block_size
        self.block_exp = self._calculate_block_exp(block_size)

    def _calculate_block_exp(self, size):
        """Convert block size to CoAP SZX exponent"""
        szx_map = {16: 0, 32: 1, 64: 2, 128: 3, 256: 4, 512: 5, 1024: 6}
        if size not in szx_map:
            raise ValueError(f"Unsupported block size: {size}")
        return szx_map[size]

    async def _calculate_file_checksum(self):
        """Calculate SHA256 checksum of the file"""
        sha256 = hashlib.sha256()
        async with aiofiles.open(self.firmware_path, 'rb') as f:
            while True:
                data = await f.read(65536)  # 64KB chunks
                if not data:
                    break
                sha256.update(data)
        return sha256

    async def check_server_status(self, context):
        """Check server status"""
        uri = urljoin(self.target_url, "/borneo/v1/ota/coap/status")
        print(f"Checking server status: {uri}")
        request = Message(code=Code.GET, uri=uri)
        try:
            response = await context.request(request).response
            if response.code.is_successful():
                status = cbor2.loads(response.payload)
                print("\nServer status:")
                print(f"Current partition: {status.get('running_partition', 'unknown')}")
                print(f"Update status: {status.get('update_status', 'unknown')}")
                print(f"Bytes received: {status.get('bytes_received', 0)}")
                return True
            else:
                print(f"Status check failed: {response.code}")
                return False
        except Exception as e:
            print(f"Status check error: {str(e)}")
            return False

    async def send_firmware(self):
        """Send firmware file (loaded into memory at once)"""
        if not os.path.exists(self.firmware_path):
            print(f"Error: Firmware file {self.firmware_path} does not exist")
            return False

        file_size = os.path.getsize(self.firmware_path)
        sha256 = await self._calculate_file_checksum()
        file_checksum = sha256.digest()

        print(f"Preparing to send firmware:")
        print(f"Path: {self.firmware_path}")
        print(f"Size: {file_size} bytes")
        print(f"SHA256: {sha256.hexdigest()}")

        # Create CoAP context
        context = await Context.create_client_context()

        # Read entire firmware file
        async with aiofiles.open(self.firmware_path, 'rb') as f:
            firmware_data = await f.read()

        # Create CoAP PUT request
        uri = urljoin(self.target_url, "/borneo/v1/ota/coap/download")
        request = Message(code=Code.PUT, uri=uri, payload=firmware_data)
        request.remote.maximum_block_size_exp = 5  # 1024 bytes

        try:
            # Send request and wait for response
            response = await context.request(request).response

            # Process server response
            if response.code.is_successful():
                print("Firmware upload successful!")

                # Send POST request to complete update
                post_payload = cbor2.dumps({
                    "checksum": file_checksum,
                })
                request = Message(code=Code.POST, payload=post_payload, uri=uri)
                try:
                    response = await context.request(request).response
                    if response.code.is_successful():
                        result = cbor2.loads(response.payload)
                        print("Firmware update successfully triggered!")
                        print(
                            f"Next boot partition: {result.get('next_boot', 'unknown')}")
                        return True
                    else:
                        print(f"Update trigger failed: {response.code}")
                        return False
                except Exception as e:
                    print(f"Error triggering update: {str(e)}")
                    return False

                return True
            else:
                print(f"Upload failed, server returned code: {response.code}")
                return False
        except Exception as e:
            print(f"Request failed: {e}")
            return False
        finally:
            try:
                await context.shutdown()
            except Exception as e:
                print(f"Warning: Failed to shutdown CoAP context cleanly: {e}")
                print(
                    "This is likely a known aiocoap library issue and does not affect the OTA success.")

async def main(args):
    # Configuration parameters
    BLOCK_SIZE = 512

    updater = CoAPFirmwareUpdater(args.url, args.fw_path, BLOCK_SIZE)
    success = await updater.send_firmware()

    if success:
        print("\nFirmware update process completed, device should reboot automatically with new firmware")
    else:
        print("\nFirmware update failed")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
                    prog='bo-coap-ota.py',
                    description='Borneo-IoT OTA over CoAP Utility')
    parser.add_argument("url", help="The URL to Device address, e.g.: `coap://192.168.1.10`")
    parser.add_argument("fw_path", help="The `.bin` file path of the firmware to process")
    args = parser.parse_args()
    asyncio.run(main(args))
