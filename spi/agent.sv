`include "uvm/if.sv"
`include "uvm/spi/sequence.sv"
`include "uvm/spi/driver.sv"
`include "uvm/spi/monitor.sv"

import uvm_pkg::*;
`include "uvm_macros.svh"

class spi_agent extends uvm_agent;
	`uvm_component_utils(spi_agent)
	function new(string name = "spi_agent", uvm_component parent=null);
		super.new(name, parent);
	endfunction

	spi_driver  d0;
	spi_monitor m0;
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);

		d0 = spi_driver::type_id::create("d0", this);
		m0 = spi_monitor::type_id::create("m0", this);
	endfunction

	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);
	endfunction
endclass


