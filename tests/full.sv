`include "uvm/if.sv"

// Test class instantiates the environment and starts it.
class full_test extends base_test;
	`uvm_component_utils(full_test)

	function new(string name = "full_test", uvm_component parent=null);
		super.new(name, parent);
	endfunction

	virtual task main_phase(uvm_phase phase);
		cluster_hit c;
		int sim_time_start, sim_time_end;
		int rows, cols;

		rows = `ARCADIA_MATRIX_HEIGHT;
		cols = `ARCADIA_MATRIX_WIDTH;

		phase.raise_objection(this);
		`uvm_info("TEST", $sformatf("Starting full test on a %4d (rows) x %4d (cols) matrix.",rows,cols), UVM_NONE);

		cfg.sim_time_start = $time;
		cfg.expiration_time = 0;

		c = cluster_hit::type_id::create("c", this);
		for(int col=0;col<cols;col++)
			for(int row=0;row<rows;row++)
				c.inject_pix(row,col,400,400,1);
	   
		c.start(e0.hit_ag.s0);

		#50us;

		`uvm_info("TEST", "Finished full test", UVM_NONE);

		phase.drop_objection(this);
	endtask

	virtual task post_main_phase(uvm_phase phase);
		super.post_main_phase(phase);

		e0.hit_sb.report();
	endtask

	function void print_settings();
		int sim_time;
/*
		$display("Settings:");
`ifdef RATE_MHZ_CM2
		$display("\tRATE_MHZ_CM2: %f", `RATE_MHZ_CM2);
`endif
		$display("\tTB_HITRATE_PER_CM2: %f", `TB_HITRATE_PER_CM2);
		$display("\tTB_HITRATE_PER_PIXEL: %f", `TB_HITRATE_PER_PIXEL);
		$display("\tTB_HITRATE_PER_MATRIX: %f", `TB_HITRATE_PER_MATRIX);
		$display("\tTB_HIT_PERIOD: %f", `TB_HIT_PERIOD);
		$display("\tMatrix size: %4d x %4d", `ARCADIA_MATRIX_WIDTH, `ARCADIA_MATRIX_HEIGHT);
		$display("Injecting Poisson-distributed hits with average period = %d ns for %d ns\n", `TB_HIT_PERIOD_NS, `TB_SIMULATION_LENGTH_NS);
	
		$display("Checking timescale...");
		sim_time = $time;
		#`TB_HIT_PERIOD_NS;
		sim_time = $time - sim_time;
		$display("Waited %f ns, detected %f ns", `TB_HIT_PERIOD_NS, sim_time);
	
		sim_time = sim_time - `TB_HIT_PERIOD_NS;
		if(sim_time < -1 || sim_time > 1)
			$stop;
*/
	endfunction


	function void print_statistics();
/*
		int sim_time_length = sim_time_end - sim_time_start;

		string printout = {
			"Statistics:",
			$sprintf("\n\tInjected %d clusters in %d ns. Rate: %.3f MHz (%.3f MHz/cm2)", hits_count, (sim_time_length), real'(hits_count)/(sim_time_length)*1e3, real'(hits_count)/(sim_time_length)*1e3/(25e-6*25e-6*`ARCADIA_MATRIX_HEIGHT*`ARCADIA_MATRIX_WIDTH)*(0.01*0.01)),
		}

	for(int col = 0; col < `ARCADIA_SECTIONS; col++)
		printout = {printout, $sprintf("\n\tSection %2d: Injected %d pixels. Rate: %.3f MHz (%.3f MHz/cm2)", col, hits_per_section[col], real'(hits_per_section[col])/(sim_time_length)*1e3, real'(hits_per_section[col])/(sim_time_length)*1e3/(25e-6*25e-6*`ARCADIA_SECTION_HEIGHT*`ARCADIA_SECTION_WIDTH)*(0.01*0.01))};

	for(int col = 0; col < `ARCADIA_SECTIONS; col++) begin
		printout = {printout, $sprintf("\n\tSection %2d: Received %2d data packets, of %2d bits each, in %d ns. Packet rate: %2.3f Mbps. Output bandwidth: %.3f Mbps, per core section: %.3f Mbps",
			col, packets_count[col], `ARCADIA_SECTION_DATA_BITS, (sim_time_length),
			real'(packets_count[col])/(sim_time_length)*1e3,
			real'(packets_count[col]*`ARCADIA_SECTION_DATA_BITS)/(sim_time_length)*1e3,
			real'(packets_count[col]*`ARCADIA_SECTION_DATA_BITS)/(sim_time_length)/(`ARCADIA_SECTION_COLUMNS)*1e3
		)};

		if(col != 0)
			packets_count[0] += packets_count[col];
	end

	printout = {printout, $sprintf("\n\tFull chip: Received %2d data packets, of %2d bits each, in %.2f ms. Output bandwidth: %.3f Mbps, per section: %.3f Mbps",
		packets_count[0], `ARCADIA_SECTION_DATA_BITS, (sim_time_length)/1E6,
		real'(packets_count[0]*`ARCADIA_SECTION_DATA_BITS)/(sim_time_length)*1e3,
		real'(packets_count[0]*`ARCADIA_SECTION_DATA_BITS)/(sim_time_length)/(`ARCADIA_SECTIONS)*1e3
	)};
*/
	endfunction
endclass
