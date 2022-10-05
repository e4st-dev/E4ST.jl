function [mpc, roffer, contab] = t_case_e4st_dac2
%T_CASE_E4ST_DAC2  Three-bus test case for t_e4st_dac()
% Three-bus test case for testing e4st_solve() with one direct air capture 
% unit. % Contains three buses, two of which have a generator and one of 
% which has a direct air capture unit. The gererator at bus 1 has a 
% maximum power output of 10 MW and variable cost of $50/MW. The generator
% at bus 2 has a maximum power output of 23 MW and variable cost of $20/MW.
% There are four hours. For hour 1 has a load of 15 MW, while hour 2
% has a load of 25 MW. Hour 3 has a load of 26 MW and hour 4 has a load of
% 15 MW. Power plant 1 emits 10 short tons CO2/MWh electricity and power 
% plant 2 emits 0.1 short tons CO2/MWh. There is one direct air capture 
% unit that has a capture rate of 7 short tons CO2/ MWh. It has a variable
% cost of $50/MWh. There is a net emissions cap of 0 short tons.
% This is the most basic test of direct air capture.

%% define named indices into data matrices
define_constants
c = idx_dcline;

%% MATPOWER Case Format : Version 2
mpc.version = '2';

%%-----  Power Flow Data  -----%%
%% system MVA base
mpc.baseMVA = 100;

%% bus data
%	bus_i	type	Pd	Qd	Gs	Bs	area	Vm	Va	baseKV	zone	Vmax	Vmin
mpc.bus = [
	1	3	0	0	0	0	1	1	0	135	1	1.05	0.95;
	2	1	0	0	0	0	2	1	0	135	1	1.1	    0.95;
    3	1	0	0	0	0	2	1	0	135	1	1.1	    0.95;
];

%% generator data
%	bus	Pg	Qg	Qmax	Qmin	Vg	mBase	status	Pmax	Pmin	Pc1	Pc2	Qc1min	Qc1max	Qc2min	Qc2max	ramp_agc	ramp_10	ramp_30	ramp_q	apf
mpc.gen = [
	1	10	0	5	-5	1	100	1	10	0	0	0	0	0	0	0	0	Inf	0	0	0;
	2	23	0	10	-10	1	100	1	23	0	0	0	0	0	0	0	0	Inf	0	0	0;
	% Direct Air Capture Device
    3  -20	0	0	0	1	100	1	1  -20	0	0	0	0	0	0	Inf	Inf	Inf	Inf	0;

	% dispatchable loads
	1	-10	0	0	0	1	100	1	0	-10	0	0	0	0	0	0	Inf	Inf	Inf	Inf	0;
	2	-5	0	0	0	1	100	1	0	-5	0	0	0	0	0	0	Inf	Inf	Inf	Inf	0;
];

%% branch data
%	fbus	tbus	r	x	b	rateA	rateB	rateC	ratio	angle	status	angmin	angmax
mpc.branch = [
	1	2	0.01	0.01	0.014	130	130	130	1	0	1	-360	360;
    2	3	0.01	0.01	0.014	130	130	130	1	0	1	-360	360;
];

%%-----  OPF Data  -----%%
%% generator cost data
%	1	startup	shutdown	n	x1	y1	...	xn	yn
%	2	startup	shutdown	n	c(n-1)	...	c0
mpc.gencost = [
	2	0	0	2	50	0;
	2	0	0	2	20	0;
	% Direct Air Capture
 	2	0	0	2	-50 	0; %variable cost $50/MWh
	% dispatchable loads
	2	0	0	2	5000	0;
	2	0	0	2	5000	0;
];

mpc.total_output.map = [1, 1, 1, 0, 0];
mpc.total_output.min = [0];
mpc.total_output.max = [0];
mpc.total_output.coeff = [10; 0.1; 7; 0; 0]; %coeff of DAC positive bc power negative
mpc.total_output.type = [1];


%% reserve and delta offers
%     +      +        -      -
%  active  active  active  active
% reserve  reserve reserve reserve
%  price    qty    price    qty
roffer = [
    % generators
    10      10      1e-7    Inf;
    5       23      1e-7    Inf;
    % Direct Air Capture
    1e-7    0       10      20; % construction cost 10, max 20 MW
    % dispatchable loads
    1e-7    10      1e-7    Inf;
    1e-7    5       1e-7    Inf;
];

%% changes table
% label probty  field           row column          chgtype newvalue
contab = [
    1   0.25    CT_TAREALOAD    1   CT_LOAD_ALL_P   CT_REL  2;
    1   0.25    CT_TAREALOAD    2   CT_LOAD_ALL_P   CT_REL  1;
    2   0.25    CT_TAREALOAD    1   CT_LOAD_ALL_P   CT_REL  2.1;
    2   0.25    CT_TAREALOAD    2   CT_LOAD_ALL_P   CT_REL  1;
    3   0.25    CT_TAREALOAD    1   CT_LOAD_ALL_P   CT_REL  1;
    3   0.25    CT_TAREALOAD    2   CT_LOAD_ALL_P   CT_REL  1; %same as original hour
];


