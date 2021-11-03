`include "uvm/if.sv"

import uvm_pkg::*;
`include "uvm_macros.svh"

class hit_driver extends uvm_driver #(pixel_hit);
	`uvm_component_utils(hit_driver)

	virtual chip_if vif;
	cfg_t cfg;

	uvm_analysis_port #( pixel_hit ) m_sent_imp;
	uvm_analysis_port #( pixel_hit ) m_dead_imp;

	logic [`ARCADIA_MATRIX_HEIGHT-1:0][`ARCADIA_MATRIX_WIDTH-1:0] pixel_dead;
	int count_sent_event;

	function new(string name = "hit_driver", uvm_component parent=null);
		super.new(name, parent);

		m_sent_imp = new ("m_sent_imp", this);
		m_dead_imp = new ("m_dead_imp", this);

		pixel_dead = 0;
		count_sent_event = 0;
	endfunction

	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		if (!uvm_config_db#(virtual chip_if)::get(this, "", "chip_vif", vif))
			`uvm_fatal("DRV", "Could not get vif")

		if (!uvm_config_db#(cfg_t)::get(this, "", "cfg", cfg))
			`uvm_fatal("DRV", "Could not get cfg")
	endfunction

	virtual task reset_phase(uvm_phase phase);
		vif.diodes = 0;
	endtask

	virtual task run_phase(uvm_phase phase);
		static int inj_skew_seed = 0;

		super.run_phase(phase);

		forever begin
			pixel_hit c;
			seq_item_port.get_next_item(c);

			c.timestamp = cfg.timestamp;
			c.simtime = $time;

			if(c.row < 0 || c.row >= `ARCADIA_MATRIX_HEIGHT || c.col < 0 || c.col >= `ARCADIA_MATRIX_WIDTH) begin
				`uvm_info("DRV", $sformatf("\t\tPix %s is out of bounds. Skipping injection...", c.convert2str()), UVM_HIGH);
				seq_item_port.item_done();
				continue;
			end

			cfg.sent_pix++;
			if(pixel_dead[c.row][c.col]) begin
				`uvm_info("DRV", $sformatf("\t\tPix %s DEAD. Skipping injection...", c.convert2str()), UVM_HIGH);
				m_dead_imp.write(c);

			end else begin
				`uvm_info("DRV", $sformatf("\t\tPix %s INJ w/ tw %.3f dt %.3f", c.convert2str(), c.fe_timewalk, c.fe_deadtime), UVM_HIGH);
				m_sent_imp.write(c);

				if (c.fake == 0) fork begin
					//phase.raise_objection(this);

					pixel_dead[c.row][c.col] = 1'b1;
					#(c.fe_timewalk);
					vif.diodes[c.row][c.col] = 1'b1;

					`uvm_info("DRV", $sformatf("\tInjecting %s", c.convert2str()), UVM_DEBUG);

					#(c.fe_deadtime);
					vif.diodes[c.row][c.col] <= 1'b0;
					pixel_dead[c.row][c.col] <= 1'b0;

					//phase.drop_objection(this);
				end join_none
			end

			seq_item_port.item_done();
		end
	endtask
endclass
