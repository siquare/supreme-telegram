// N point FFT
module top;
   reg CK, RST, ST;
   reg [15:0] I1, I2;
   wire [15:0] O1, O2;
   integer     i;
   

   FFT1 fft (I1, I2, O1, O2, ST, FI, RST, CK );

   initial begin
      CK=0;
      RST=1;
      ST=0;
      #100 RST=0;
      #100 RST=1;
      #205 ST=1;


I1 = 16'b 0000000000000000 ;
I2 = 16'b 0000000000111011 ;
#20 ST=0;
I1 = 16'b 0000000001110101 ;
I2 = 16'b 0000000010101010 ;
#20 ST=0;
I1 = 16'b 0000000011011001 ;
I2 = 16'b 0000000011111111 ;
#20 ST=0;
I1 = 16'b 0000000100011011 ;
I2 = 16'b 0000000100101101 ;
#20 ST=0;
I1 = 16'b 0000000100110011 ;
I2 = 16'b 0000000100101101 ;
#20 ST=0;
I1 = 16'b 0000000100011011 ;
I2 = 16'b 0000000011111111 ;
#20 ST=0;
I1 = 16'b 0000000011011001 ;
I2 = 16'b 0000000010101010 ;
#20 ST=0;
I1 = 16'b 0000000001110101 ;
I2 = 16'b 0000000000111011 ;
#20 ST=0;
I1 = 16'b 0000000000000000 ;
I2 = 16'b 1111111111000101 ;
#20 ST=0;
I1 = 16'b 1111111110001011 ;
I2 = 16'b 1111111101010110 ;
#20 ST=0;
I1 = 16'b 1111111100100111 ;
I2 = 16'b 1111111100000001 ;
#20 ST=0;
I1 = 16'b 1111111011100101 ;
I2 = 16'b 1111111011010011 ;
#20 ST=0;
I1 = 16'b 1111111011001101 ;
I2 = 16'b 1111111011010011 ;
#20 ST=0;
I1 = 16'b 1111111011100101 ;
I2 = 16'b 1111111100000001 ;
#20 ST=0;
I1 = 16'b 1111111100100111 ;
I2 = 16'b 1111111101010110 ;
#20 ST=0;
I1 = 16'b 1111111110001011 ;
I2 = 16'b 1111111111000101 ;
#20 ST=0;
I1 = 16'b 0000000000000000 ;
I2 = 16'b 0000000000111011 ;
#20 ST=0;
I1 = 16'b 0000000001110101 ;
I2 = 16'b 0000000010101010 ;
#20 ST=0;
I1 = 16'b 0000000011011001 ;
I2 = 16'b 0000000011111111 ;
#20 ST=0;
I1 = 16'b 0000000100011011 ;
I2 = 16'b 0000000100101101 ;
#20 ST=0;
I1 = 16'b 0000000100110011 ;
I2 = 16'b 0000000100101101 ;
#20 ST=0;
I1 = 16'b 0000000100011011 ;
I2 = 16'b 0000000011111111 ;
#20 ST=0;
I1 = 16'b 0000000011011001 ;
I2 = 16'b 0000000010101010 ;
#20 ST=0;
I1 = 16'b 0000000001110101 ;
I2 = 16'b 0000000000111011 ;
#20 ST=0;
I1 = 16'b 0000000000000000 ;
I2 = 16'b 1111111111000101 ;
#20 ST=0;
I1 = 16'b 1111111110001011 ;
I2 = 16'b 1111111101010110 ;
#20 ST=0;
I1 = 16'b 1111111100100111 ;
I2 = 16'b 1111111100000001 ;
#20 ST=0;
I1 = 16'b 1111111011100101 ;
I2 = 16'b 1111111011010011 ;
#20 ST=0;
I1 = 16'b 1111111011001101 ;
I2 = 16'b 1111111011010011 ;
#20 ST=0;
I1 = 16'b 1111111011100101 ;
I2 = 16'b 1111111100000001 ;
#20 ST=0;
I1 = 16'b 1111111100100111 ;
I2 = 16'b 1111111101010110 ;
#20 ST=0;
I1 = 16'b 1111111110001011 ;
I2 = 16'b 1111111111000101 ;

      #100000 $finish;
   end

   always #10 CK <= ~CK;

endmodule


module FFT1 (I1, I2, O1, O2, ST, FI, RST, CK );
   input [15:0] I1, I2;
   output [15:0] O1, O2;

   input CK, RST, ST;
   output FI;

   reg [5:0] WADDR, RADDR1, RADDR2;  // log_2(N) bit
   reg 	       STATUS;

   wire [31:0] Y1, Y2, W1, W2, DI1, DI2, DO1, DO2;
   wire 	Fin, Ini;
   
   assign FI = Fin;
   assign O1 = (Fin==1) ? DO1[31:16] : 0;
   assign O2 = (Fin==1) ? DO2[31:16] : 0;
   assign DI1 = (Ini == 1) ? {I1,16'b0} : Y1;
   assign DI2 = (Ini == 1) ? {I2,16'b0} : Y2;


   MM mem( DI1, DI2, DO1, DO2, W1, W2, CK, ST, RST, Fin, Ini  );
   butt b ( Y1, Y2, DO1, DO2, W1, W2 );
endmodule   


module MM (DI1, DI2, DO1, DO2, Wo1, Wo2, CK, S, RST, Fin, Ini );
   input CK, RST, S;
   input [31:0] DI1,DI2;
   output [31:0] DO1, DO2, Wo1, Wo2;
   output Fin, Ini;
   

   reg [31:0] 	 M1[0:127], W[0:63];
   reg [5:0] 	 CI, CO;
   reg [7:0] 	 ST;
   reg 	[1:0]	 STATUS;

   integer 	 i;

   wire [4:0] 	 WA1, WA2;

   assign Fin=ST[7];
   assign Ini=ST[0];
   
 	 
   assign Wo1 = W[WA1];
   assign Wo2 = W[WA2];



   wire [6:0] 	 MRA1, MRA2, MWA1, MWA2;

   assign MWA1={CI,1'b0};
   assign MWA2={CI,1'b1};
   assign MRA1=ST[7]==1 ? {CI,1'b0} : {CO[5],1'b0,CO[4:0]};
   assign MRA2=ST[7]==1 ? {CI,1'b1} : {CO[5],1'b1,CO[4:0]};

   assign DO1 = M1[MRA1];
   assign DO2 = M1[MRA2];



   assign WA1 = ( ST[1]==1 ? 5'b0 :
		  ( ST[2] == 1 ? {(CI[4]&CI[0]),4'b0} :
		    ( ST[3] == 1 ? {(CI[4]&CI[0]),(CI[4]&CI[1]),3'b0} :
		      ( ST[4] == 1 ? {(CI[4]&CI[0]),(CI[4]&CI[1]),(CI[4]&CI[2]),2'b0} : 
			( ST[5] == 1 ? {(CI[4]&CI[0]),(CI[4]&CI[1]),(CI[4]&CI[2]),(CI[4]&CI[3]),1'b0} : 5'b 0 )))) );
   assign WA2 = ( ST[1]==1 ? {CI[4],4'b0} :
		  ( ST[2] == 1 ? {(CI[4]&CI[0]),CI[4],3'b0} :
		    ( ST[3] == 1 ? {(CI[4]&CI[0]),(CI[4]&CI[1]),CI[4],2'b0} :
		      ( ST[4] == 1 ? {(CI[4]&CI[0]),(CI[4]&CI[1]),(CI[4]&CI[2]),CI[4],1'b0} : 
			( ST[5] == 1 ? {(CI[4]&CI[0]),(CI[4]&CI[1]),(CI[4]&CI[2]),(CI[4]&CI[3]),CI[4]} : 5'b 0 ))) ));


   always @(posedge CK) begin
      if( !RST ) begin
	 STATUS <= 0;

W[0] <= { 16'b 0000000100000000, 16'b 0000000000000000 };
W[1] <= { 16'b 0000000011111110, 16'b 1111111111100111 };
W[2] <= { 16'b 0000000011111011, 16'b 1111111111001111 };
W[3] <= { 16'b 0000000011110100, 16'b 1111111110110110 };
W[4] <= { 16'b 0000000011101100, 16'b 1111111110011111 };
W[5] <= { 16'b 0000000011100001, 16'b 1111111110001000 };
W[6] <= { 16'b 0000000011010100, 16'b 1111111101110010 };
W[7] <= { 16'b 0000000011000101, 16'b 1111111101011110 };
W[8] <= { 16'b 0000000010110101, 16'b 1111111101001011 };
W[9] <= { 16'b 0000000010100010, 16'b 1111111100111011 };
W[10] <= { 16'b 0000000010001110, 16'b 1111111100101100 };
W[11] <= { 16'b 0000000001111000, 16'b 1111111100011111 };
W[12] <= { 16'b 0000000001100001, 16'b 1111111100010100 };
W[13] <= { 16'b 0000000001001010, 16'b 1111111100001100 };
W[14] <= { 16'b 0000000000110001, 16'b 1111111100000101 };
W[15] <= { 16'b 0000000000011001, 16'b 1111111100000010 };
W[16] <= { 16'b 0000000000000000, 16'b 1111111100000000 };
W[17] <= { 16'b 1111111111100111, 16'b 1111111100000010 };
W[18] <= { 16'b 1111111111001111, 16'b 1111111100000101 };
W[19] <= { 16'b 1111111110110110, 16'b 1111111100001100 };
W[20] <= { 16'b 1111111110011111, 16'b 1111111100010100 };
W[21] <= { 16'b 1111111110001000, 16'b 1111111100011111 };
W[22] <= { 16'b 1111111101110010, 16'b 1111111100101100 };
W[23] <= { 16'b 1111111101011110, 16'b 1111111100111011 };
W[24] <= { 16'b 1111111101001011, 16'b 1111111101001011 };
W[25] <= { 16'b 1111111100111011, 16'b 1111111101011110 };
W[26] <= { 16'b 1111111100101100, 16'b 1111111101110010 };
W[27] <= { 16'b 1111111100011111, 16'b 1111111110001000 };
W[28] <= { 16'b 1111111100010100, 16'b 1111111110011111 };
W[29] <= { 16'b 1111111100001100, 16'b 1111111110110110 };
W[30] <= { 16'b 1111111100000101, 16'b 1111111111001111 };
W[31] <= { 16'b 1111111100000010, 16'b 1111111111100111 };

      end else if (STATUS == 0 && S == 1 ) begin // if ( !RST )
	 STATUS <= 1;
	 CI <= 6'b 0;
	 CO <= {1'b1,5'b0};
	 ST <= 1;
      end else if( STATUS == 1 ) begin
	 CI <= CI+1;
	 CO <= CO+1;

	 M1[MWA1] <= DI1;
	 M1[MWA2] <= DI2;
	 if( CI[4:0] == 5'b 11111 ) ST <= ST << 1;
      end
   end
   
   

endmodule // MM


module butt(y0,y1,x0,x1,W1,W2);
   input [31:0] x0,x1,W1,W2;
   output [31:0] y0,y1;
   
   wire [31:0] xx0, xx1;

   assign xx0 = addc( x0, x1 );
   assign xx1 = subc( x0, x1 );
   assign y0 = mulc(xx0, W1);
   assign y1 = mulc(xx1, W2);

   function [31:0] addc;
      input [31:0] a, b;
      reg [15:0]   yr, yi;
      begin
	 yr = a[31:16] + b[31:16];
	 yi = a[15:0] + b[15:0];
	 addc = {yr, yi};
      end
   endfunction
   function [31:0] subc;
      input [31:0] a, b;
      reg [15:0]   yr, yi;
      begin
	 yr = a[31:16] - b[31:16];
	 yi = a[15:0] - b[15:0];
	 subc = {yr, yi};
      end
   endfunction
//  function [31:0] mulc;
//    input [31:0] a, b;
//    reg [15:0] yr, yi;
//    begin
//      yr = a[31:16]*b[31:16] - a[15:0]*b[15:0];
//      yi = a[15:0]*b[31:16] + a[31:16]*b[15:0];
//      mulc = {yr, yi};
//    end
//  endfunction
   function [31:0] mulc;
      input [31:0] a, b;
      reg [31:0]   yr1, yr2, yi1, yi2;
      reg [15:0]   ar, ai, br, bi, yyr1, yyr2, yyi1, yyi2, yr, yi;
      begin
         if( a[31] == 0 ) ar = a[31:16]; else ar = ~(a[31:16]-1);
         if( a[15] == 0 ) ai = a[15:0]; else ai = ~(a[15:0]-1);
         if( b[31] == 0 ) br = b[31:16]; else br = ~(b[31:16]-1);
         if( b[15] == 0 ) bi = b[15:0]; else bi = ~(b[15:0]-1);
	 
	 
         yr1 = ar * br;
         yr2 = ai * bi;
	 
         yi1 = ar * bi;
         yi2 = ai * br;
	 
         if( (a[31]^b[31])==0 ) yyr1 = yr1[23:8]; else yyr1 = ~yr1[23:8] + 1;
         if( (a[15]^b[15])==0 ) yyr2 = yr2[23:8]; else yyr2 = ~yr2[23:8] + 1;
         yr = yyr1 - yyr2;
	 
         if( (a[31]^b[15])==0 ) yyi1 = yi1[23:8]; else yyi1 = ~yi1[23:8] + 1;
         if( (a[15]^b[31])==0 ) yyi2 = yi2[23:8]; else yyi2 = ~yi2[23:8] + 1;
         yi = yyi1 + yyi2;
	 
	 mulc = {yr, yi};
      end
   endfunction
endmodule
