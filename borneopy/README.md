# borneo.py

A open-source Python client library for devices under the Borneo-IoT Project.

## Features

- Basic device control (power on/off, reboot, factory reset, etc.)
- Device information queries
- Timezone settings
- Firmware upgrade checking
- CoAP OTA firmware updates

## Installation

```bash
pip install -r requirements.txt
```

## Usage Examples

### Basic Device Control

```python
import asyncio
from borneo.lyfi import LyfiCoapClient

async def main():
    async with LyfiCoapClient("coap://192.168.1.100") as device:
        # Get device information
        info = await device.get_info()
        print(f"Device info: {info}")
        
        # Control device power
        await device.set_on_off(True)
        status = await device.get_on_off()
        print(f"Device status: {status}")

if __name__ == "__main__":
    asyncio.run(main())
```

### CoAP OTA Firmware Update

```python
import asyncio
from borneo.lyfi import LyfiCoapClient

async def update_firmware():
    device_url = "coap://192.168.1.100"
    firmware_path = "firmware.bin"
    
    def progress_callback(current, total):
        percent = int((current / total) * 100)
        print(f"Upload progress: {percent}%")
    
    def status_callback(message):
        print(f"Status: {message}")
    
    async with LyfiCoapClient(device_url) as device:
        # Check OTA status
        status = await device.check_ota_status()
        if status['success']:
            print(f"Current partition: {status['current_partition']}")
        
        # Execute OTA update
        result = await device.perform_ota_update(
            firmware_path,
            progress_callback=progress_callback,
            status_callback=status_callback
        )
        
        if result['success']:
            print("Firmware update successful!")
        else:
            print(f"Update failed: {result['error']}")

if __name__ == "__main__":
    asyncio.run(update_firmware())
```

## Command Line Tools

### `bocli` — command-line tool 🔧

`bocli` is the console script provided by this package (see `pyproject.toml`).
Install the package to get the `bocli` command (`pip install -e .`) or run via `uv run bocli`.

Usage:

```text
bocli [global options] <command> [command options]
```

Global options
- `-h, --host`  Device base URL for CoAP commands (e.g. `coap://192.168.1.10`)
- `-v, --verbose`  Increase verbosity (repeatable)
- `-c, --compatible`  Compatibility string (default: `bst,borneo-lyfi`)
- `--version`  Print version and exit

Available commands
- `lota` — perform local OTA over CoAP
  - usage: `bocli -h coap://192.168.1.100 lota firmware.bin [--block-size 512] [--status-only]`
  - note: `fw_path` is required; `--status-only` will only query OTA status and exit
- `mdns` — discover devices via mDNS (e.g. `bocli mdns -t 5` or `bocli mdns --find`)
- `get` — call `get_<what>` on `LyfiCoapClient` and print JSON
  - usage: `bocli -h coap://192.168.1.100 get color`
  - list targets: `bocli -h coap://192.168.1.100 get --list`
- `capabilities` — list available `get_...` methods (supports `--json`)
- `on` / `off` — turn device on / off (e.g. `bocli -h coap://192.168.1.100 on`)
- `factory-reset` — perform factory reset (use `-y` to bypass confirmation)

Examples
```bash
# discover devices with mDNS for 3 seconds
bocli mdns -t 3

# list `get_...` targets supported by the device
bocli -h coap://192.168.1.100 get --list

# get a resource (prints JSON)
bocli -h coap://192.168.1.100 get color

# turn device on
bocli -h coap://192.168.1.100 on

# perform OTA (upload firmware)
bocli -h coap://192.168.1.100 lota firmware.bin
# check OTA status only (fw_path is still required by the CLI)
bocli -h coap://192.168.1.100 lota firmware.bin --status-only
```

See `borneo/cli.py` for full command descriptions and options.

## API Documentation

### CoAP OTA Methods

#### `check_ota_status()`
Check device OTA status.

**Returns:**
```python
{
    'success': bool,
    'current_partition': str,      # Current running partition
    'update_status': str,          # Update status
    'bytes_received': int          # Bytes received
}
```

#### `upload_firmware(firmware_path, progress_callback=None)`
Upload firmware file to device.

**Parameters:**
- `firmware_path`: Path to firmware file
- `progress_callback`: Optional progress callback function `callback(current, total)`

**Returns:**
```python
{
    'success': bool,
    'message': str,
    'next_boot': str,              # Next boot partition
    'checksum': str,               # File checksum
    'size': int                    # File size
}
```

#### `perform_ota_update(firmware_path, progress_callback=None, status_callback=None)`
Execute complete OTA update process.

**Parameters:**
- `firmware_path`: Path to firmware file
- `progress_callback`: Optional progress callback function `callback(current, total)`
- `status_callback`: Optional status callback function `callback(message)`

**Returns:**
```python
{
    'success': bool,
    'message': str,
    'details': dict                # Detailed result information
}
```

## Dependencies

- `aiocoap>=0.4.12` - CoAP protocol support
- `cbor2>=5.9.0` - CBOR data format support
- `aiofiles` - Async file operations

## Packaging & development

This project uses a modern PEP 621 `pyproject.toml` (setuptools backend). Below are common development and packaging commands.

- Build distributions:
  - `python -m build` (uses build backend from `pyproject.toml`)
  - `uv build` (if you use Astral's `uv` tool)

- Create and activate a local virtual environment (Windows):
  - `python -m venv .venv`
  - `.venv/Scripts/activate`

- Install dependencies for development:
  - `pip install -e .`
  - or `uv pip sync` / `uv venv` when using `uv`

- Run an example:
  - `python examples/hello_lyfi.py`

- Publish to PyPI:
  - `uv publish`
  - or `python -m twine upload dist/*`

Notes:
- **License:** `GPL-3.0-or-later` — please add or verify a `LICENSE` file in the repository.
- The project was migrated from `setup.py` to `pyproject.toml`; builds produce both `sdist` and `wheel` artifacts.