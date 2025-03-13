function mpc = case9
%CASE9    Power flow data for 9 bus, 3 generator case.

%% MATPOWER Case Format : Version 2
mpc.version = '2';

%%-----  Power Flow Data  -----%%
%% system MVA base
mpc.baseMVA = 100;

%% bus data
%	bus_i	type	Pd	Qd	Gs	Bs	area	Vm	Va	baseKV	zone	Vmax	Vmin
mpc.bus = [
	1	3	0	0	0	0	1	1	0	345	1	1.1	0.9;
	2	2	0	0	0	0	1	1	0	345	1	1.1	0.9;
	3	2	0	0	0	0	1	1	0	345	1	1.1	0.9;
	4	1	0	0	0	0	1	1	0	345	1	1.1	0.9;
	5	1	90	80	0	0	1	1	0	345	1	1.1	0.9;  % Increased Qd (Reactive Load)
	6	1	0	0	0	0	1	1	0	345	1	1.1	0.9;
	7	1	100	70	0	0	1	1	0	345	1	1.1	0.9;  % Increased Qd
	8	1	0	0	0	0	1	1	0	345	1	1.1	0.9;
	9	1	125	100	0	0	1	1	0	345	1	1.1	0.9; % Increased Qd
];

%% generator data
%	bus	Pg	Qg	Qmax	Qmin	Vg	mBase	status	Pmax	Pmin
mpc.gen = [
	1	0.0	0.0	1	-1	1.04	100	1	250	10;   % Severe Q limits
	2	0.0	0.0	1	-1	1.025	100	1	300	10;  % Severe Q limits
	3	0.0	0.0	1 -1	1.025	100	1	270	10; % Severe Q limits
];

%% branch data
%	fbus	tbus	r	x	b	rateA	rateB	rateC	ratio	angle	status	angmin	angmax
mpc.branch = [
	1	4	0	0.20	0	250	250	250	0	0	1	-360	360;  % Increased reactance
	4	5	0.017	0.30	0.158	250	250	250	0	0	1	-360	360;  % Increased reactance
	5	6	0.039	0.40	0.358	150	150	150	0	0	1	-360	360;  % Increased reactance
	3	6	0	0.20	0	300	300	300	0	0	1	-360	360;  % Increased reactance
	6	7	0.0119	0.25	0.209	150	150	150	0	0	1	-360	360;  % Increased reactance
	7	8	0.0085	0.30	0.149	250	250	250	0	0	1	-360	360;  % Increased reactance
	8	2	0	0.40	0	250	250	250	0	0	1	-360	360;  % Increased reactance
	8	9	0.032	0.30	0.306	250	250	250	0	0	1	-360	360;  % Increased reactance
	9	4	0.01	0.35	0.176	250	250	250	0	0	1	-360	360;  % Increased reactance
];

%%-----  OPF Data  -----%%
%% generator cost data
%	1	startup	shutdown	n	x1	y1	...	xn	yn
%	2	startup	shutdown	n	c(n-1)	...	c0
mpc.gencost = [
	2	1500	0	3	0.11	5	150;
	2	2000	0	3	0.085	1.2	600;
	2	3000	0	3	0.1225	1	335;
];
