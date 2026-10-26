# EqShaders third-party components

EqShaders MVP is an integration package. It does **not** relicense its upstream components into one license.

## Photon-derived ReShade layer

The ReShade post-processing code in `Shaders/EqShaders.fx` and `Shaders/PhotonWoW/` contains maths and behaviour ported from **Photon Shaders v1.3b** by Benjamin Stott (SixthSurge).

The Photon terms distributed with this repository in `PHOTON_LICENSE.txt` continue to apply to that derived shader code. In particular, do not treat the Photon-derived part as GPL merely because EqShaders can run alongside ComfyAtmosphere.

## ComfyAtmosphere

- Project: `aloofbit/comfyatmosphere`
- EqShaders MVP pinned release: `v0.17.1-alpha`
- Pinned upstream commit: `73bebaaf2439aa17cc7766bb99bf8513f9aa6ade`
- License: GPL-3.0

The EqShaders installer downloads the official ComfyAtmosphere release archive from its upstream GitHub release. EqShaders does not vendor or modify the ComfyAtmosphere source or DLL in this MVP.

ComfyAtmosphere remains a separate program loaded by VanillaFixes and is responsible for renderer-level/world-space effects including shadow maps, sun shadows, volumetric lighting, world fog, lamps, water/grass features and time-of-day behaviour.

## ReShade

EqShaders uses ReShade as the post-processing host. ReShade is **not redistributed by this repository**. The MVP currently expects the 32-bit Vulkan ReShade layer to already be installed for the WoW/DXVK process (the tested setup used ReShade 6.8.0 Addon).

## DXVK / World of Warcraft / OctoWoW / VanillaFixes

These are not distributed by EqShaders. Their respective licenses/terms remain separate.

## Why the MVP is structured this way

The goal is one user-facing graphics stack without creating a misleading combined license. The two rendering components stay technically and legally distinct:

`WoW -> ComfyAtmosphere -> DXVK -> Vulkan -> ReShade -> EqShaders`

The installer and preset coordinate them as one EqShaders experience while preserving each upstream component's own licensing and attribution.
