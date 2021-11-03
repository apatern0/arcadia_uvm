`include "uvm/if.sv"

import uvm_pkg::*;
`include "uvm_macros.svh"

class spi_driver extends uvm_driver #(spi_command);
	`uvm_component_utils(spi_driver)

	virtual chip_if vif;
	spi_command cmd_queue[$];
	uvm_analysis_port #( spi_command ) m_sent_imp;

	function new(string name = "spi_driver", uvm_component parent=null);
		super.new(name, parent);

		m_sent_imp = new ("m_sent_imp", this);
	endfunction

	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if (!uvm_config_db#(virtual chip_if)::get(this, "", "chip_vif", vif))
			`uvm_fatal("DRV", "Could not get vif")
	endfunction

	virtual task run_phase(uvm_phase phase);
		spi_command spi_cmd;

		`uvm_info("SPI", $sformatf("%m - Ready to receive commands"), UVM_HIGH);
		super.run_phase(phase);
		vif.spi_tx = 'h0;

		forever begin
			while (cmd_queue.size() == 0 || vif.spi_busy == 1'b1)
				@(posedge vif.clock);

			while (cmd_queue.size() != 0) begin
				spi_cmd = cmd_queue.pop_back();

				vif.spi_enable = 1'b1;
				vif.spi_tx = {spi_cmd.cmd, 4'h0, spi_cmd.data};

				m_sent_imp.write(spi_cmd);
	
				`uvm_info("SPI", $sformatf("Sending SPI command: %s", spi_cmd.convert2str()), UVM_HIGH)
	
				@(posedge vif.clock);
				vif.spi_enable = 1'b0;

				@(posedge vif.clock);
				while(vif.spi_busy == 1'b1)
					@(posedge vif.clock);

				repeat(100) @(posedge vif.clock);

				spi_cmd.phase.drop_objection(this);
			end
		end
	endtask

	virtual task reset_phase(uvm_phase phase);
		vif.spi_enable = 1'b0;

		forever @(vif.chip_reset) begin
			if(vif.chip_reset)
				vif.spi_reset = 1'b1;
			else begin
				phase.raise_objection(this);
				repeat(5) @(posedge vif.clock);

				vif.spi_reset = 1'b0;
				phase.drop_objection(this);
			end
		end

	endtask: reset_phase 

	task send_command (uvm_phase phase, bit [3:0] cmd, bit [15:0] data);
		spi_command spi_cmd = spi_command::type_id::create();
		spi_cmd.cmd = cmd;
		spi_cmd.data = data;
		spi_cmd.phase = phase;

		`uvm_info("SPI", $sformatf("New command in queue: %s", spi_cmd.convert2str()), UVM_DEBUG);

		cmd_queue.push_front( spi_cmd );

		phase.raise_objection(this);
	endtask
endclass
