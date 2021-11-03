`include "uvm/if.sv"

import uvm_pkg::*;
`include "uvm_macros.svh"

class pixel_hit extends uvm_sequence_item;
	`uvm_object_utils(pixel_hit)

	int row;
	int col;
	real fe_timewalk;
	real fe_deadtime;
	int fake;

	int timestamp;
	int simtime;

	virtual function string convert2str();
		string cmd_name;

		return $sformatf("[%2d][%2d] : section_gen[%2d].col_gen[%2d].col.core_gen[%3d].core.region_gen[%3d].pr.Diodes[%2d][%2d]",
						row, col, `COL_IDX(col), `COLUMN_IDX(col), `CORE_IDX(row),
						`REGION_IDX(row), `REGION_AFE_ROW(row), `REGION_AFE_COL(col)
			);
	endfunction

	function new(string name = "pixel_hit");
		super.new(name);
	endfunction
endclass

class cluster_hit extends uvm_sequence;
	`uvm_object_utils(cluster_hit)

	//`uvm_declare_p_sequencer (uvm_sequencer #(cluster_hit))

	static int random_seed;
	pixel_hit pixels[$];
	int timestamp;
	int simtime;
	bit fake = 0;
	int cluster_offset [1:0];

	virtual function string convert2str();
		string str;

		str = $sformatf("Cluster @ %10d (sim. %20d). Pixels:", timestamp, simtime);
		foreach (pixels[i])
    		str = {str, "\n\t", pixels[i].convert2str()};

		return str;
	endfunction

	function new(string name = "cluster_hit");
		super.new(name);

		cluster_offset = {0, 0};
		fake = 0;
	endfunction
	
	virtual task body();
		cluster_hit e = cluster_hit::type_id::create();

		foreach (pixels[i]) begin

			start_item(pixels[i]);
			pixels[i].fake = fake;
			pixels[i].col += cluster_offset[0];
			pixels[i].row += cluster_offset[1];
			finish_item(pixels[i]);

			//`uvm_do(pixels[i]);
		end

		`uvm_info("SEQ", $sformatf("Injecting new cluster.\n%s", e.convert2str()), UVM_DEBUG);
	endtask

	function void post_randomize();
		int row_delta, col_delta;
		cluster_hit c;

		automatic int row = $dist_uniform(random_seed, 0, `ARCADIA_MATRIX_HEIGHT-1);
		automatic int col = $dist_uniform(random_seed, 0, `ARCADIA_MATRIX_WIDTH-1);

		inject_pix(row, col, 400, $dist_uniform(random_seed, `TB_INJECTION_SKEW_MIN, `TB_INJECTION_SKEW_MAX));

		for(int row_delta=-1; row_delta<=1; row_delta++) begin
			for(int col_delta=-1; col_delta<=1; col_delta++) begin
				automatic int this_row = row+row_delta;
				automatic int this_col = col+col_delta;
				automatic int this_prob = $dist_uniform(random_seed, 0, 99);
				automatic int this_skew = $dist_uniform(random_seed, `TB_INJECTION_SKEW_MIN, `TB_INJECTION_SKEW_MAX);

				if(
					(this_row > 0) && (this_row < `ARCADIA_MATRIX_HEIGHT) &&
					(this_col > 0) && (this_col < `ARCADIA_MATRIX_WIDTH) &&
					(this_prob < (`TB_PIX_NEIGHBOR_PROB*100))
				)
					inject_pix(this_row, this_col, 400, this_skew);
			end
		end
	endfunction

	function void inject_pix(int row, int col, real fe_deadtime, real fe_timewalk, int skip_check = 0);
		int present[$];
		pixel_hit a = pixel_hit::type_id::create();

		a.row = row;
		a.col = col;

		`uvm_info("INJ", $sformatf("Pixel selected for injection: %s", a.convert2str()), UVM_DEBUG);
	
		if(fe_deadtime < 0.0) 
			a.fe_deadtime = 400;
		else
			a.fe_deadtime = fe_deadtime;
	
		if(fe_timewalk < 0.0)
			a.fe_timewalk = 400;
		else
			a.fe_timewalk = fe_timewalk;
	
		// Is it a valid pixel?
		if (row < `ARCADIA_MATRIX_HEIGHT && row >= 0 && col < `ARCADIA_MATRIX_WIDTH && col >= 0) begin
	
			if(skip_check == 1)
				pixels.push_front(a);
			else begin
				// Is it already injected?
				present = pixels.find_index with (item.row == a.row && item.col == a.col);
	
				if(present.size() == 0)
					pixels.push_front(a);
			end
		end else
			`uvm_warning("SEQ", $sformatf("Trying to inject out-of-bound pixel at [%4d][%4d]", row, col))
	endfunction;
endclass

class randomized_cluster extends uvm_sequence;
	`uvm_object_utils(randomized_cluster)

	//`uvm_declare_p_sequencer (uvm_sequencer #(randomized_cluster))
	uvm_sequencer #(pixel_hit) s0;
	
	real rate_mhz_pix;
	real rate_mhz_cm2;
	int length_us;
	real hit_period_ns;

	virtual function string convert2str();
		string str;

		return $sformatf("Randomized Cluster injection @ %3d MHz/cm2 for %0d us.", rate_mhz_cm2, length_us);
	endfunction

	function new(string name = "randomized_cluster");
		super.new(name);
	endfunction
	
	/*
	rand int num; 	// Config total number of items to be sent
	constraint c1 { soft num inside {[10:50]}; }
	*/

	function void set_rate_mhz_cm2 (real x);
		rate_mhz_cm2  = x;
		rate_mhz_pix  = rate_mhz_cm2/(0.01*0.01)*(25E-6*25E-6);
		hit_period_ns = 1E3/(`ARCADIA_MATRIX_HEIGHT*`ARCADIA_MATRIX_WIDTH*rate_mhz_pix);
	endfunction

	virtual task body();
		int poisson_seed;
		int rnd;
		int sim_time;
		int next_hit;
		cluster_hit c;

		sim_time = $time;

		while ($time - sim_time <= length_us*1000) begin
			next_hit = $dist_poisson(poisson_seed, hit_period_ns);
			#(1+next_hit);

			// Prob of multihits
			//rnd = $dist_uniform(random_seed, 0, `ARCADIA_COL_HEIGHT*`ARCADIA_COLS*`ARCADIA_COL_WIDTH);
			rnd=1;
			for(int r=0; r<rnd; r++) begin
				c = cluster_hit::type_id::create("c");
				c.randomize();
				c.start(s0);
			end
		end
	endtask
endclass

class real_data_cluster extends uvm_sequence;
	`uvm_object_utils(real_data_cluster)

	uvm_sequencer #(pixel_hit) s0;
	
	real rate_mhz_pix;
	real rate_mhz_cm2;
	int length_us;
	real hit_period_ns;

	string xyt_file_name;
	int    xyt_file_rd;

	string clusters_file_name;
	int    clusters_file_rd;

	cluster_hit cluster_db [$];
	
	/*
	rand int num; 	// Config total number of items to be sent
	constraint c1 { soft num inside {[10:50]}; }
	*/

	virtual function string convert2str();
		string str;

		return $sformatf("Randomized Cluster injection @ %3d MHz/cm2 for %0d us.", rate_mhz_cm2, length_us);
	endfunction

	function new(string name = "real_data_cluster");
		cluster_hit cluster_tmp;
		int pixel_x, pixel_y, cluster_number;
		real alpide_timewalk, alpide_deadtime, bulk_timewalk, bulk_deadtime;
		string line, str_cluster;

		super.new(name);

		xyt_file_name = {`CLUSTER_POSITION, `CLUSTER_POSITION_NAME, ".txt"};
		xyt_file_rd   = $fopen(xyt_file_name, "r");

		if(!xyt_file_rd)
			`uvm_fatal("SEQ", $sformatf("xyt file %s was NOT opened successfully: %0d", xyt_file_name, xyt_file_rd))
		else 
			`uvm_info("SEQ", $sformatf("Processing xyt file: %s", xyt_file_name), UVM_LOW)

		clusters_file_name = {`CLUSTER_GENERATOR, `CLUSTER_NAME, ".txt"};
		clusters_file_rd   = $fopen(clusters_file_name, "r");

		if(!clusters_file_rd)
			`uvm_fatal("SEQ", $sformatf("clusters file %s was NOT opened successfully: %0d", clusters_file_name, clusters_file_rd))
		else 
			`uvm_info("SEQ", $sformatf("Processing clusters file: %s", clusters_file_name), UVM_LOW)

		while (!$feof(clusters_file_rd)) begin : read_line
			$fgets(line, clusters_file_rd);

			if(line.match("#"))
				continue;

			if(line.match("CLUSTER_NUMBER")) begin
				$sscanf(line, "%s %d", str_cluster, cluster_number);
				cluster_tmp = cluster_hit::type_id::create("cluster");

			end else if(line.match("ENDCLUSTER")) begin
				cluster_db.push_front(cluster_tmp);

			end else begin
				$sscanf(line, "%d %d %f %f %f %f\n", pixel_x, pixel_y, alpide_timewalk, bulk_timewalk, alpide_deadtime, bulk_deadtime);

				`ifdef ARCADIA_FE_ALPIDE_REFERENCE
					if(alpide_deadtime > 0.0 && alpide_timewalk > 0.0)
						cluster_tmp.inject_pix(pixel_x, pixel_y, alpide_deadtime, alpide_timewalk);

				`else // BULK
					if(bulk_deadtime > 0.0 && bulk_timewalk > 0.0)
						cluster_tmp.inject_pix(pixel_x, pixel_y, bulk_deadtime, bulk_timewalk);

				`endif
			end
		end : read_line

		$fclose(clusters_file_rd);
	endfunction

	virtual task body();
		int sim_time;
		string line;
		string first_char;
		int cluster_x;
		int cluster_y;
		int cluster_idx;
		int delta_time;
		int cluster_type;
		cluster_hit c;

		sim_time = $time;

		while (!$feof(xyt_file_rd)) begin
			$fgets(line, xyt_file_rd);
			$sscanf(line, "%s", first_char); //get first char of that line

			// Don't parse comments
			if(first_char.match("#"))
				continue;
		
			$sscanf(line, "%d %d %d %d\n", cluster_x, cluster_y, delta_time, cluster_type);
			`uvm_info("SEQ", $sformatf("Injecting new cluster. X=%d Y=%d Time=%d Type=%d.", cluster_x, cluster_y, delta_time, cluster_type), UVM_HIGH);

			#(delta_time);

			cluster_idx = $urandom_range(cluster_db.size()-1);
			`uvm_info("SEQ", $sformatf("Reading cluster: %5d.", cluster_idx), UVM_HIGH);

			c = cluster_db[cluster_idx];
			c.cluster_offset = {cluster_x, cluster_y};
			c.start(s0);
		end

		$fclose(xyt_file_rd);
	endtask
endclass
