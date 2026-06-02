# BorneoIoT: Professional Aquarium Lighting Platform

[![Firmware Build Status](https://github.com/borneo-iot/borneo/actions/workflows/fw-ci.yml/badge.svg)](https://github.com/borneo-iot/borneo/actions/workflows/fw-ci.yml)
[![Firmware Release Status](https://github.com/borneo-iot/borneo/actions/workflows/fw-release.yml/badge.svg)](https://github.com/borneo-iot/borneo/actions/workflows/fw-release.yml)
[![App Build Status](https://github.com/borneo-iot/borneo/actions/workflows/flutter-ci.yml/badge.svg)](https://github.com/borneo-iot/borneo/actions/workflows/flutter-ci)
[![Hardware: OSHWA Certified](https://img.shields.io/badge/Hardware-OSHWA%20CN000017-green)](https://certification.oshwa.org/cn000017.html)
[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue)](LICENSE)
[![License: CERN-OHL-S-2.0](https://img.shields.io/badge/Hardware%20License-CERN--OHL--S--2.0-lightgrey)](LICENSE-HARDWARE)


![BorneoIoT Banner](assets/borneo-repo-banner.jpg)

<p align="center">
<a href="https://www.borneoiot.com"><b>Website</b></a> •
<a href="https://docs.borneoiot.com"><b>Documentation</b></a> •
<a href="https://github.com/borneo-iot/borneo/discussions"><b>Forum</b></a> •
<a href="https://discord.gg/EFJTm7PpEs"><b>Discord</b></a> 
</p>


<p align="center">
<a href="https://www.crowdsupply.com/borneo-iot/buce-aquarium-led-controller" target="_blank" rel="noopener">
<img alt="Crowd Supply: Subscribe" src="https://img.shields.io/badge/Subscribe-Crowd%20Supply-009999?style=for-the-badge&logo=crowdsupply" />
</a>
<a href="https://flasher.borneoiot.com">
<img src="https://img.shields.io/badge/⚡%20Flash%20Firmware-Web%20Flasher-blue?style=for-the-badge" alt="Web Flasher" />
</a>


</p>

<p align="center">
    <a href="https://apps.apple.com/us/app/borneo-aqua-pro/id6759588830" target="_blank" rel="noopener">
        <img alt="Download on App Store" src="assets/download-on-the-app-store.svg" style="height: 60px;" />
    </a>
</p>

If you would like to support this project, please consider purchasing a ready-to-use, pre-tested, pre-loaded firmware product from PCBWay Store: 

<a href="https://www.pcbway.com/project/gifts_detail/6_Channel_Wi_Fi_PWM_LED_Dimmer_for_Aquariums_adb134c9.html">
<img src="https://img.shields.io/badge/PCBWay-00a563?style=for-the-badge&logo=cart" alt="Get It on PCBWay" />
</a>

---

> **Production-grade open-source stack for aquarium LED dimmers.**
> Hardware designs, embedded firmware, and mobile controls. Ready for weekend builds or product integration.

This project delivers a full-stack solution for smart aquarium LED:

1.  **Hardware**: Certified open-source PCB designs targeting the ESP32 family, featuring 6-channel PWM dimming and modular architecture.
2.  **Firmware**: A robust ESP-IDF based firmware implementing CoAP/CBOR protocols, sunrise/sunset simulation, and cooling control.
3.  **Mobile App**: A cross-platform Flutter application for intuitive real-time control, scheduling, and device management.

## Quick Start

**New users:** Follow the **[step-by-step guide](https://docs.borneoiot.com/getting-started/quick-start.html)** to flash firmware and connect your first device.

**No toolchain required**, flash directly from Chrome/Edge Browser:

1. Connect ESP32/ESP32-C3/ESP32-C5 via USB
2. Visit **[flasher.borneoiot.com](https://flasher.borneoiot.com)**
3. Download the app and power on

[Full Getting Started Guide](https://docs.borneoiot.com/getting-started)

## Features

### Hardware

- **6 or 10 PWM channels**, 12-bit resolution (4096 steps), up to 19kHz
- **Flicker-free**, suitable for aquarium photography
- **22×30mm core module**, fits slim LED fixtures
- ESP32-C3/C5 native, WiFi + Bluetooth LE

[Schematics & BoM](hw/)

![Ulva-6](assets/ulva6.jpg)

### Firmware

- **Sunrise/sunset curves** with millisecond-smooth transitions
- **SNTP time sync**: automatic, no manual adjustment
- **Active cooling control**: temperature-based fan/PWM throttling
- **OTA updates**: over-the-air firmware upgrades
- **CoAP + CBOR protocol**: efficient, low-latency device communication

[Source code](fw/) • [Protocol docs](https://docs.borneoiot.com/protocol)

### Mobile App

- **Cross-platform**: iOS, Android, Windows, built with Flutter
- **Real-time control**: dimming, scheduling, scene presets
- **Multi-device**: group control, cloud-free local network
- **Developer API**: Python client for automation

[App source](client/) • [Python SDK](borneopy/)

## Repository Guide

| Directory | Contents | Entry Point |
|-----------|----------|-------------|
| [`hw/`](hw/) | PCB designs (Horizon EDA), Gerbers, 3D models | [`hw/README.md`](hw/) |
| [`fw/`](fw/) | ESP-IDF firmware, CoAP protocol | [`fw/README.md`](fw/) |
| [`client/`](client/) | Flutter mobile app | [`client/README.md`](client/) |
| [`borneopy/`](borneopy/) | Python client library | [`borneopy/README.md`](borneopy/) |

## Getting Started

- **New Users**: Check out our [**Quick Start Guide**](https://docs.borneoiot.com/getting-started/quick-start.html).
- If you are a new user looking to quickly experience our firmware, you can directly use our web firmware flasher to flash the latest version of the firmware to your ESP32 series development board: https://flasher.borneoiot.com/
- **Hardware**: Find schematics and BoM files in the [`hw/`](hw/) directory.
- **Firmware**: Compilation instructions are available in the [`fw/`](fw/) folder.

## Project Status

| Component | Status | Details |
| :--- | :--- | :--- |
| **Hardware** | Stable | Production-ready, OSHWA certified. |
| **Firmware** | Beta | Full-featured and stable on my personal tanks for years. |
| **Mobile App** | Beta | Core functionality working. |

## Roadmap

Check our [milestones](https://github.com/borneo-iot/borneo/milestones) for the latest development updates and upcoming features.

## Community & Support

- **Website**: [www.borneoiot.com](https://www.borneoiot.com)
- **Documentation**: [docs.borneoiot.com](https://docs.borneoiot.com)
- **Discussions**: [Join the Conversation](https://github.com/borneo-iot/borneo/discussions)
- **Discord**: [Connect with Developers](https://discord.gg/EFJTm7PpEs)
- **Email**: [info@binarystarstech.com](mailto:info@binarystarstech.com)

## Licenses

- **Software/Firmware**: Dual-licensed under [**GPL-3.0+**](LICENSE) and Enterprise licenses.
- **Hardware**: Licensed under [**CERN-OHL-S-2.0**](LICENSE-HARDWARE).

---

Copyright © 2025-TODAY [Yunnan BinaryStars Technologies, Co., Ltd.](https://www.binarystarstech.com/en) All rights reserved.

The hardware, firmware, and App for this project were all created by: Wei Li（李维）.
