
# SPDX-License-Identifier: MPL-2.0

# scoped to the oclib_uart_rx

# allow 50ns to get from the pin to the flop in the UART
set_max_delay -to [get_cells uINPUT_DEBOUNCE/uSYNC/uXPM/syncstages_ff_reg[0][0] ] 50.0
