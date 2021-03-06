// Audio Controlling in FPGA
//   ____________           ________
//   |          | ->->->->- |      | ->->->->- ||
//   |   FPGA   |           | AC97 |           || Audio Line In / Line Out
//   | Virtex-5 | -<-<-<-<- |      | -<-<-<-<- ||
//   ~~~~~~~~~~~~           ~~~~~~~~
//
// Access between FPGA and AC97, input: FPGA <- AC97, output: FPGA -> AC97

module audio_if (
	// 27Mhz Clock and Board Reset
	input				clk						,// FPGA Clock: 27Mhz
	input				rst_n					,// reset of FPGA, down:1, up:0

	// IF between AC97
	input				audio_bit_clk			,// 12.288MHz bit clock generated by AC97
	output				flash_audio_reset_b		,// reset of AC97, negative reset
	input				audio_sdata_in			,// serial data from AC97, 256bit per frame
	output	reg			audio_sdata_out			,// serial data to AC97, 256bit per frame
	output	reg			audio_sync				,// AC-Link frame sync, 12.288MHz/256 = 48kHz
	    
	// USER IF
	input					btn_c				,
	input					btn_n				,
	input					btn_e				,
	input					btn_s				,
	input					btn_w				,

	// TO AUDIO_PROC.V
	output	reg				oAudio_sync			,
	output	reg	[20-1: 0]	oAudio_L			,
	output	reg	[20-1: 0]	oAudio_R			,
	input					iAudio_sync			,
	input		[20-1: 0]	iAudio_L			,
	input		[20-1: 0]	iAudio_R			,
	
	// LED OUTPUT for DEBUGGING
	output		[ 8-1: 0]	tp
);

parameter	S_CTRL_IDLE	= 2'b00;
parameter	S_CTRL_RST	= 2'b01;
parameter	S_CTRL_INIT	= 2'b10;
parameter	S_CTRL_AUD 	= 2'b11;

parameter	S_AC97_IDLE	= 2'b00;
parameter	S_AC97_RST 	= 2'b01;
parameter	S_AC97_INIT	= 2'b10;
parameter	S_AC97_AUD 	= 2'b11;

//parameter	P_LENGTH_AUDIO_RST = 20'd27000;
parameter	P_LENGTH_AUDIO_RST = 20'd54000;
//parameter	P_LENGTH_AUDIO_RST = 20'd108000;

//////////////////////////////////////////////////////////////////////////////
// REGS & WIRES
//////////////////////////////////////////////////////////////////////////////
wire				btn_c_pls	;
wire				btn_e_pls	;
wire				btn_w_pls	;
wire				btn_s_pls	;
wire				btn_n_pls	;

reg		[ 2-1: 0]	curSTATE_CTRL	;
reg		[ 2-1: 0]	nxtSTATE_CTRL	;

reg		[ 2-1: 0]	curSTATE_AC97	;
reg		[ 2-1: 0]	nxtSTATE_AC97	;

reg		[20-1: 0]	cnt_audio_rst		;
wire				done_audio_rst	;

reg		[ 8-1: 0]	cnt_audio_sync	;

reg		[ 8-1: 0]	cnt_audio_init	;

reg		[256-1:0] 	data_in_tmp				;
reg		[256-1:0] 	data_in					;
reg		[256-1:0] 	data_in_d1				;
reg		[256-1:0] 	data_in_from_proc		;

reg		[256-1:0] 	data_out		;
reg		[256-1:0] 	data_out_tmp	;

reg					mode_mute		;
reg					mode_no_proc	;

wire				ac97_init_done;

wire led0, led1, led2, led3, led4, led5, led6, led7;

// ASYNC: SYSCLK -> AUDCLK
wire	chg_state_ctrl_to_idle	;
wire	chg_state_ctrl_to_rst	;
wire	chg_state_ctrl_to_init	;
wire	chg_state_ctrl_to_aud	;

reg		chg_state_ctrl_to_idle_lvl	;
reg		chg_state_ctrl_to_rst_lvl	;
reg		chg_state_ctrl_to_init_lvl	;
reg		chg_state_ctrl_to_aud_lvl	;

reg		[2:0]	chg_state_ctrl_to_idle_lvl_d	;
reg		[2:0]	chg_state_ctrl_to_rst_lvl_d		;
reg		[2:0]	chg_state_ctrl_to_init_lvl_d	;
reg		[2:0]	chg_state_ctrl_to_aud_lvl_d		;

wire	chg_state_ctrl_to_idle_audclk	;
wire	chg_state_ctrl_to_rst_audclk	;
wire	chg_state_ctrl_to_init_audclk	;
wire	chg_state_ctrl_to_aud_audclk	;

assign	chg_state_ctrl_to_idle	= (curSTATE_CTRL!=S_CTRL_IDLE)&(nxtSTATE_CTRL==S_CTRL_IDLE);
assign	chg_state_ctrl_to_rst	= (curSTATE_CTRL!=S_CTRL_RST )&(nxtSTATE_CTRL==S_CTRL_RST );
assign	chg_state_ctrl_to_init	= (curSTATE_CTRL!=S_CTRL_INIT)&(nxtSTATE_CTRL==S_CTRL_INIT);
assign	chg_state_ctrl_to_aud	= (curSTATE_CTRL!=S_CTRL_AUD )&(nxtSTATE_CTRL==S_CTRL_AUD );

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		chg_state_ctrl_to_idle_lvl	<= 1'b0;
		chg_state_ctrl_to_rst_lvl	<= 1'b0;
		chg_state_ctrl_to_init_lvl	<= 1'b0;
		chg_state_ctrl_to_aud_lvl	<= 1'b0;
	end else begin
		if (chg_state_ctrl_to_idle	) chg_state_ctrl_to_idle_lvl	<= ~chg_state_ctrl_to_idle_lvl	 ;
		if (chg_state_ctrl_to_rst	) chg_state_ctrl_to_rst_lvl		<= ~chg_state_ctrl_to_rst_lvl	 ;
		if (chg_state_ctrl_to_init	) chg_state_ctrl_to_init_lvl	<= ~chg_state_ctrl_to_init_lvl	 ;
		if (chg_state_ctrl_to_aud	) chg_state_ctrl_to_aud_lvl		<= ~chg_state_ctrl_to_aud_lvl	 ;
	end
end

always @ (posedge audio_bit_clk or negedge rst_n) begin
	if (~rst_n) begin
		chg_state_ctrl_to_idle_lvl_d	<= {3{1'b0}};
		chg_state_ctrl_to_rst_lvl_d		<= {3{1'b0}};
		chg_state_ctrl_to_init_lvl_d	<= {3{1'b0}};
		chg_state_ctrl_to_aud_lvl_d		<= {3{1'b0}};
	end else begin
		chg_state_ctrl_to_idle_lvl_d	<= {chg_state_ctrl_to_idle_lvl_d[1:0],	chg_state_ctrl_to_idle_lvl	};
		chg_state_ctrl_to_rst_lvl_d		<= {chg_state_ctrl_to_rst_lvl_d[1:0],	chg_state_ctrl_to_rst_lvl	};
		chg_state_ctrl_to_init_lvl_d	<= {chg_state_ctrl_to_init_lvl_d[1:0],	chg_state_ctrl_to_init_lvl	};
		chg_state_ctrl_to_aud_lvl_d		<= {chg_state_ctrl_to_aud_lvl_d[1:0],	chg_state_ctrl_to_aud_lvl	};
	end
end

assign	chg_state_ctrl_to_idle_audclk	= chg_state_ctrl_to_idle_lvl_d[1]	^ chg_state_ctrl_to_idle_lvl_d[2]	;
assign	chg_state_ctrl_to_rst_audclk	= chg_state_ctrl_to_rst_lvl_d[1]	^ chg_state_ctrl_to_rst_lvl_d[2]	;
assign	chg_state_ctrl_to_init_audclk	= chg_state_ctrl_to_init_lvl_d[1]	^ chg_state_ctrl_to_init_lvl_d[2]	;
assign	chg_state_ctrl_to_aud_audclk	= chg_state_ctrl_to_aud_lvl_d[1]	^ chg_state_ctrl_to_aud_lvl_d[2]	;


// ASYNC: AUDCLK -> SYSCLK
wire	chg_state_ac97_to_idle	;
wire	chg_state_ac97_to_rst	;
wire	chg_state_ac97_to_init	;
wire	chg_state_ac97_to_aud	;

reg		chg_state_ac97_to_idle_lvl	;
reg		chg_state_ac97_to_rst_lvl	;
reg		chg_state_ac97_to_init_lvl	;
reg		chg_state_ac97_to_aud_lvl	;

reg		[2:0]	chg_state_ac97_to_idle_lvl_d	;
reg		[2:0]	chg_state_ac97_to_rst_lvl_d		;
reg		[2:0]	chg_state_ac97_to_init_lvl_d	;
reg		[2:0]	chg_state_ac97_to_aud_lvl_d		;

wire	chg_state_ac97_to_idle_sysclk	;
wire	chg_state_ac97_to_rst_sysclk	;
wire	chg_state_ac97_to_init_sysclk	;
wire	chg_state_ac97_to_aud_sysclk	;

assign	chg_state_ac97_to_idle	= (curSTATE_AC97!=S_AC97_IDLE)&(nxtSTATE_AC97==S_AC97_IDLE);
assign	chg_state_ac97_to_rst	= (curSTATE_AC97!=S_AC97_RST )&(nxtSTATE_AC97==S_AC97_RST );
assign	chg_state_ac97_to_init	= (curSTATE_AC97!=S_AC97_INIT)&(nxtSTATE_AC97==S_AC97_INIT);
assign	chg_state_ac97_to_aud	= (curSTATE_AC97!=S_AC97_AUD )&(nxtSTATE_AC97==S_AC97_AUD );

always @ (posedge audio_bit_clk or negedge rst_n) begin
	if (~rst_n) begin
		chg_state_ac97_to_idle_lvl	<= 1'b0;
		chg_state_ac97_to_rst_lvl	<= 1'b0;
		chg_state_ac97_to_init_lvl	<= 1'b0;
		chg_state_ac97_to_aud_lvl	<= 1'b0;
	end else begin
		if (chg_state_ac97_to_idle	) chg_state_ac97_to_idle_lvl	<= ~chg_state_ac97_to_idle_lvl	 ;
		if (chg_state_ac97_to_rst	) chg_state_ac97_to_rst_lvl		<= ~chg_state_ac97_to_rst_lvl	 ;
		if (chg_state_ac97_to_init	) chg_state_ac97_to_init_lvl	<= ~chg_state_ac97_to_init_lvl	 ;
		if (chg_state_ac97_to_aud	) chg_state_ac97_to_aud_lvl		<= ~chg_state_ac97_to_aud_lvl	 ;
	end
end

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		chg_state_ac97_to_idle_lvl_d	<= {3{1'b0}};
		chg_state_ac97_to_rst_lvl_d		<= {3{1'b0}};
		chg_state_ac97_to_init_lvl_d	<= {3{1'b0}};
		chg_state_ac97_to_aud_lvl_d		<= {3{1'b0}};
	end else begin
		chg_state_ac97_to_idle_lvl_d	<= {chg_state_ac97_to_idle_lvl_d[1:0],	chg_state_ac97_to_idle_lvl	};
		chg_state_ac97_to_rst_lvl_d		<= {chg_state_ac97_to_rst_lvl_d[1:0],	chg_state_ac97_to_rst_lvl	};
		chg_state_ac97_to_init_lvl_d	<= {chg_state_ac97_to_init_lvl_d[1:0],	chg_state_ac97_to_init_lvl	};
		chg_state_ac97_to_aud_lvl_d		<= {chg_state_ac97_to_aud_lvl_d[1:0],	chg_state_ac97_to_aud_lvl	};
	end
end

assign	chg_state_ac97_to_idle_sysclk	= chg_state_ac97_to_idle_lvl_d[1]	^ chg_state_ac97_to_idle_lvl_d[2]	;
assign	chg_state_ac97_to_rst_sysclk	= chg_state_ac97_to_rst_lvl_d[1]	^ chg_state_ac97_to_rst_lvl_d[2]	;
assign	chg_state_ac97_to_init_sysclk	= chg_state_ac97_to_init_lvl_d[1]	^ chg_state_ac97_to_init_lvl_d[2]	;
assign	chg_state_ac97_to_aud_sysclk	= chg_state_ac97_to_aud_lvl_d[1]	^ chg_state_ac97_to_aud_lvl_d[2]	;


//////////////////////////////////////////////////////////////////////////////
// FSM: STATE_CTRL
//////////////////////////////////////////////////////////////////////////////
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		curSTATE_CTRL	<= S_CTRL_IDLE;
	end else begin
		curSTATE_CTRL	<= nxtSTATE_CTRL;
	end
end

always @ (*) begin
	case (curSTATE_CTRL)
		S_CTRL_IDLE:begin
			if (btn_c_pls)
				nxtSTATE_CTRL	<= S_CTRL_RST;
			else 
				nxtSTATE_CTRL	<= S_CTRL_IDLE;
		end
		S_CTRL_RST:begin
			if (done_audio_rst)
				nxtSTATE_CTRL	<= S_CTRL_INIT;
			else 
				nxtSTATE_CTRL	<= S_CTRL_RST;
		end
		S_CTRL_INIT:begin
			if (chg_state_ac97_to_aud_sysclk)
				nxtSTATE_CTRL	<= S_CTRL_AUD;
			else 
				nxtSTATE_CTRL	<= S_CTRL_INIT;
		end
		S_CTRL_AUD:begin
			if (btn_c_pls)
				nxtSTATE_CTRL	<= S_CTRL_RST;
			else 
				nxtSTATE_CTRL	<= S_CTRL_AUD;
		end
		default:begin
			nxtSTATE_CTRL	<= S_CTRL_IDLE;
		end
	endcase
end


always @ (posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		cnt_audio_rst	<= {20{1'b0}};
	end else if (done_audio_rst) begin
		cnt_audio_rst	<= {20{1'b0}};
	end else if (chg_state_ctrl_to_rst) begin
		cnt_audio_rst	<= {20{1'b0}};
	end else if (curSTATE_CTRL==S_CTRL_RST) begin
		cnt_audio_rst	<= cnt_audio_rst + 1'b1;
	end
end
assign done_audio_rst = (curSTATE_CTRL==S_CTRL_RST) ? (cnt_audio_rst >= P_LENGTH_AUDIO_RST-1) : 1'b0 ;

//////////////////////////////////////////////////////////////////////////////
// FSM: STATE_AC97
//////////////////////////////////////////////////////////////////////////////
always @ (posedge audio_bit_clk or negedge rst_n) begin
	if (~rst_n) begin
		curSTATE_AC97	<= S_AC97_IDLE;
	end else begin
		curSTATE_AC97	<= nxtSTATE_AC97;
	end
end

always @ (*) begin
	case (curSTATE_AC97)
		S_AC97_IDLE:begin
			if (chg_state_ctrl_to_init_audclk)
				nxtSTATE_AC97	<= S_AC97_INIT;
			else 
				nxtSTATE_AC97	<= S_AC97_IDLE;
		end
//		S_AC97_RST:begin
//			if (/* TRIG */)
//				nxtSTATE_AC97	<= S_AC97_INIT;
//			else 
//				nxtSTATE_AC97	<= S_AC97_RST;
//		end
		S_AC97_INIT:begin
			if (ac97_init_done)
				nxtSTATE_AC97	<= S_AC97_AUD;
			else 
				nxtSTATE_AC97	<= S_AC97_INIT;
		end
		S_AC97_AUD:begin
			if (chg_state_ctrl_to_init_audclk)
				nxtSTATE_AC97	<= S_AC97_INIT;
			else 
				nxtSTATE_AC97	<= S_AC97_AUD;
		end
		default:begin
			nxtSTATE_AC97	<= S_AC97_IDLE;
		end
	endcase
end

always @ (posedge audio_bit_clk or negedge rst_n) begin
	if (~rst_n) begin
		cnt_audio_sync	<= {8{1'b0}};
	end else if (chg_state_ac97_to_init|chg_state_ac97_to_aud) begin
		cnt_audio_sync	<= {8{1'b0}};
	end else if (curSTATE_AC97==S_AC97_INIT) begin
		if (cnt_audio_sync>=8'd255) begin
			cnt_audio_sync	<= {8{1'b0}};
		end else begin
			cnt_audio_sync	<= cnt_audio_sync + 1'b1;
		end
	end else if (curSTATE_AC97==S_AC97_AUD) begin
		if (cnt_audio_sync>=8'd255) begin
			cnt_audio_sync	<= {8{1'b0}};
		end else begin
			cnt_audio_sync	<= cnt_audio_sync + 1'b1;
		end
	end
end

always @ (posedge audio_bit_clk or negedge rst_n) begin
	if (~rst_n) begin
		cnt_audio_init	<= {8{1'b0}};
	end else if (chg_state_ac97_to_init) begin
		cnt_audio_init	<= {8{1'b0}};
	end else if (curSTATE_AC97==S_AC97_INIT) begin
		if (cnt_audio_sync>=8'd255) cnt_audio_init	<= cnt_audio_init + 1'b1;
	end
end

assign ac97_init_done = (curSTATE_AC97==S_AC97_INIT) ? ((cnt_audio_init==8'd5)&(cnt_audio_sync==8'd255)) : 1'b0 ;

always @ (posedge audio_bit_clk or negedge rst_n) begin
	if (~rst_n) begin
		data_out	<= {256{1'b0}};
	end else if (chg_state_ac97_to_init) begin	// REG 00 write: Register Reset
		data_out[255:240] <= 16'b1110_0000_0000_0000;
		data_out[239:220] <= 20'b0000_0000_0000_0000_0000;
		data_out[219:200] <= 20'b0000_0000_0010_1000_0000;
		data_out[199:160] <= {40{1'b0}};
		data_out[159:  0] <= {160{1'b0}};
	end else if (curSTATE_AC97==S_AC97_INIT) begin // DON'T TOUCH
		if (cnt_audio_sync>=8'd255) begin
			if (cnt_audio_init==8'd0) begin		// REG 00 write: Register Reset
				data_out[255:240] <= 16'b1110_0000_0000_0000;
				data_out[239:220] <= 20'b0000_0000_0000_0000_0000;
				data_out[219:200] <= 20'b0000_0000_0010_1000_0000;
				data_out[199:160] <= {40{1'b0}};
				data_out[159:  0] <= {160{1'b0}};
			end else if (cnt_audio_init==8'd1) begin		// REG 76 write: DAM, FMXE
				data_out[255:240] <= 16'b1110_0000_0000_0000;
				data_out[239:220] <= 20'b0111_0110_0000_0000_0000;
				data_out[219:200] <= 20'b0000_1010_0000_0000_0000;
				data_out[199:160] <= {40{1'b0}};
				data_out[159:  0] <= {160{1'b0}};
			end else if (cnt_audio_init==8'd2) begin// REG 02 write: Master Volume Mute OFF
				data_out[255:240] <= 16'b1111_1000_0000_0000;
				data_out[239:220] <= 20'b0000_0010_0000_0000_0000;
				data_out[219:200] <= 20'b0000_0000_0000_0000_0000;
				data_out[199:160] <= {40{1'b0}};
				data_out[159:0] <= {160{1'b0}};
			end else if (cnt_audio_init==8'd3) begin// REG 18 write: PCM Out Mute OFF
				data_out[255:240] <= 16'b1111_1000_0000_0000;
				data_out[239:220] <= 20'b0001_1000_0000_0000_0000;
				data_out[219:200] <= 20'b0000_0000_0000_0000_0000;
				data_out[199:160] <= {40{1'b0}};
				data_out[159:0] <= {160{1'b0}};
			end else if (cnt_audio_init==8'd4) begin// REG 1C write: Input Mute OFF
				data_out[255:240] <= 16'b1111_1000_0000_0000;
				data_out[239:220] <= 20'b0001_1100_0000_0000_0000;
				data_out[219:200] <= 20'b0000_0000_0000_0000_0000;
				data_out[199:160] <= {40{1'b0}};
				data_out[159:0] <= {160{1'b0}};
			end 
		end // DON'T TOUCH
	end else if (curSTATE_AC97==S_AC97_AUD) begin // EDITABLE
		data_out[256-1:240] <= 16'b1001_1000_0000_0000;
		data_out[240-1:220] <= 20'b0000_0000_0000_0000_0000;
		data_out[220-1:200] <= 20'b0000_0000_0000_0000_0000;
		data_out[200-1:180] <= (mode_mute) ? {20{1'b0}} : (mode_no_proc) ? data_in[199:180] : data_in_from_proc[199:180];
		data_out[180-1:160] <= (mode_mute) ? {20{1'b0}} : (mode_no_proc) ? data_in[179:160] : data_in_from_proc[179:160];
		data_out[160-1:  0] <= {160{1'b0}};
	end
end

// DATA RCV
always @(posedge audio_bit_clk or negedge rst_n) begin
	if (~rst_n) begin
		data_in_tmp	<= {256{1'b0}};
	end else begin
		data_in_tmp	<= { data_in_tmp[254:0], audio_sdata_in };
	end
end

always @(posedge audio_bit_clk or negedge rst_n) begin
	if (~rst_n) begin
		data_in		<= {256{1'b0}};
	end else if (curSTATE_AC97==S_AC97_AUD) begin
		//if (cnt_audio_sync==8'd255) data_in <= { data_in_tmp[254:0], audio_sdata_in };
		if (cnt_audio_sync==8'd001) data_in <= { data_in_tmp[254:0], audio_sdata_in };
	end else begin
		data_in[255:240] <= 16'b1001_1000_0000_0000;
		data_in[239:220] <= 20'b0000_0000_0000_0000_0000;
		data_in[219:200] <= 20'b0000_0000_0000_0000_0000;
		data_in[199:180] <= 20'b0000_0000_0000_0000_0000;
		data_in[179:160] <= 20'b0000_0000_0000_0000_0000;
		data_in[159:  0] <= {160{1'b0}};
	end
end

always @(posedge audio_bit_clk or negedge rst_n) begin
	if (~rst_n) begin
		audio_sync		<= 1'b0;
	end else if (curSTATE_AC97==S_AC97_INIT) begin
		audio_sync	<= (cnt_audio_sync<8'd16) ? 1'b1 : 1'b0 ;
	end else if (curSTATE_AC97==S_AC97_AUD ) begin
		audio_sync	<= (cnt_audio_sync<8'd16) ? 1'b1 : 1'b0 ;
	end else begin
		audio_sync		<= 1'b0;
	end
end

wire	[ 8-1: 0] index_audio_bit;
assign index_audio_bit = 8'd255 - cnt_audio_sync;

//always @(posedge audio_bit_clk or negedge rst_n) begin
//	if (~rst_n) begin
//		audio_sdata_out		<= 1'b0;
//	end else if (curSTATE_AC97==S_AC97_INIT) begin
//		audio_sdata_out		<= data_out[index_audio_bit];
//	end else if (curSTATE_AC97==S_AC97_AUD ) begin
//		audio_sdata_out		<= data_out[index_audio_bit];
//	end
//end
reg audio_sdata_out_tmp;
always @(posedge audio_bit_clk or negedge rst_n) begin
	if (~rst_n) begin
		audio_sdata_out_tmp		<= 1'b0;
	end else if (curSTATE_AC97==S_AC97_INIT) begin
		audio_sdata_out_tmp		<= data_out[index_audio_bit];
	end else if (curSTATE_AC97==S_AC97_AUD ) begin
		audio_sdata_out_tmp		<= data_out[index_audio_bit];
	end
end
always @(posedge audio_bit_clk or negedge rst_n) begin
	if (~rst_n) begin
		audio_sdata_out		<= 1'b0;
	end else begin
		audio_sdata_out		<= audio_sdata_out_tmp;
	end
end


always @ (posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		mode_mute	<= 1'b0;
	end else if (btn_s_pls) begin
		mode_mute	<= ~mode_mute;
	end
end

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		mode_no_proc	<= 1'b0;
	end else if (btn_w_pls) begin
		mode_no_proc	<= ~mode_no_proc;
	end
end

always @ (posedge audio_bit_clk or negedge rst_n) begin
	if (~rst_n) begin
		data_in_d1	<= {256{1'b0}};
	end else begin
		data_in_d1	<= data_in;
	end
end

wire	data_in_chg;
assign	data_in_chg = (data_in!=data_in_d1);

reg	data_in_chg_lvl;
always @ (posedge audio_bit_clk or negedge rst_n) begin
	if (~rst_n) begin
		data_in_chg_lvl	<= 1'b0;
	end else if (data_in_chg) begin
		data_in_chg_lvl	<= ~data_in_chg_lvl;
	end
end

reg	data_in_chg_lvl_sysclk_d1;
reg	data_in_chg_lvl_sysclk_d2;
reg	data_in_chg_lvl_sysclk_d3;
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		data_in_chg_lvl_sysclk_d1	<= 1'b0;
		data_in_chg_lvl_sysclk_d2	<= 1'b0;
		data_in_chg_lvl_sysclk_d3	<= 1'b0;
	end else begin
		data_in_chg_lvl_sysclk_d1	<= data_in_chg_lvl;
		data_in_chg_lvl_sysclk_d2	<= data_in_chg_lvl_sysclk_d1;
		data_in_chg_lvl_sysclk_d3	<= data_in_chg_lvl_sysclk_d2;
	end
end

wire	data_in_chg_sysclk;
assign	data_in_chg_sysclk = data_in_chg_lvl_sysclk_d2^data_in_chg_lvl_sysclk_d3;

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		oAudio_sync		<= 1'b0;
	end else if (data_in_chg_sysclk) begin
		oAudio_sync		<= 1'b1;
	end else begin
		oAudio_sync		<= 1'b0;
	end
end

always @ (posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		oAudio_L	<= {20{1'b0}};
		oAudio_R	<= {20{1'b0}};
	end else if (data_in_chg_sysclk) begin
		oAudio_L	<= data_in[199:180];
		oAudio_R	<= data_in[179:160];
	end
end

reg	iAudio_sync_lvl_sysclk;
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		iAudio_sync_lvl_sysclk <= 1'b0;
	end else if (iAudio_sync) begin
		iAudio_sync_lvl_sysclk <= ~iAudio_sync_lvl_sysclk;
	end
end

reg	iAudio_sync_lvl_audclk_d1;
reg	iAudio_sync_lvl_audclk_d2;
reg	iAudio_sync_lvl_audclk_d3;
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		iAudio_sync_lvl_audclk_d1	<= 1'b0;
		iAudio_sync_lvl_audclk_d2	<= 1'b0;
		iAudio_sync_lvl_audclk_d3	<= 1'b0;
	end else begin
		iAudio_sync_lvl_audclk_d1	<= iAudio_sync_lvl_sysclk;
		iAudio_sync_lvl_audclk_d2	<= iAudio_sync_lvl_audclk_d1;
		iAudio_sync_lvl_audclk_d3	<= iAudio_sync_lvl_audclk_d2;
	end
end

wire	iAudio_sync_pls_audclk;
assign	iAudio_sync_pls_audclk = iAudio_sync_lvl_audclk_d2^iAudio_sync_lvl_audclk_d3;

always @(posedge audio_bit_clk or negedge rst_n) begin
	if (~rst_n) begin
		data_in_from_proc[255:240] <= 16'b1001_1000_0000_0000;
		data_in_from_proc[239:220] <= 20'b0000_0000_0000_0000_0000;
		data_in_from_proc[219:200] <= 20'b0000_0000_0000_0000_0000;
		data_in_from_proc[199:180] <= 20'b0000_0000_0000_0000_0000;
		data_in_from_proc[179:160] <= 20'b0000_0000_0000_0000_0000;
		data_in_from_proc[159:  0] <= {160{1'b0}};
	end else if (iAudio_sync_pls_audclk) begin
		data_in_from_proc[255:240] <= 16'b1001_1000_0000_0000;
		data_in_from_proc[239:220] <= 20'b0000_0000_0000_0000_0000;
		data_in_from_proc[219:200] <= 20'b0000_0000_0000_0000_0000;
		data_in_from_proc[199:180] <= iAudio_L;
		data_in_from_proc[179:160] <= iAudio_R;
		data_in_from_proc[159:  0] <= {160{1'b0}};
	end
end

//////////////////////////////////////////////////////////////////////////////
// OUTPUT
//////////////////////////////////////////////////////////////////////////////
assign flash_audio_reset_b = (curSTATE_CTRL==S_CTRL_RST) ? 1'b0 : 1'b1 ;

//////////////////////////////////////////////////////////////////////////////
// TP
//////////////////////////////////////////////////////////////////////////////
reg	flash_audio_reset_b_d1;
reg	flash_audio_reset_b_d2;
reg	flash_audio_reset_b_d3;
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		flash_audio_reset_b_d1 <= 1'b1;
		flash_audio_reset_b_d2 <= 1'b1;
		flash_audio_reset_b_d3 <= 1'b1;
	end else begin
		flash_audio_reset_b_d1 <= flash_audio_reset_b;
		flash_audio_reset_b_d2 <= flash_audio_reset_b_d1;
		flash_audio_reset_b_d3 <= flash_audio_reset_b_d2;
	end
end

wire flash_audio_reset_b_ris;
assign flash_audio_reset_b_ris = flash_audio_reset_b_d2 & ~flash_audio_reset_b_d3;

reg	flash_audio_reset_b_lvl;
always @ (posedge clk or negedge rst_n) begin
	if (~rst_n) begin
		flash_audio_reset_b_lvl <= 1'b0;
	end else if (flash_audio_reset_b_ris) begin
		flash_audio_reset_b_lvl <= ~flash_audio_reset_b_lvl;
	end
end

reg		[20-1: 0]	r_cnt_audio_bit_clk;
always @ (posedge audio_bit_clk or negedge rst_n) begin
	if (~rst_n) begin
		r_cnt_audio_bit_clk	<= {16{1'b0}};
	end else begin
		r_cnt_audio_bit_clk <= r_cnt_audio_bit_clk + 1'b1;
	end
end 
assign tp = { mode_no_proc, mode_mute, flash_audio_reset_b_lvl, r_cnt_audio_bit_clk[20-1], curSTATE_AC97, curSTATE_CTRL };


//////////////////////////////////////////////////////////////////////////////
// INST
//////////////////////////////////////////////////////////////////////////////
button_detector A_BUTTON_PLS (
.clk				(clk				),//i
.rst_n				(rst_n				),//i
.BUTTON_C			(btn_c				),//i
.BUTTON_E			(btn_e				),//i
.BUTTON_W			(btn_w				),//i
.BUTTON_S			(btn_s				),//i
.BUTTON_N			(btn_n				),//i
.O_PLS_BUTTON_C		(btn_c_pls			),//o
.O_PLS_BUTTON_E		(btn_e_pls			),//o
.O_PLS_BUTTON_W		(btn_w_pls			),//o
.O_PLS_BUTTON_S		(btn_s_pls			),//o
.O_PLS_BUTTON_N		(btn_n_pls			) //o
);

// FOR DEBUGGING
wire [16-1: 0] TP_TAG   = data_out[256-1:240];
wire [20-1: 0] TP_SLOT01 = data_out[240-1:220];
wire [20-1: 0] TP_SLOT02 = data_out[220-1:200];
wire [20-1: 0] TP_SLOT03 = data_out[200-1:180];
wire [20-1: 0] TP_SLOT04 = data_out[180-1:160];
wire [20-1: 0] TP_SLOT05 = data_out[160-1:140];
wire [20-1: 0] TP_SLOT06 = data_out[140-1:120];
wire [20-1: 0] TP_SLOT07 = data_out[120-1:100];
wire [20-1: 0] TP_SLOT08 = data_out[100-1: 80];
wire [20-1: 0] TP_SLOT09 = data_out[ 80-1: 60];
wire [20-1: 0] TP_SLOT10 = data_out[ 60-1: 40];
wire [20-1: 0] TP_SLOT11 = data_out[ 40-1: 20];
wire [20-1: 0] TP_SLOT12 = data_out[ 20-1:  0];

wire	TP_TAG_VALID_FRAME	= TP_TAG[16-1];
wire	TP_TAG_SLOT01		= TP_TAG[15-1];
wire	TP_TAG_SLOT02		= TP_TAG[14-1];
wire	TP_TAG_SLOT03		= TP_TAG[13-1];
wire	TP_TAG_SLOT04		= TP_TAG[12-1];
wire	TP_TAG_SLOT05		= TP_TAG[11-1];
wire	TP_TAG_SLOT06		= TP_TAG[10-1];
wire	TP_TAG_SLOT07		= TP_TAG[ 9-1];
wire	TP_TAG_SLOT08		= TP_TAG[ 8-1];
wire	TP_TAG_SLOT09		= TP_TAG[ 7-1];
wire	TP_TAG_SLOT10		= TP_TAG[ 6-1];
wire	TP_TAG_SLOT11		= TP_TAG[ 5-1];
wire	TP_TAG_SLOT12		= TP_TAG[ 4-1];
wire	TP_TAG_ALWAYS_0		= TP_TAG[ 3-1];
wire	TP_TAG_ID1			= TP_TAG[ 2-1];
wire	TP_TAG_ID0			= TP_TAG[ 1-1];

wire			TP_SLOT01_RW		= TP_SLOT01[20-1:19];
wire [ 7-1: 0]	TP_SLOT01_CMD_ADDR	= TP_SLOT01[19-1:12];
wire [12-1: 0]	TP_SLOT01_REV		= TP_SLOT01[12-1: 0];

wire [16-1: 0]	TP_SLOT02_CMD_DATA	= TP_SLOT02[19-1: 4];
wire [ 4-1: 0]	TP_SLOT02_REV		= TP_SLOT02[ 4-1: 0];

endmodule
