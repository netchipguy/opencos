
# SPDX-License-Identifier: MPL-2.0

# scoped to the oclib_uart_tx

# allow 50ns to get from the flop in the UART to the pin
set_max_delay -from [get_cells tx_reg] 50.0
