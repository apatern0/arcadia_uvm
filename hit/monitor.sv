`include "uvm/if.sv"

import uvm_pkg::*;
`include "uvm_macros.svh"

class hit_monitor extends uvm_monitor;
	`uvm_component_utils(hit_monitor)
	function new(string name="hit_monitor", uvm_component parent=null);
		super.new(name, parent);
	endfunction

	int stage;

	string mon_name;
	virtual chip_if vif;
	cfg_t cfg;
	uvm_analysis_port #(pixel_recv) m_recv_imp;

	bit stop_on_null;

	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);

		if (!uvm_config_db#(virtual chip_if)::get(this, "", "chip_vif", vif))
			`uvm_fatal("MON", "Could not get vif")

		if (!uvm_config_db#(int)::get(this, "", "stage", stage))
			`uvm_fatal("MON", "Could not get stage")

		if (!uvm_config_db#(cfg_t)::get(this, "", "cfg", cfg))
			`uvm_fatal("MON", "Could not get cfg")

		mon_name = $sformatf("MON%0d", stage);
		m_recv_imp = new ("m_recv_imp", this);
	endfunction

	virtual task active_phase();
	endtask;

	virtual task post_configure_phase(uvm_phase phase);
		super.post_configure_phase(phase);

		active_phase();
	endtask

	virtual task main_phase(uvm_phase phase);
		super.main_phase(phase);

		active_phase();
	endtask

	function automatic void analyze_packet (
		logic [7:0] data,
		int core_pr,
		int column,
		int sec,
		int timestamp,
		int tag
	);
		int timestamp_corrected;
		int count, i;

		timestamp_corrected = (timestamp == -1) ? -1 : (2**`ARCADIA_EVENT_ID_BITS + timestamp) % (2**`ARCADIA_EVENT_ID_BITS);

		for(int i=0; i<`ARCADIA_PR_PIXELS; i++) begin
			pixel_recv recv;

			if(data[i] == 0)
				continue;

			count++;

			recv = pixel_recv::type_id::create();
			recv.row = core_pr*`ARCADIA_PR_HEIGHT + i/`ARCADIA_PR_WIDTH;
			recv.col = (`ARCADIA_SECTION_COLUMNS*sec + column)*`ARCADIA_COLUMN_WIDTH + i%`ARCADIA_PR_WIDTH;

			recv.timestamp = timestamp_corrected;
			recv.simtime[`ARCADIA_TAP_STAGES] = $time;
			recv.stage = stage;
			m_recv_imp.write(recv);
		end

		`uvm_info(mon_name, $sformatf("Time %7d. Timestamp %4d. -> Receiving %3d hits from section %2d column %2d core %2d region %2d vector %0db%0b",
			$time, timestamp_corrected, count, sec, column,
			core_pr[`ARCADIA_CORE_PR_ADDRESS_BITS-1-:`ARCADIA_CORE_ADDRESS_BITS], core_pr[`ARCADIA_PR_ADDRESS_BITS-1:0],
			`ARCADIA_PR_HITMAP_BITS, data
		), UVM_HIGH);

	endfunction
endclass

class core_monitor extends hit_monitor;
	`uvm_component_utils(core_monitor)
	function new(string name="core_monitor", uvm_component parent=null);
		super.new(name, parent);
	endfunction

	region_probe_if_array region_probes;
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);

		if (!uvm_config_db#(region_probe_if_array)::get(this, "", "region_probes", region_probes))
			`uvm_fatal("MON", "Could not get region_probes")
	endfunction

	virtual task active_phase;
		for(int i=0; i<`ARCADIA_SECTIONS; i++)
		for(int c=0; c<`ARCADIA_SECTION_COLUMNS; c++)
		for(int o=0; o<`ARCADIA_COLUMN_CORES; o++)
		for(int p=0; p<`ARCADIA_CORE_PRS; p++) fork
			automatic int sec  = i;
			automatic int col  = c;
			automatic int core = o;
			automatic int pr   = p;
			forever begin
				logic [31:0] packet;
				logic [`ARCADIA_CORE_PR_ADDRESS_BITS-1:0] hit_core_pr;
				logic [`ARCADIA_PR_DATA_BITS-1:0]         hit_data;
				logic [`ARCADIA_EVENT_ID_BITS-1:0]        hit_timestamp;

				`uvm_info(mon_name, $sformatf("Listening on data from sec %2d col %2d core %2d pr %2d...", sec, col, core, pr), UVM_DEBUG);
				region_probes[sec][col][core][pr].wait_and_get(packet);
				cfg.recv_pkt[stage]++;
				->> cfg.recv_pkt_event[stage];

				{hit_timestamp, hit_core_pr, hit_data} = packet;

				if(packet[7:0] == 0) begin
					cfg.recv_pkt_null[stage]++;
					`uvm_warning(mon_name, $sformatf("Receiving null packet from sec %2d col %2d core %2d pr %2d...", sec, col, core, pr));

					if (stop_on_null) $stop;
				end else begin
					`uvm_info(mon_name, $sformatf("Received packet 0b%b (sec %2d col %2d corepr %4d data 0b%8b) w/ts %4d.", packet, sec, col, hit_core_pr, hit_data, hit_timestamp), UVM_HIGH);
					analyze_packet(hit_data, hit_core_pr, col, sec, -1, 4'd0);
				end // end else begin
			end // forever begin
		join_none
	endtask
endclass

class col_monitor extends hit_monitor;
	`uvm_component_utils(col_monitor)
	function new(string name="col_monitor", uvm_component parent=null);
		super.new(name, parent);
	endfunction

	col_probe_if_array col_probes;
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);

		if (!uvm_config_db#(col_probe_if_array)::get(this, "", "col_probes", col_probes))
			`uvm_fatal("MON", "Could not get col_probes")
	endfunction

	virtual task active_phase;
		for(int i=0; i<`ARCADIA_SECTIONS; i++) for(int c=0; c<`ARCADIA_SECTION_COLUMNS; c++) fork
			automatic int sec = i;
			automatic int col = c;
			forever begin
				logic [31:0] packet;
				logic [`ARCADIA_CORE_PR_ADDRESS_BITS-1:0] hit_core_pr;
				logic [`ARCADIA_PR_DATA_BITS-1:0]         hit_data;
				logic [`ARCADIA_EVENT_ID_BITS-1:0]        hit_timestamp;

				`uvm_info(mon_name, $sformatf("Listening on data from sec %2d col %2d...", sec, col), UVM_DEBUG);
				col_probes[sec][col].wait_and_get(packet);

				{hit_timestamp, hit_core_pr, hit_data} = packet;

				if(packet[7:0] == 0) begin
					cfg.recv_pkt_null++;
					`uvm_warning(mon_name, $sformatf("Time %7d. Receiving null packet from col %2d...", $time, col));

					if (stop_on_null) $stop;
				end else begin
					`uvm_info(mon_name, $sformatf("Received packet 0b%b (sec %2d col %2d corepr %4d data 0b%8b) w/ts %4d.", packet, sec, col, hit_core_pr, hit_data, hit_timestamp), UVM_HIGH);
					analyze_packet(hit_data, hit_core_pr, col, sec, -1, 4'd0);
				end // end else begin
			end // forever begin
		join_none
	endtask
endclass

class colmem_out_monitor extends hit_monitor;
	`uvm_component_utils(colmem_out_monitor)
	function new(string name="colmem_out_monitor", uvm_component parent=null);
		super.new(name, parent);
	endfunction

	colmem_out_probe_if_array colmem_out_probes;
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);

		if (!uvm_config_db#(colmem_out_probe_if_array)::get(this, "", "colmem_out_probes", colmem_out_probes))
			`uvm_fatal("MON", "Could not get colmem_out_probes")
	endfunction

	virtual task active_phase;
		for(int i=0; i<`ARCADIA_SECTIONS; i++) for(int c=0; c<`ARCADIA_SECTION_COLUMNS; c++) fork
			automatic int sec = i;
			automatic int col = c;
			forever begin
				logic [31:0] packet;
				logic [`ARCADIA_CORE_PR_ADDRESS_BITS-1:0] hit_core_pr;
				logic [`ARCADIA_PR_DATA_BITS-1:0]         hit_data;
				logic [`ARCADIA_EVENT_ID_BITS-1:0]        hit_timestamp;

				`uvm_info(mon_name, $sformatf("Listening on data from sec %2d col %2d...", sec, col), UVM_DEBUG);
				colmem_out_probes[sec][col].wait_and_get(packet);

				{hit_timestamp, hit_core_pr, hit_data} = packet;

				if(packet[7:0] == 0) begin
					cfg.recv_pkt_null++;
					`uvm_warning(mon_name, $sformatf("Time %7d. Receiving null packet from colmem_out %2d...", $time, col));

					if (stop_on_null) $stop;
				end else begin
					`uvm_info(mon_name, $sformatf("Received packet 0b%b (sec %2d col %2d corepr %4d data 0b%8b) w/ts %4d.", packet, sec, col, hit_core_pr, hit_data, hit_timestamp), UVM_HIGH);
					analyze_packet(hit_data, hit_core_pr, col, sec, hit_timestamp, 4'd0);
				end // end else begin
			end // forever begin
		join_none
	endtask
endclass

class pre_serializer_monitor extends hit_monitor;
	`uvm_component_utils(pre_serializer_monitor)
	function new(string name="pre_serializer_monitor", uvm_component parent=null);
		super.new(name, parent);
	endfunction

	pre_serializer_probe_if_array pre_serializer_probes;
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);

		if (!uvm_config_db#(pre_serializer_probe_if_array)::get(this, "", "pre_serializer_probes", pre_serializer_probes))
			`uvm_fatal("MON", "Could not get pre_serializer_probe")
	endfunction

	virtual task active_phase;
		
		for(int i=0; i<`ARCADIA_SECTIONS; i++) fork
			automatic int sec = i;
			forever begin
				logic [31:0] packet;
				`uvm_info(mon_name, $sformatf("Listening on data from serializer %2d...", sec), UVM_DEBUG);
				pre_serializer_probes[sec].wait_and_get(packet);

				if(packet[7:0] == 0) begin
					cfg.recv_pkt_null++;
					`uvm_warning(mon_name, $sformatf("Time %7d. Receiving null packet in ser %2d...", $time, sec));

					if (stop_on_null) $stop;
				end else begin
					`uvm_info(mon_name, $sformatf("Received packet 0b%b w/ts %4d.", packet, packet[28:25]), UVM_HIGH);
					analyze_packet(
						packet[7:0],
						packet[16:8],
						packet[20:17],
						packet[24:21],
						packet[28:25],
						packet[31:29]
					);
				end
			end
		join_none
	endtask
endclass

class serializers_monitor extends hit_monitor;
	`uvm_component_utils(serializers_monitor)
	function new(string name="serializers_monitor", uvm_component parent=null);
		super.new(name, parent);
	endfunction

	serializer_probe_if_array serializer_probes;
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);

		if (!uvm_config_db#(serializer_probe_if_array)::get(this, "", "serializer_probes", serializer_probes))
			`uvm_fatal("MON", "Could not get serializer_probes")
	endfunction

	virtual task active_phase;
		for(int i=0; i<`ARCADIA_SECTIONS; i++) fork
			automatic int sec = i;
			forever begin
				logic [31:0] packet;
		
				`uvm_info(mon_name, $sformatf("Listening on data from serializer %2d...", sec), UVM_DEBUG);
				serializer_probes[sec].wait_and_get(packet);

				if(packet[7:0] == 0) begin
					cfg.recv_pkt_null++;
					`uvm_warning(mon_name, $sformatf("Time %7d. Receiving null packet from serializer %2d...", $time, sec));

					if (stop_on_null) $stop;
				end else begin
					`uvm_info(mon_name, $sformatf("Received packet 0b%b w/ts %4d.", packet, packet[28:25]), UVM_HIGH);
					analyze_packet (
						packet[7:0],
						packet[16:8],
						packet[20:17],
						packet[24:21],
						packet[28:25],
						packet[31:29]
					);
				end
			end
		join_none
	endtask
endclass
