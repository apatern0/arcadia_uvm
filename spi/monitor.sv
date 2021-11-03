`include "uvm/if.sv"

import uvm_pkg::*;
`include "uvm_macros.svh"

class spi_monitor extends uvm_monitor;
	`uvm_component_utils(spi_monitor)
	function new(string name="spi_monitor", uvm_component parent=null);
		super.new(name, parent);
	endfunction

	uvm_analysis_port  #(spi_command) m_recv_imp;
	virtual chip_if vif;
	bit old_busy;

	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);

		if (!uvm_config_db#(virtual chip_if)::get(this, "", "chip_vif", vif))
			`uvm_fatal("MON", "Could not get vif")

		m_recv_imp = new ("m_recv_imp", this);
		old_busy = 0;
	endfunction

	virtual task run_phase(uvm_phase phase);
		super.run_phase(phase);

		forever @(posedge vif.clock) begin
			if(old_busy & ~vif.spi_busy) begin
				spi_command spi_cmd = spi_command::type_id::create("item");
				spi_cmd.cmd  = vif.spi_rx[23:20];
				spi_cmd.data = vif.spi_rx[15:0];
				m_recv_imp.write(spi_cmd);

				`uvm_info("MON", $sformatf("Received SPI Command: %s", spi_cmd.convert2str()), UVM_HIGH)
			end

			old_busy <= vif.spi_busy;
		end
	endtask
endclass
