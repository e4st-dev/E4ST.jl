function mpc = t_case2_e4st_storage
%T_CASE2_E4ST_STORAGE   Two-bus test case for t_e4st_storage()
% Two-bus test case for testing e4st_solve() with short term storage.
% Contains two buses, each with a generator. One generator is cheap,
% one generator is expensive. There exists a battery that is cheap to
% operate.

%% MATPOWER Case Format : Version 2
mpc.version = '2';

%%-----  Power Flow Data  -----%%
%% system MVA base
mpc.baseMVA = 100;

%% bus data
%	bus_i	type	Pd	Qd	Gs	Bs	area	Vm	Va	baseKV	zone	Vmax	Vmin
mpc.bus = [
	1	3	0	0	0	0	1	1	0	135	1	1.05	0.95;
	2	1	0	0	0	0	2	1	0	135	1	1.1	0.95;
];

%% generator data
%	bus	Pg	Qg	Qmax	Qmin	Vg	mBase	status	Pmax	Pmin	Pc1	Pc2	Qc1min	Qc1max	Qc2min	Qc2max	ramp_agc	ramp_10	ramp_30	ramp_q	apf
mpc.gen = [
	1	10	0	5	-5	1	100	1	10	0	0	0	0	0	0	0	0	Inf	0	0	0;
	2	20	0	10	-10	1	100	1	20	0	0	0	0	0	0	0	0	Inf	0	0	0;
	% battery
	2	10	0	0	0	1	100	1	10	-10	0	0	0	0	0	0	0	Inf	0	0	0;
	% dispatchable loads
	1	-10	0	0	0	1	100	1	0	-10	0	0	0	0	0	0	Inf	Inf	Inf	Inf	0;
	2	-5	0	0	0	1	100	1	0	-5	0	0	0	0	0	0	Inf	Inf	Inf	Inf	0;
];

%% branch data
%	fbus	tbus	r	x	b	rateA	rateB	rateC	ratio	angle	status	angmin	angmax
mpc.branch = [
	1	2	0.01	0.01	0.014	130	130	130	1	0	1	-360	360;
];

%%-----  OPF Data  -----%%
%% generator cost data
%	1	startup	shutdown	n	x1	y1	...	xn	yn
%	2	startup	shutdown	n	c(n-1)	...	c0
mpc.gencost = [
	2	0	0	2	50	0;
	2	0	0	2	20	0;
	% battery
	2	0	0	2	0	0;
	% dispatchable loads
	2	0	0	2	5000	0;
	2	0	0	2	5000	0;
];

%%-----  Short Term Storage Data  -----%%
%	gen_index	efficiency	max_energy(MWh/MW Capacity)
mpc.short_term_storage = [
	3	0.85	4;
];

%%-----  Day Data  -----%%
% each day is represented by a col vector
% The vector contains the labels of the contingencies that belong to that day,
% in the order in which they occur. Label 0 indicates base case.
mpc.days = {
	[0; 1];
	[2; 3];
};
