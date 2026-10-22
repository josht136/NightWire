# Nightwire for iOS

SwiftUI app for iPhone and iPad. It shows the same adapter details as the Mac details window: IP, CIDR, MAC, link speed, gateway, DNS, subnet, and public IP, plus Wi-Fi fields when the selected interface is Wi-Fi. Neighbors are the ARP entries on that interface.

There is no ping chart.

## Run

Open `Nightwire.xcodeproj`, choose your team under Signing, and run it on a device. A USB-C or Lightning Ethernet adapter is the interesting case; the simulator has no dongle.

```bash
xcodebuild -scheme Nightwire -destination 'platform=iOS Simulator,name=iPhone 16' -derivedDataPath build test
```

`project.yml` is the XcodeGen spec if you want to regenerate the project.

## Interface

The menu lists USB Ethernet, Wi-Fi, and cellular. **Automatic** is the default. While it is selected, a plugged-in USB Ethernet adapter (iOS reports these as wired Ethernet) is chosen ahead of Wi-Fi and cellular, including before it has an IPv4 address. Pin another interface from the menu and that choice is remembered. If the pinned adapter is unplugged, Nightwire shows another interface until it returns.

## What iOS will not fill in

- **Channel, band, and radio** are not available from public iOS APIs. Those rows stay on a Wi-Fi interface and read Unavailable.
- **SSID, BSSID, and signal** need Location permission and the Access Wi-Fi Information capability (`com.apple.developer.networking.wifi-info` in `Nightwire.entitlements`). Enable that capability on the App ID. If signing fails because the profile does not include it, remove the key to ship the rest of the screen without Wi-Fi names.
- **DHCP versus static, the DHCP lease, and service order** are not available from public iOS APIs. The config badge stays "—" and those rows stay hidden. The layout still includes them when a value is known.
- **DNS** for the default interface comes from the system resolver. Other interfaces do not inherit that list, so a non-default adapter does not show the wrong network's servers.
- **MAC addresses** are often redacted for Wi-Fi. A USB Ethernet adapter's address is shown when the kernel provides it.
- **Public IP** is read through the selected interface via `api.ipify.org`. If that interface has no route, the row says Unavailable instead of showing another network's address.
- **Neighbors** come from the IPv4 routing table. If iOS refuses the read, the section says the ARP table is unavailable.
