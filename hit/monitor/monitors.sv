import uvm_pkg::*;
`include "uvm_macros.svh"

`include "defines.sv"
`include "interfaces.sv"

// Base monitor
`include "hit_monitor.sv"

// Core monitors
`include "core/hitmem_monitor.sv"
`include "core/interface_module.sv"

// EOS monitors
`include "eos/colmem_monitor.sv"
`include "eos/from_columns_monitor.sv"
`include "eos/interface_module.sv"

// Periphery monitors
`include "periphery/serializer_monitor.sv"
`include "periphery/post_serializer_monitor.sv"
