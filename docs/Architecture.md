# Architecture

Looking at it roughly bottom up.

## oc_user.sv

A "userspace" app is loaded, via pointing a build to a DEPS target that pulls in an oc_user.sv.

There is an associated oc_user.vh which contains:
- `defines which configure the internals of the user-space app, and can be whatever is required by the application. They don't need OC_* prefixes, etc
- `defines which configure the interface to the operating system, and are defined by OpenCOS.  These OC_USER_* defines configure the ports of oc_user and it's instantiation in oc_cos.

Userspace apps which "ship" with OpenCOS are in the <oc>/user directory, but they can be located anywhere (TBD: document how that is done)

TODO: define a userspace testbench.  The OC_COS and above levels are implemented behaviorally for flexible testing at the userspace API level.

## oc_cos.sv

The "operating system", which instantiates the userspace app, as well as a collection of top level modules.  It is stores in <oc>/top

oc_cos configures itself via two sets of defines:
- OC_COS_* defines which enable services from the operating system.  For example the userspace could request that ethernet bridging is enabled between 4 external and 4 userspace ports, instead of direct connection.  The board may setup features such as fan and LED controls.  Meanwhile the integrator may enable things like bitstream licensing.
- OC_BOARD_* defines which are set by the board target DEPS, and configure the ports of oc_cos.  The goal is for OC_BOARD defines to setup the defaults for the parameters of oc_cos, not for them to be used repeatedly internally.  Some things cannot be done that way (for example setting module names).

Testing is performed via <oc>/top/tests/oc_cos_*test targets, which should aim to instantiate as much as possible, while testing the subset that the testbench knows how to test.  Practically speaking, the kinds of tests run at this level should consider not duplicating the tests that operate at the next stage up (board level).

TODO: do we require board target to use DEPS?  what if they just want to have defines in a file, how do we ensure it's read before oc_cos (we could add a way for oc_cos to pull in a header file)

## oc_chip_top.sv

This is the typical (but not mandatory) name of the top level for a given target.  This is stored in a <oc>/boards/<board> directory.

The concept of oc_chip_top is like a "board support package" for an operating system, the thin shim that connects the shared code with the unique target.  It likely instantiates I/O buffers, maybe connects some pins that are unique to the board (things to do with bringup sequence, custom thermal solutions, etc).  Basically, anything that OC_COS cannot handle, needs to be put up here.

It's entirely optional for oc_chip_top to configure oc_cos via parameter.  oc_cos will setup it's ports based on OC_BOARD defines, and overriding the parameters so they don't match the defaults could result in inconsistent state if the design looks at the OC_BOARD defines again.  oc_chip_top

TODO: work on the naming.  it's called a target, a board, oc_chip_top, etc, and it's confusing.

## oc_chip_harness.sv

The purpose of oc_chip_harness is to "reverse" the transformation between oc_cos ports (ledOut[1:0], pciRxP[15:0], etc) and oc_chip_top ports (LED_GREEN, LED_RED, PCI_RXP_15, PCI_RXP_14, etc).  It terminates any custom interface coming out of oc_chip_top in a way that makes sense.  Upwards, it shows ports that look like oc_cos.  In this way, oc_cos tests (including those that test userspace apps) can be run on oc_chip_top (i.e. including all board customizations).

The upward facing ports need to match the upward facing oc_cos ports.  This can be done "with care", or can be done by examining OC_BOARD_* defines and setting up params and ports to match.

oc_chip_harness does not accept params, and oc_cos_test runs in a mode where it doesn't push params.  Instead it is expected that OC_BOARD_* defines from the board DEPS will configure oc_cos (definitely) and oc_chip_top/oc_chip_harness (optionally).
