function [mpc, roffer, contab] = t_case_e4st_dac1
%T_CASE_E4ST_DAC1  Two-bus test case for t_e4st_dac()
% Two-bus test case for testing e4st_solve() with one direct air capture unit.
% Contains two buses, each with a generator. The gererator at bus 1 has a 
% maximum power output of 10 MW and variable cost of $50/MW. The generator
% at bus 2 has a maximum power output of 20 MW and variable cost of $20/MW.
% There are four hours. For hour 1 has a load of 15 MW, while hour 2
% has a load of 25 MW. Hour 3 has a load of 26 MW and hour 4 has a load of
% 15 MW. Power plant 1 emits 10 short tons CO2/MWh electricity and Power 
% plant 2 emits 10 short tons CO2/MWh electricity . The
% direct air capture unit has a variable cost of $50/MWh and costs $10/MW
% to build. It captures CO2 at a rate 7 short tons per MWh. There is a zero
% emission constraint. 


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
];
% REWRITE: we need idx, which bus is reference bus in each island
% Things we for sure need:
% - reference bus 
% - Bus id's
% - Starting voltage angle (to seed JuMP?)
% - Vmax and Vmin (?) Though it per-unit voltages, so we might not even need these
% - baseKV - helpful to know, not necessary for solving
% - Gs and Bs are for shunts (we don't deal with it)


%% generator data
%	bus	Pg	Qg	Qmax	Qmin	Vg	mBase	status	Pmax	Pmin	Pc1	Pc2	Qc1min	Qc1max	Qc2min	Qc2max	ramp_agc	ramp_10	ramp_30	ramp_q	apf
mpc.gen = [
	1	10	0	5	-5	1	100	1	10	0	0	0	0	0	0	0	0	Inf	0	0	0;
	2	23	0	10	-10	1	100	1	23	0	0	0	0	0	0	0	0	Inf	0	0	0;
	% Direct Air Capture Device
    1	-20	0	0	0	1	100	1	1  -20	0	0	0	0	0	0	Inf	Inf	Inf	Inf	0;
	% dispatchable loads
	1	-10	0	0	0	1	100	1	0  -10	0	0	0	0	0	0	Inf	Inf	Inf	Inf	0;
	2	-5	0	0	0	1	100	1	0	-5	0	0	0	0	0	0	Inf	Inf	Inf	Inf	0;
];
% Rewrite: things we for sure need for each generator from the gen sheet:
% - bus id
% - Pg - MW capacity
% - status
% - ramp (eventual feature?)
% - (Pmax and Pmin could be retirable amount and buildable amount)
% - 



%% branch data
%	fbus	tbus	r	x	b	rateA	rateB	rateC	ratio	angle	status	angmin	angmax
mpc.branch = [
	1	2	0.01	0.01	0.014	130	130	130	1	0	1	-360	360;
];
% REWRITE: we need:
% - from
% - to
% - one of r, x, b (impedance/susceptance for angle diff)
% - rateA, rateB, and rateC are different measures of flow limit, not sure which one to use.  Typically use rateA, but need to confirm
% - status


%%-----  OPF Data  -----%%
%% generator cost data
%	1	startup	shutdown	n	x1	y1	...	xn	yn
%	2	startup	shutdown	n	c(n-1)	...	c0
mpc.gencost = [
	2	0	0	2	50	0;
	2	0	0	2	20	0;
	% Direct Air Capture
 	2	0	0	2	-50	0;
	% dispatchable loads
	2	0	0	2	5000	0;
	2	0	0	2	5000	0;
];
% REWRITE: we need:
% - variable cost (VOM + fuel_cost - ptc)


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
    1e-7    0       10       20; % construction cost 10, max 20 MW % construction cost 50, max 20 MW
    % dispatchable loads
    1e-7    10      1e-7    Inf;
    1e-7    5       1e-7    Inf;
];
% REWRITE:
% - Add this to generator sheet
% - we may want all 4 of these (min and max amount to add and retire)

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


