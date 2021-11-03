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

	virtual task post_main_phase(uvm_phase phase);
		super.main_phase(phase);

		active_phase();
	endtask

	virtual task pre_shutdown_phase(uvm_phase phase);
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
			recv.simtime[arcadia_ver::num_stages] = $time;
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
