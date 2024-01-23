# Open Chip Operating System
(aka OpenChip/OpenCOS)

Main Documentation is [here](docs/README.md)

## An open framework for creating chips

Documentation right now is basically RTFC, contact netchipguy@gmail.com for info.

The philosophy behind OpenCOS is to try to emulate the path set by modern operating systems, separating the management of hardware ("kernel space" in Linux lingo) from the application ("user space" in the Linux lingo).  OpenChip can be thought of as the "kernel".

The main pain points that OpenCOS aims to address are:

- the tricky work of full-chip integration (`oc_top` being the OpenCOS equivalent of an OS kernel and board support package)
- the lack of a standard high-quality hardware library (`oclib_*` being the OpenCOS equivalent of glibc)
- a pleasing development environment that isolates user from the peculiarities of the closed-source nature of most hardware development (`eda` wrapper)
- a methodology to support embedding timing knowledge into RTL code (OpenCOS uses "attributes" which are acted upon via EDA tool TCL, versus relying only on SDC-type "side files" that must be maintained to match the RTL, which itself maybe highly modular and parameterizable)

### Chip Manufacturers
Chip manufacturers such as FPGA vendors (Xilinx, etc) and ASIC vendors (Broadcom, etc) can port OpenCOS to one or more "targets", including whatever IPs they desire.  The target (such as `u55n`) defines the clock inputs and maps target-specific pin names onto the generic OpenCOS top level (`op_top`).  Each target has a set of defines (`OC_TARGET_*`) which will conditionally include various IPs in `op_top`.

### Application Developers
Application developers write their code to standard interfaces (AXI) at the ports of the `oc_user` module, which is instantiated by `oc_top`.  The top level expects various parameters and pins to be present on `oc_user`.  SystemVerilog doesn't support optional pins, so there may be many unused pins -- that is OK.  One of the philosophies of OpenCOS is to keep code simple, and rely on compile time optimizations to strip out anything unnecessary.  The top level will push parameters (number of AXI memory ports, etc) to the application... the application can adapt itself to the target, and/or assert that the target meets it's requirements.

### Integrators
Integrators (often the application developer) choose a target, and an application, and make any choices that remain (for example, the target may support four DDR4 memory interfaces, and the application may support 1..N, and the integrator may decide to create a "lightweight" version supporting only one interface, for initial debug).

## Organization
- **top** : Top level files (oc_top, and a generic oc_user that serves as a generic test platform for targets) as well as components that are used in the top level
- **user** : A collection of "user space" applications, freely distributed as part of the OpenChip framework
- **lib** : A library of components for use in top level and user-space applications.  The desire here is to provide a library of primitives (FIFOs, memories, clock-crossing synchronizers, CSR infrastructure, etc) to provide baseline functionality reminding the author of glibc
- **bin** : Command line scripts, TCL for EDA tools, etc.

## License
OpenCOS is licensed under the Mozilla Public License, v2.  The reasoning behind that is:

- A desire to ensure that code changes to the OpenCOS (aka "kernel") are returned to the community.  This excludes the weakest licenses (MIT, Apache, etc)
- Compatibility with closed source applications, which will be tightly linked into a single "entity" (a bitfile or physical ASIC).  This excludes the strongest licenses (GPL, LGPL).  Note: LGPL is fairly close to what is desired, but includes a clause that requires the user be able to replace the licensed code and rebuild the target -- this is not compatible with hardware designs.
- The Mozilla license includes the requirement to share changes to the OpenCOS framework itself, but doesn't require that end users are able to **replace** the framework and rebuild the whole product.

## About the authors
netchipguy (aka Simon L. Sabato) is currently a hardware architect at F5, and a long time ASIC/FPGA developer who enjoys enabling high-quality design, but hates recreating the wheel.  
