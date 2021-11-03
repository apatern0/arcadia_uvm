`include "uvm/if.sv"
`include "uvm/classes.sv"
`include "uvm/hit/sequence.sv"
`include "uvm/hit/driver.sv"
`include "uvm/hit/monitor/monitors.sv"

import uvm_pkg::*;
`include "uvm_macros.svh"

class hit_agent extends uvm_agent;
	`uvm_component_utils(hit_agent)
	function new(string name = "hit_agent", uvm_component parent=null);
		super.new(name, parent);
	endfunction

	hit_driver  d0;
	uvm_sequencer #(pixel_hit) s0;

	core_monitor           m4;
	col_monitor            m3;
	colmem_out_monitor     m2;
	pre_serializer_monitor m1;
	serializers_monitor    m0;

	virtual function void build_phase(uvm_phase phase);
		int c;
		super.build_phase(phase);
		
		d0 = hit_driver::type_id::create("d0", this);
		s0 = uvm_sequencer#(pixel_hit)::type_id::create("s0", this);

		// Monitors
		c = arcadia_ver::num_stages-1;
		if (arcadia_ver::stages[4] == 1) begin
			`uvm_warning("AM", $sformatf("stages4 is %0d", arcadia_ver::stages[4]));
			m4 = core_monitor::type_id::create("m4", this);
			uvm_config_db#(int)::set(this, "m4", "stage", c--);
		end

		if (arcadia_ver::stages[3] == 1) begin
			`uvm_warning("AM", $sformatf("stages3 is %0d", arcadia_ver::stages[3]));
			m3 = col_monitor::type_id::create("m3", this);
			uvm_config_db#(int)::set(this, "m3", "stage", c--);
		end

		if (arcadia_ver::stages[2] == 1) begin
			`uvm_warning("AM", $sformatf("stages2 is %0d", arcadia_ver::stages[2]));
			m2 = colmem_out_monitor::type_id::create("m2", this);
			uvm_config_db#(int)::set(this, "m2", "stage", c--);
		end

		if (arcadia_ver::stages[1] == 1) begin
			`uvm_warning("AM", $sformatf("stages1 is %0d", arcadia_ver::stages[1]));
			m1 = pre_serializer_monitor::type_id::create("m1", this);
			uvm_config_db#(int)::set(this, "m1", "stage", c--);
		end

		if (arcadia_ver::stages[0] == 1) begin
			`uvm_warning("AM", $sformatf("stages0 is %0d", arcadia_ver::stages[0]));
			m0 = serializers_monitor::type_id::create("m0", this);
			uvm_config_db#(int)::set(this, "m0", "stage", c--);
		end
	endfunction

	virtual function void connect_phase(uvm_phase phase);
		super.connect_phase(phase);

		d0.seq_item_port.connect(s0.seq_item_export);
	endfunction
endclass


