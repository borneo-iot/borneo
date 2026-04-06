# Borneo Firmware - AI Coding Guidelines

## Overview

Borneo Firmware is ESP-IDF based software for ESP32/ESP32-C3 devices, implementing CoAP/CBOR protocols for LED control, sunrise/sunset simulation, and device management.

## Technology Stack

- **Framework**: ESP-IDF (Espressif IoT Development Framework)
- **Language**: C/C++
- **Protocol**: CoAP with CBOR encoding
- **MCU**: ESP32, ESP32-C3, ESP32-C5

## Project Structure

- `components/`: ESP-IDF components
- `cmake/`: Build configuration
- `scripts/`: Build and utility scripts
- `3rd-components/`: Third-party components
- `lyfi/`, `products/`: Device-specific code

## Development Guidelines

### Coding Standards

- Follow ESP-IDF coding conventions
- Use C23 standard, allowing GNU GCC extensions
- Implement error handling with ESP_ERROR_CHECK
- Use logging with ESP_LOG macros

### Building

- Use ESP-IDF build system
- **Do not use `idf.py menuconfig` to modify configuration, as it may break the build system**
- Build with `idf.py -DPRODUCT_D=<PRODUCT_ID> build` (replace `<PRODUCT_ID>` with the actual product ID to ensure correct compilation)
- Flash with `idf.py flash`

### Key Features

- PWM dimming for 6 channels
- CoAP server for remote control
- OTA updates
- Time synchronization
- Cooling control with PID

### Testing

- Use ESP-IDF unit testing framework
- QA testing for production builds

## Contributing

- Ensure code compiles with ESP-IDF
- Test on target hardware
- Document new features in code comments