# Installation

Mandatory:

- OpenCOS (`git clone https://github.com/netchipguy/opencos.git`)

Recommended:

- Python packages used by `oc_connect`
    - NOTE: all these can be put in a venv
    - `pip install pyserial`
- Xilinx Vivado suite
     - NOTE: licenses are not required to build designs for certain targets (generally Alveo boards: U200, U50, etc).  Other Xilinx kits contain licenses supporting the device used in the kit (Kintex 7, etc).  For other situations, a license is required to build bitfiles.  Certain IPs (Xilinx 25GMAC for example) may require additional licenses – we are always looking for open source versions of such IP :)
   - `https://www.xilinx.com/support/download.html`
- Minicom (or another serial terminal)
    - For debugging.  `oc_connect` should be all that is needed, but at some point many folks will need a vanilla serial terminal.  