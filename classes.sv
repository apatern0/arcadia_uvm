`include "defines.sv"
`include "interfaces.sv"

`include "arcadia_ver.sv"

`ifndef ARCADIA_UVM_CLASSES
`define ARCADIA_UVM_CLASSES

import uvm_pkg::*;
`include "uvm_macros.svh"

class bias_setting extends uvm_object;
endclass

class pixel_recv extends uvm_object;
	`uvm_object_utils(pixel_recv)

	static int incr = 0;
	int idx;

	int row;
	int col;
	int fe_timewalk;
	int fe_deadtime;

	int timestamp;
	int timestamp_delta;

	int simtime [arcadia_ver::num_stages:0];

	int ghost;
	int duplicate;

	int stage;

	virtual function string convert2str();
		string str;

		if (ghost != -1)
			str = $sformatf("GHOST (#%1d)   ", ghost);
		else if(duplicate != -1)
			str = $sformatf("DUPL (#%5d)", duplicate);
		else if(timestamp_delta != 0)
			str = $sformatf("TIMERR (%3d) ", timestamp_delta);
		else
			str = "MATCH        ";

		str = $sformatf("%5d - %s @ %3d [%4d][%4d]: section_gen[%2d].col_gen[%2d].col.core_gen[%3d].core.region_gen[%3d].pr.Diodes[%2d][%2d] - Sim Times: ", idx, str, timestamp, row, col, `COL_IDX(col), `COLUMN_IDX(col), `CORE_IDX(row), `REGION_IDX(row), `REGION_AFE_ROW(row), `REGION_AFE_COL(col));

		for(int i=((ghost == -1) ? arcadia_ver::num_stages : ghost); i>stage;i--)
			str = {str, $sformatf("%10d, ", simtime[i])};

		str = {str, $sformatf("%10d", simtime[stage])};

		return str;
	endfunction

	function new(string name = "pixel_recv");
		super.new(name);

		ghost = -1;
		duplicate = -1;
		idx = incr++;
	endfunction
endclass
typedef pixel_recv pixel_recv_queue[$];

class cfg_t extends uvm_object;
	`uvm_object_utils(cfg_t)

	int num_stages;
	int stages [arcadia_ver::num_stages:0];

	int recv_pkt [arcadia_ver::num_stages:0];
	int recv_pkt_null [arcadia_ver::num_stages:0];
	int recv_pix [arcadia_ver::num_stages:0];
	event recv_pkt_event [arcadia_ver::num_stages-1:0];

	int sent_pkt;
	int sent_pix;
	int dead_pix;

	int disp_pix   [2**`ARCADIA_EVENT_ID_BITS-1:0];

	int match_pix   [arcadia_ver::num_stages:0];
	int ghost_pix   [arcadia_ver::num_stages:0];
	int timerr_pix  [arcadia_ver::num_stages:0];
	int dupl_pix    [arcadia_ver::num_stages:0];
	int expired_pix [arcadia_ver::num_stages:0];

	int timestamp;
	int timerr [2**`ARCADIA_EVENT_ID_BITS:0];

	int sim_time_start;
	int sim_time_end;
	int expiration_time;

	function new(string name = "cfg_t");
		super.new(name);
	endfunction
endclass

`endif
