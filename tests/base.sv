`include "uvm/if.sv"

// Test class instantiates the environment and starts it.
class base_test extends uvm_test;

	`uvm_component_utils(base_test)
	function new(string name = "base_test", uvm_component parent=null);
		super.new(name, parent);
	endfunction

	env                e0;
	virtual chip_if    vif;
	cfg_t              cfg;

	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);

		cfg = cfg_t::type_id::create("cfg", this);
		e0 = env::type_id::create("e0", this);

		if (!uvm_config_db#(virtual chip_if)::get(this, "", "chip_vif", vif))
			`uvm_fatal("TEST", "Did not get vif")

		uvm_config_db#(virtual chip_if)::set(this, "*", "chip_vif", vif);
		uvm_config_db#(cfg_t)::set(this, "*", "cfg", cfg);
	endfunction

	virtual task reset_phase(uvm_phase phase);
		super.reset_phase(phase);

		cfg.sim_time_end = 0;
	endtask
endclass
