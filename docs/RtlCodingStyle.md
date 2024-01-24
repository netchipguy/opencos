# RTL Coding

## Organization

### lib/oclib_*

Library elements

## Naming Style

### Modules
- lowercase_underlined
- OC reserved prefixes: `oclib_*`, `oc_*`
- Complete words: `oclib_synchronizer`
    - Except for standard cases (`oclib_fifo`, `oclib_csr_to_drp`)

### Parameters
- CamelCase
- Full words
  
### Ports/Signals
- lowercase_underlined
- Clocks must start with `clock`
    - Various backend flows may rely on this
    - Single clock modules should just have `clock`
    - Multi-clock modules can use the default `clock` and others (`clockJtag`), or just several non-default clocks (`clockRead`, `clockWrite`)
- Resets should start with `reset`
    - When >1 reset, labels match clock (`clockAxi`/`resetAxi`)
 
### Indentation
- Matches Verilog-Mode for Emacs

## Defines
- Universal defines: `SIMULATION`, `SYNTHESIS`, `SEED`
- OC reserved prefix: `OC_*`
- Tool and version: `OC_TOOL_*`
    - `OC_TOOL_VIVADO`, `OC_TOOL_VIVADO_2022.2`
- Library: `OC_LIBRARY_*`
    - `OC_LIBRARY_ULTRASCALE_PLUS`
- Target: `OC_TARGET_*`
    - `OC_TARGET_U200`
  
## Includes
- Default settings by EDA
    - `+incdir+<Root of OpenCOS repo>`
    - `+libext+.sv+.v`
- Include files should use header guards
    - ``ifdef __LIB_OCLIB_DEFINES_VH`
- RTL files should ``include` their dependencies (not include them in DEPS)

## Parameters
- Always have default values
    - they may be invalid and caught with a static assert
    - purpose here is to ensure modules can report detailed error ("You must set parameter X because ...") instead of not compiling