`include "uvm/if.sv"
`include "cfg_defines.v"

import uvm_pkg::*;
`include "uvm_macros.svh"

class base_driver extends uvm_driver;
	`uvm_component_utils(base_driver)
	function new(string name = "base_driver", uvm_component parent=null);
		super.new(name, parent);
	endfunction

	virtual chip_if vif;

	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);

		if (!uvm_config_db#(virtual chip_if)::get(this, "", "chip_vif", vif))
			`uvm_fatal("DRV", "Could not get vif")
	endfunction

	virtual task reset_phase(uvm_phase phase);
		phase.raise_objection(this);

		vif.clock_enable = 1'b0;
		vif.chip_reset = 1'b0;
		vif.test_pulse = 1'b0;

		// Reset pulse w/o Clock
		repeat(1) @ (posedge vif.clock);
		repeat(2) @ (posedge vif.clock) begin
			repeat(10) @ (posedge vif.clock);
			#0.5ns;
			vif.chip_reset = ~vif.chip_reset;
		end
		repeat(1) @ (posedge vif.clock);

		// Reset pulse w/ Clock
		vif.clock_enable = 1'b1;
		repeat(1) @ (posedge vif.clock);
		repeat(2) @ (posedge vif.clock) begin
			repeat(10) @ (posedge vif.clock);
			#0.5ns;
			vif.chip_reset = ~vif.chip_reset;
		end

		// Reset pulse w/o Clock
		vif.clock_enable = 1'b0;
		repeat(1) @ (posedge vif.clock);
		repeat(2) @ (posedge vif.clock) begin
			repeat(10) @ (posedge vif.clock);
			#1ns;
			vif.chip_reset = ~vif.chip_reset;
		end

		repeat(100) @ (posedge vif.clock);

		// Enable Clock
		vif.clock_enable = 1'b1;
		repeat(10) @ (posedge vif.clock);

		phase.drop_objection(this);
	endtask
endclass
