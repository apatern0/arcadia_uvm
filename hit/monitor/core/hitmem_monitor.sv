interface region_probe_if (
	input [`ARCADIA_PR_DATA_BITS-1:0] region_hitmap
);
	logic [`ARCADIA_CORE_ADDRESS_BITS-1:0] core_address;
	logic [`ARCADIA_PR_ADDRESS_BITS-1:0] pr_address;

	logic [`ARCADIA_PR_DATA_BITS-1:0] region_hitmap_old;
	logic [`ARCADIA_PR_DATA_BITS-1:0] region_hitmap_x;
	logic [`ARCADIA_PR_DATA_BITS-1:0] region_hitmap_new;
	logic any_change;
	logic any_new;

	always @(*) begin
		region_hitmap_x = region_hitmap ^ region_hitmap_old;
		any_change = (|region_hitmap_x);
	end

	initial region_hitmap_old = 0;

	task wait_and_get(output CoreDataIf res);
		forever begin
			@(posedge any_change);

			region_hitmap_new = region_hitmap & ~region_hitmap_old;
			region_hitmap_old = region_hitmap;
			any_new = (|region_hitmap_new);

			if(any_new) break;
		end

		res = '{
			CorePrAddress: {core_address, pr_address},
			Data: region_hitmap_x,
			Event: -1
		};
	endtask
endinterface
typedef virtual region_probe_if region_probe_if_array [`ARCADIA_SECTIONS-1:0] [`ARCADIA_SECTION_COLUMNS-1:0] [`ARCADIA_COLUMN_CORES-1:0] [`ARCADIA_CORE_PRS-1:0];

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

/*

interface core_probe_if (
	input CoreIfAsc fromPrev,
	input CoreIfDesc toPrev,

	input CoreIfDesc fromNext,
	input CoreIfAsc toNext
);
	logic [`ARCADIA_CORE_ADDRESS_BITS-1:0] core_address;

	task edge_ready();
		@(posedge fromPrev.Read iff (toPrev.Token & ~fromNext.Token & ~(|fromPrev.CorePixelSelect[`ARCADIA_CORE_ADDRESS_BITS-1:0])));
	endtask

	task wait_and_get(output CoreDataIf res);
		edge_ready();
		res = '{
			CorePrAddress: {core_address, toPrev.PrAddress},
			Data: toPrev.Data,
			Event: -1
		};
	endtask
endinterface
typedef virtual core_probe_if core_probe_if_array [`ARCADIA_SECTIONS-1:0] [`ARCADIA_SECTION_COLUMNS-1:0] [`ARCADIA_COLUMN_CORES-1:0];

*/
