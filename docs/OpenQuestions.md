# Open Questions

## RTL Coding

* Can we make tools behave well with a rational policy for unconnected ports?
    * Unconnected outputs should be ignored (ideally we can flag an output as being "not ignorable" but that seems pretty vague).  It's not great that adding an output to a module causes warnings in previous usage that doesn't need the new feature
    * Unconnected inputs should be ignored IF THEY HAVE A DEFAULT VALUE.  We get to set default values for inputs, why should we force people to tie them?