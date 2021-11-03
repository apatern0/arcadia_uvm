`include "uvm/if.sv"

import uvm_pkg::*;
`include "uvm_macros.svh"

class bias_scoreboard extends uvm_scoreboard;
	`uvm_component_utils (bias_scoreboard)
	
	`uvm_analysis_imp_decl ( _sent_pix )
	`uvm_analysis_imp_decl ( _dead_pix )
	`uvm_analysis_imp_decl ( _recv_pix )

	uvm_analysis_imp_sent_pix #( pixel_bias , bias_scoreboard ) m_sent_imp ;
	uvm_analysis_imp_dead_pix #( pixel_bias , bias_scoreboard ) m_dead_imp ;
	uvm_analysis_imp_recv_pix #( pixel_recv , bias_scoreboard ) m_recv_imp ;

	cfg_t cfg;
	virtual chip_if vif;

	pixel_recv dead_queue[$];

	pixel_recv stage_queue       [arcadia_ver::num_stages:0] [$];
	pixel_recv expired_queue     [arcadia_ver::num_stages:0] [$];
	pixel_recv expired_queue_old [arcadia_ver::num_stages:0] [$];

	pixel_recv match_queue       [$];
	pixel_recv ghost_queue       [arcadia_ver::num_stages:0] [$];
	pixel_recv ghost_queue_old   [arcadia_ver::num_stages:0] [$];
	pixel_recv timerr_queue      [$];
	pixel_recv dupl_queue        [$];

	bit stop_on_ghost;
	bit stop_on_duplicate;
	int report_level;

	function new (string name = "bias_scoreboard", uvm_component parent);
		super.new (name, parent);
	endfunction

	function void build_phase (uvm_phase phase);
		m_sent_imp = new ("m_sent_imp", this);
		m_dead_imp = new ("m_dead_imp", this);
		m_recv_imp = new ("m_recv_imp", this);

		if (!uvm_config_db#(cfg_t)::get(this, "", "cfg", cfg))
			`uvm_fatal("SB", "Could not get cfg")

		if (!uvm_config_db#(virtual chip_if)::get(this, "", "chip_vif", vif))
			`uvm_fatal("SB", "Could not get vif")

		stop_on_ghost = 0;
		stop_on_duplicate = 0;
		report_level = UVM_HIGH;
	endfunction

	virtual task pre_main_phase(uvm_phase phase);
		clear();
	endtask

	function void check_expired();
		int expired[$];

		if(cfg.expiration_time != 0) begin
			for (int stage=arcadia_ver::num_stages; stage > 0; stage--) begin
				expired = stage_queue[stage].find_index with ( $time - item.simtime[stage] > cfg.expiration_time );
				expired.rsort();

				foreach (expired[i]) begin
					`uvm_info($sformatf("SB%0d", stage), $sformatf("Expired was %5d, Removing from stage: %s", cfg.expired_pix[stage], stage_queue[stage][expired[i]].convert2str()), UVM_HIGH);

					expired_queue[stage].push_front( stage_queue[stage][expired[i]] );
					stage_queue[stage].delete( expired[i] );
					cfg.expired_pix[stage]++;
				end
			end
		end
	endfunction

	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		fork
			forever #1us check_expired();
			forever #1us report();
		join_none
	endtask

	virtual task post_main_phase(uvm_phase phase);
		super.main_phase(phase);
		
		fork
			forever #1us check_expired();
			forever #1us report();
		join_none
	endtask

	virtual function void write_sent_pix (pixel_bias data);
		pixel_recv this_queue [$];
		string str;

		pixel_recv p = pixel_recv::type_id::create("p");
		p.row = data.row;
		p.col = data.col;
		p.fe_timewalk = data.fe_timewalk;
		p.simtime[arcadia_ver::num_stages] = data.simtime;
		p.timestamp = (2**`ARCADIA_EVENT_ID_BITS + data.timestamp) % (2**`ARCADIA_EVENT_ID_BITS);
		p.stage = arcadia_ver::num_stages;

		stage_queue[arcadia_ver::num_stages].push_front(p);
		cfg.match_pix[arcadia_ver::num_stages]++;
	endfunction

	virtual function void write_dead_pix (pixel_bias data);
		pixel_recv p = pixel_recv::type_id::create("p");
		p.row = data.row;
		p.col = data.col;
		p.fe_timewalk = data.fe_timewalk;
		p.simtime[arcadia_ver::num_stages] = data.simtime;
		p.timestamp = data.timestamp;
		p.stage = arcadia_ver::num_stages;

		dead_queue.push_front(p);
		cfg.dead_pix++;
	endfunction 

	virtual function void write_recv_pix (pixel_recv data);
		cfg.recv_pix[data.stage]++;
		data.simtime[data.stage] = $time;

		process_pixel(data);
	endfunction

	function string dump_queue(const ref pixel_recv queue [$], input int cut = 0);
		string str;
		int counter;

		counter = 0;
		foreach (queue[i]) begin
			str = {str, queue[i].convert2str(), "\n"};
			if (cut != 0) begin
				if(counter > cut) begin
					str = {str, "... queue exceeding 20 items. Stopping dump.", "\n"};
					break;
				end else
					counter = counter+1;
			end
		end
		return str;
	endfunction

	virtual function void process_pixel (pixel_recv data);
		pixel_recv p;
		string sb_stagename;
		string str;

		int diff;
		int idx;

		sb_stagename = $sformatf("SB_STAGE%0d", data.stage);

		// Match
		idx = is_match(stage_queue[data.stage+1], data);
		if(idx != -1) begin
			// Move object
			stage_queue[data.stage+1][idx].stage   = data.stage;
			stage_queue[data.stage+1][idx].simtime[data.stage] = $time;
			stage_queue[data.stage].push_front(stage_queue[data.stage+1][idx]);
			stage_queue[data.stage+1].delete(idx);

			// Increase counter
			cfg.match_pix[data.stage]++;

			str = {data.convert2str(), "\n"};
//			str = {str, $sformatf("This_queue becomes:\n%s", dump_queue(stage_queue[data.stage]))};
//			str = {str, $sformatf("\n While next queue becomes:\n%s", dump_queue(stage_queue[data.stage+1]))};
			`uvm_info(sb_stagename, str, UVM_HIGH);

			return;
		end
		
		// Timing displacement
		idx = is_timerr(stage_queue[data.stage+1], data);
		if(idx != -1) begin
			// Adjust timestamp, set delta
			p = stage_queue[data.stage+1][idx];

			p.timestamp_delta = data.timestamp - p.timestamp;
			if(p.timestamp_delta > 2**(`ARCADIA_EVENT_ID_BITS-1))
				p.timestamp_delta -= 2**`ARCADIA_EVENT_ID_BITS;
			else if(p.timestamp_delta <= -2**(`ARCADIA_EVENT_ID_BITS-1))
				p.timestamp_delta += 2**`ARCADIA_EVENT_ID_BITS;

			`uvm_info("TIMERR", $sformatf("Found with timestamp %4d, but should be %4d. Offset: %2d\n", data.timestamp, p.timestamp, p.timestamp_delta), UVM_HIGH);

			p.timestamp       = data.timestamp;

			// Move object
			stage_queue[data.stage+1][idx].stage   = data.stage;
			stage_queue[data.stage+1][idx].simtime[data.stage] = $time;
			stage_queue[data.stage].push_front(stage_queue[data.stage+1][idx]);
			stage_queue[data.stage+1].delete(idx);

			// Increase counters
			cfg.timerr_pix[data.stage]++;
			cfg.match_pix[data.stage]++;
			cfg.disp_pix[data.stage][data.timestamp_delta+2**(`ARCADIA_EVENT_ID_BITS-1)]++;

			str = {data.convert2str(), "\n"};
//			str = {str, $sformatf("This_queue becomes:\n%s", dump_queue(stage_queue[data.stage]))};
//			str = {str, $sformatf("\n While next queue becomes:\n%s", dump_queue(stage_queue[data.stage+1]))};
			`uvm_info(sb_stagename, str, UVM_HIGH);

			return;
		end

		// Is it a duplicate?
		idx = is_dupl(stage_queue[data.stage], data);
		if (idx != -1) begin
			data.duplicate = stage_queue[data.stage][idx].idx;

			// Copy object
			data.simtime[data.stage] = $time;
			stage_queue[data.stage].push_front(data);

			// Increase counter
			cfg.dupl_pix[data.stage]++;

			str = {data.convert2str(), "\n"};
//			str = {str, $sformatf("This_queue becomes:\n%s", dump_queue(stage_queue[data.stage]))};
//			str = {str, $sformatf("\n While next queue becomes:\n%s", dump_queue(stage_queue[data.stage+1]))};
			`uvm_info(sb_stagename, str, UVM_HIGH);

			if(stop_on_duplicate) $stop;
			return;
		end

		// No match, no timerr, no duplicate... then it's a ghost
		data.ghost = data.stage;

		// Copy object
		data.simtime[data.stage] = $time;
		stage_queue[data.stage].push_front(data);
		ghost_queue[data.stage].push_front(data);

		// Increase counter
		cfg.ghost_pix[data.stage]++;

		str = {data.convert2str(), "\n"};
//		str = {str, $sformatf("This_queue becomes:\n%s", dump_queue(stage_queue[data.stage]))};
//		str = {str, $sformatf("\n While next queue becomes:\n%s", dump_queue(stage_queue[data.stage+1]))};
		`uvm_info(sb_stagename, str, UVM_HIGH);

		if(stop_on_ghost) $stop;
	endfunction

	function int is_dupl(const ref pixel_recv_queue this_queue, pixel_recv data);
		int match [$];
		match = this_queue.find_last_index with (
			item.row == data.row && item.col == data.col &&
			(item.timestamp == -1 || data.timestamp == -1 || (
				item.timestamp < ((`TB_TIMING_DELTA + data.timestamp)  % (2**`ARCADIA_EVENT_ID_BITS)) &
				data.timestamp  < ((`TB_TIMING_DELTA + item.timestamp) % (2**`ARCADIA_EVENT_ID_BITS))
			))
		);

		return (match.size() > 0) ? match[0] : -1;
	endfunction

	function int is_timerr(ref pixel_recv_queue this_queue, ref pixel_recv data);
		int match [$];
		match = this_queue.find_last_index with (item.row == data.row && item.col == data.col);

		return (match.size() > 0) ? match[0] : -1;
	endfunction

	function int is_match(const ref pixel_recv_queue this_queue, pixel_recv data);
		int match [$];
		string str;
		
		/*
			str = $sformatf("Looking for %s among the following:\n", data.convert2str());
			foreach (this_queue[i])
				str = {str, this_queue[i].convert2str(), "\n"};
			`uvm_info("IS_MATCH", str, UVM_DEBUG);
		*/

		match = this_queue.find_last_index with (
				item.row == data.row && item.col == data.col &&
				(item.timestamp == -1 || data.timestamp == -1 || item.timestamp == data.timestamp)
		);

		return (match.size() > 0) ? match[0] : -1;
	endfunction

	function void report(int cut = 0);
		string report;
		int ghost_stages [arcadia_ver::num_stages-1:0];
		int sim_time_length;
		int tot_prev;
		real rate_mhz, rate_mhz_cm2;
		pixel_recv q [$];

		/*
		*  Stage report
		*/

		report = {"Overall report:\n\n",
		    "+-----+--------------+--------------+---------------------+-------------------+-------------------+-------------------+-------------------+-------------------+\n",
		    "|  S  |   PACKETS    |     NULL     |        TOTAL        |      MATCHES      |       TIMERR      |       GHOSTS      |     DUPLICATES    |      EXPIRED      |\n",
		    "+-----+--------------+--------------+---------------------+-------------------+-------------------+-------------------+-------------------+-------------------+\n"
		};


		for(int stage=arcadia_ver::num_stages; stage>=0; stage--) begin
			int p    = cfg.recv_pkt[stage];
			int m    = cfg.match_pix[stage];
			int t    = cfg.timerr_pix[stage];
			int d    = cfg.dupl_pix[stage];
			int g    = cfg.ghost_pix[stage];
			int e    = cfg.expired_pix[stage];
			int n    = cfg.recv_pkt_null[stage];
			int tot  = m + d + g;
			real m_p = m*100.0/tot;
			real t_p = t*100.0/m;
			real d_p = d*100.0/tot;
			real g_p = g*100.0/tot;
			real e_p = e*100.0/tot;
			real tot_p = (tot_prev == 0) ? 100.0 : (tot*100.0/tot_prev);
			tot_prev = tot;
			
			report = {report,
			$sformatf("|  %1d  | %12d | %12d | %9d (%6.2f%%) | %7d (%6.2f%%) | %7d (%6.2f%%) | %7d (%6.2f%%) | %7d (%6.2f%%) | %7d (%6.2f%%) |",
						 stage,   p,     n,     tot,  tot_p,    m,    m_p,      t,    t_p,      g,    g_p,      d,    d_p,      e,    e_p
			), "\n"};

			q = expired_queue[stage].find( x ) with (x.ghost != -1);
			foreach (q[i])
				ghost_stages[q[i].ghost]++;
		end

		/*
		*  Timing displacement
		*/

		for(int i=0; i<=2**`ARCADIA_EVENT_ID_BITS; i++)
			cfg.timerr[i] = 0;

		q = stage_queue[0].find( x ) with (x.timestamp_delta != 0);
		foreach (q[i])
			cfg.timerr[q[i].timestamp_delta+2**(`ARCADIA_EVENT_ID_BITS-1)]++;

		report = {report,
		    "+-----+--------------+--------------+---------------------+-------------------+-------------------+-------------------+-------------------+-------------------+\n",
			"\n",
			"+-----------+-------------------------+\n",
			"|  TIMERR   |          COUNTS         |\n",
			"+-----------+-------------------------+\n"
		};

		for(int i=0; i<=2**`ARCADIA_EVENT_ID_BITS; i++) if(cfg.timerr[i] > 0)
			report = {report, $sformatf("|    %2d     |   %9d (%7.2f%%)  |\n",
								i-2**(`ARCADIA_EVENT_ID_BITS-1), cfg.timerr[i], ($itor(cfg.timerr[i])*100/cfg.recv_pix[0])
			)};

		report = {report,
			"+-----------+-------------------------+\n",
			"\n"
		};

		/*
		* Expired
		*/
		report = {report,
			"Expired:\n"
		};
		for(int stage=arcadia_ver::num_stages; stage>=0; stage--) begin
			int size = expired_queue[stage].size();
		
			if(size) begin
				report = {report,
					$sformatf("Stage %0d:\n", stage),
					dump_queue(expired_queue[stage], cut)
				};

				for(int i=size-1; i>=0; i--) begin
					expired_queue_old[stage].push_front(expired_queue[stage][i]);
					expired_queue[stage].delete(i);
				end
			end
		end
		
		report = {report,
			"Ghosts:\n"
		};
		for(int stage=arcadia_ver::num_stages-1; stage>=0; stage--) begin
			int size = ghost_queue[stage].size();
		
			if(size) begin
				report = {report,
					$sformatf("Stage %0d:\n", stage),
					dump_queue(ghost_queue[stage], cut)
				};

				for(int i=size-1; i>=0; i--) begin
					ghost_queue_old[stage].push_front(ghost_queue[stage][i]);
					ghost_queue[stage].delete(i);
				end
			end
		end

//			str = {str, $sformatf("This_queue becomes:\n%s", dump_queue(stage_queue[data.stage]))};
		/*
		*  Statistics
		*/
		sim_time_length = ((cfg.sim_time_end == 0) ? $time : cfg.sim_time_end) - cfg.sim_time_start;
		rate_mhz = real'(cfg.sent_pix)/(sim_time_length)*1e3;
		rate_mhz_cm2 = rate_mhz/(25e-6*25e-6*`ARCADIA_MATRIX_HEIGHT*`ARCADIA_MATRIX_WIDTH)*(0.01*0.01);

		report = {report,
			"Statistics:\n",
			$sformatf("Injected %d pixels in %d ns. Rate: %.3f MHz (%.3f MHz/cm2)", cfg.sent_pix, sim_time_length, rate_mhz, rate_mhz_cm2)
		};
/*
		report = {report,
		    "+-----+--------------+-------------------+-------------------+-------------------+-------------------+-------------------+\n",
		    "\n"
			"+--------------------+----"
		};

		for(int stage=0; stage<arcadia_ver::num_stages; stage++) begin
		};
*/

		`uvm_info("HIT_SCOREBOARD", report, UVM_NONE);
	endfunction

	function void stage_report(int stage);
		pixel_recv q [$];
		int total, matchs, ghosts, duplicates, tot_count;
		string sb_stagename, report;

		total = stage_queue[stage].size();

		q = stage_queue[stage].find( x ) with (x.ghost == -1 & x.duplicate == 0);
		matchs = q.size();
		q = stage_queue[stage].find( x ) with (x.ghost != -1);
		ghosts = q.size();
		q = stage_queue[stage].find( x ) with (x.duplicate != 0);
		duplicates = q.size();
		sb_stagename = $sformatf("SB_STAGE%0d", stage);

		tot_count = cfg.match_pix[stage]+cfg.dupl_pix[stage]+cfg.ghost_pix[stage];

		report = 
			$sformatf("Stage report\n\nTotal:      %4d/%4d\nMatches:    %4d/%4d\nGhosts:     %4d/%4d\nDuplicates: %4d/%4d\nThe stage now contains:\n%s\nExpired items:\n%s\n\n", total, tot_count, matchs, cfg.match_pix[stage], ghosts, cfg.ghost_pix[stage], duplicates, cfg.dupl_pix[stage], dump_queue(stage_queue[stage]), dump_queue(expired_queue[stage]));

		`uvm_info(sb_stagename, report, UVM_NONE);
	endfunction

	function void partial_report(int stage);
		string report = {
			$sformatf("\n\t\tReceived/sent pixels:         %5d/%5d (%2.3f%%)", cfg.recv_pix[stage], cfg.sent_pix, real'(cfg.recv_pix[stage]*100/cfg.sent_pix)),
			$sformatf("\n\t\tMatched biass:                 %5d/%5d (%2.3f%% of sent)", cfg.match_pix[stage],
				cfg.sent_pix, real'(cfg.match_pix[stage])*100/cfg.sent_pix),
			$sformatf("\n\t\tTiming displaced biass:        %5d/%5d (%2.3f%% of sent)", cfg.timerr_pix[stage],
				cfg.sent_pix, real'(cfg.timerr_pix[stage])*100/cfg.sent_pix),

		//`uvm_info("SB", $sformatf("\n\t\t                   ... with disp = 1:  %5d (%2.3f%% of sent)", disp1,  real'(disp1)*100/cfg.sent_pix),

			$sformatf("\n\t\tDeadtime (not injected) biass: %5d/%5d (%2.3f%% of sent)", cfg.dead_pix,
				cfg.sent_pix, real'(cfg.dead_pix)*100/cfg.sent_pix),

			$sformatf("\n\t\tGhost biass:                   %5d/%5d (%2.3f%% of recv)", cfg.ghost_pix[stage],
				cfg.recv_pix[stage], real'(cfg.ghost_pix[stage])*100/cfg.recv_pix[stage]),
			$sformatf("\n\t\tDuplicate biass:               %5d/%5d (%2.3f%% of recv)", cfg.dupl_pix[stage],
				cfg.recv_pix[stage], real'(cfg.dupl_pix[stage])*100/cfg.recv_pix[stage]),
			$sformatf("\n\t\tNull packets:                 %5d/%5d (%2.3f%% of recv)", cfg.recv_pkt_null[stage],
			    cfg.recv_pkt[stage], real'(cfg.recv_pkt_null[stage])*100/cfg.recv_pkt[stage])
		};

		`uvm_info("SB", $sformatf("In-itinere Summary:\n%s", report), report_level+UVM_MEDIUM);
	endfunction

	function void clear();
		`uvm_info("SB", "Clearing counters and queues", UVM_LOW);

		cfg.sent_pix      = 0;
		cfg.dead_pix      = 0;

		dead_queue    = {};
		match_queue   = {};
		timerr_queue  = {};
		dupl_queue    = {};

		for(int i=0; i<arcadia_ver::num_stages; i++) begin
			cfg.recv_pkt_null[i] = 0;
			cfg.recv_pkt[i]     = 0;
			cfg.recv_pix[i]     = 0;
			cfg.disp_pix[i]     = 0;
			cfg.ghost_pix[i]    = 0;
			cfg.timerr_pix[i]   = 0;
			cfg.dupl_pix[i]     = 0;
			cfg.expired_pix[i]  = 0;
		end

		for(int i=0; i<=arcadia_ver::num_stages; i++) begin
			cfg.match_pix[i]  = 0;

			stage_queue[i]    = {};
			expired_queue[i]  = {};
			ghost_queue[i]    = {};
		end
	endfunction

	function void adjust_timestamp();
		int timerr_max, timerr_max_counts;

		timerr_max = 0; timerr_max_counts = cfg.timerr[0];
		for(int i=1; i<=2**`ARCADIA_EVENT_ID_BITS; i++)
			if(cfg.timerr[i] > timerr_max_counts) begin
				timerr_max = i;
				timerr_max_counts = cfg.timerr[timerr_max];
			end

		timerr_max -= 2**(`ARCADIA_EVENT_ID_BITS-1);

		`uvm_info("ENV", $sformatf("Found most common timestamp to be %2d. Performing calibration.", timerr_max), UVM_LOW);

		cfg.timestamp += timerr_max;
	endfunction
endclass
