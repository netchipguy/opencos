# Connecting Apps

The API between oc_top and oc_user is perhaps the area where OpenCOS diverges the most from the OS/Userspace parallel in the software world. 

Similarities:
- In both cases, we desire to give a stable API to our userspace apps.  Existing APIs should not change.
- As new APIs are made available, they shouldn't break existing applications.
Differences:
- The OS can add new APIs and expose them to userspace, without significant cost, and without changes to userspace.  In hardware, connectivity between OS and userspace is in the form of physical wires that must be connected.

Furthermore, module ports (and connections to instance ports) cannot be made dependent on parameters.  Either all ports are always there, or they must be made conditional on `defines.  

We desire to not burden userspace with unnecessary complexity.  For example, if it does not require networking, it shouldn't have to declare network ports. 

We desire that the userspace can be flexible.  For example, if it is a memory tester, it would be nice if it could scale the number, width, and type of interfaces (for example, connecting to four 512-bit AXI-3 interfaces, or thirty-two 256-bit AXI-4 interfaces).  

We desire that the top level (`oc_top`) only contains logic required to meet user-space requests.  We don't "build everything in" and then just connect what we need. 

The following methodology is used: 

- Userspace declares via a header (`oc_user_defines.vh`) what types of interfaces it can connect to.
    - This includes a class (local memory), an interface type (AXI-4), a width (512-bit), and a count (4)
    - This file is not expected to be edited by the integrator.  But it may note defines that can be set in `oc_board_defines.vh` to configure functionality within the userspace app.  
- The board comes with a header file that (`oc_board_defines.vh`) that the integrator edits to constrain which external interfaces are connected.  This file will also set the defines which activate `oc_top` ports connecting out to the chip interfaces.  It can also hint to `oc_top` about internal features to enable, when they can't be inferred just from the interfaces (for example, a define could enable Ethernet switching functionality between external network interfaces and userspace)
- The board-specific `oc_chip_top` will take the `oc_board_defines.vh` and drive parameters into `oc_top`
    - do we need this?
- `oc_top` will read `oc_board_defines.vh` to enable ports out to chip interfaces. 
- `oc_top` will read `oc_user_defines.vh` to know what interfaces must be connected to userspace.
- `oc_top` will infer what internal functions are needed based on board and user defines.  