# Directory Structure

`boards`
- A set of target boards, platforms, etc
  
`apps`
- A set of applications that can be loaded

`top`
- Files implementing the top-level (aka "operating system")

`sim`
- Simulation related transactors.  These are used in tests, and are kept separely `top` and `lib` because they aren't expected to be compiled/elaborated in isolation.  

`lib`
- Files implementing the OpenCOS standard library

`bin`
- Scripts, binaries, programs

`docs`
- OpenCOS documentation area