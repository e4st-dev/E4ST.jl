function t_e4st_solve(quiet)
%T_E4ST_SOLVE  Tests for E4ST_SOLVE.
%
%   Includes DC lines and interface limits.

%   E4ST
%   Copyright (c) 2009-2017 by Power System Engineering Research Center (PSERC)
%   by Ray Zimmerman, PSERC Cornell
%
%   This file is part of E4ST.
%   Covered by the 3-clause BSD License (see LICENSE file for details).
%   See http://e4st.com/ for more info.

if nargin < 1
    quiet = 0;
end

n_tests = 334;

t_begin(n_tests, quiet);

casename = 't_case30_e4st';

%% options
mpopt = mpoption('verbose', 0, 'out.all', 0);
% mpopt = mpoption('verbose', 2, 'out.all', -1);
mpopt = mpoption(mpopt, 'opf.violation', 5e-8, 'mips.comptol', 5e-9, 'mips.step_control', 1);

%% solver options
if have_fcn('cplex')
    %mpopt = mpoption(mpopt, 'cplex.lpmethod', 0);       %% automatic
    %mpopt = mpoption(mpopt, 'cplex.lpmethod', 1);       %% primal simplex
    mpopt = mpoption(mpopt, 'cplex.lpmethod', 2);       %% dual simplex
    %mpopt = mpoption(mpopt, 'cplex.lpmethod', 3);       %% network simplex
    %mpopt = mpoption(mpopt, 'cplex.lpmethod', 4);       %% barrier
    mpopt = mpoption(mpopt, 'cplex.opts.mip.tolerances.mipgap', 0);
    mpopt = mpoption(mpopt, 'cplex.opts.mip.tolerances.absmipgap', 0);
    mpopt = mpoption(mpopt, 'cplex.opts.threads', 2);
end
if have_fcn('glpk')
    mpopt = mpoption(mpopt, 'glpk.opts.mipgap', 0);
    mpopt = mpoption(mpopt, 'glpk.opts.tolint', 1e-10);
    mpopt = mpoption(mpopt, 'glpk.opts.tolobj', 1e-10);
end
if have_fcn('gurobi')
    %mpopt = mpoption(mpopt, 'gurobi.method', -1);       %% automatic
    %mpopt = mpoption(mpopt, 'gurobi.method', 0);        %% primal simplex
    mpopt = mpoption(mpopt, 'gurobi.method', 1);        %% dual simplex
    %mpopt = mpoption(mpopt, 'gurobi.method', 2);        %% barrier
    mpopt = mpoption(mpopt, 'gurobi.threads', 2);
    mpopt = mpoption(mpopt, 'gurobi.opts.MIPGap', 0);
    mpopt = mpoption(mpopt, 'gurobi.opts.MIPGapAbs', 0);
end
if have_fcn('mosek')
    sc = mosek_symbcon;
    %mpopt = mpoption(mpopt, 'mosek.lp_alg', sc.MSK_OPTIMIZER_FREE);            %% default
    %mpopt = mpoption(mpopt, 'mosek.lp_alg', sc.MSK_OPTIMIZER_INTPNT);          %% interior point
    %mpopt = mpoption(mpopt, 'mosek.lp_alg', sc.MSK_OPTIMIZER_PRIMAL_SIMPLEX);  %% primal simplex
    mpopt = mpoption(mpopt, 'mosek.lp_alg', sc.MSK_OPTIMIZER_DUAL_SIMPLEX);     %% dual simplex
    %mpopt = mpoption(mpopt, 'mosek.lp_alg', sc.MSK_OPTIMIZER_FREE_SIMPLEX);    %% automatic simplex
    %mpopt = mpoption(mpopt, 'mosek.opts.MSK_DPAR_MIO_TOL_X', 0);
    mpopt = mpoption(mpopt, 'mosek.opts.MSK_IPAR_MIO_NODE_OPTIMIZER', sc.MSK_OPTIMIZER_DUAL_SIMPLEX);
    mpopt = mpoption(mpopt, 'mosek.opts.MSK_IPAR_MIO_ROOT_OPTIMIZER', sc.MSK_OPTIMIZER_DUAL_SIMPLEX);
    mpopt = mpoption(mpopt, 'mosek.opts.MSK_DPAR_MIO_TOL_ABS_RELAX_INT', 1e-9);
    %mpopt = mpoption(mpopt, 'mosek.opts.MSK_DPAR_MIO_TOL_REL_RELAX_INT', 0);
    mpopt = mpoption(mpopt, 'mosek.opts.MSK_DPAR_MIO_TOL_REL_GAP', 0);
    mpopt = mpoption(mpopt, 'mosek.opts.MSK_DPAR_MIO_TOL_ABS_GAP', 0);
end
if have_fcn('intlinprog')
    %mpopt = mpoption(mpopt, 'linprog.Algorithm', 'interior-point');
    %mpopt = mpoption(mpopt, 'linprog.Algorithm', 'active-set');
    %mpopt = mpoption(mpopt, 'linprog.Algorithm', 'simplex');
    mpopt = mpoption(mpopt, 'linprog.Algorithm', 'dual-simplex');
    %mpopt = mpoption(mpopt, 'intlinprog.RootLPAlgorithm', 'primal-simplex');
    mpopt = mpoption(mpopt, 'intlinprog.RootLPAlgorithm', 'dual-simplex');
    mpopt = mpoption(mpopt, 'intlinprog.TolCon', 1e-9);
    mpopt = mpoption(mpopt, 'intlinprog.TolGapAbs', 0);
    mpopt = mpoption(mpopt, 'intlinprog.TolGapRel', 0);
    mpopt = mpoption(mpopt, 'intlinprog.TolInteger', 1e-6);
end


% mpopt = mpoption(mpopt, 'sopf.force_Pc_eq_P0', 1);  %% constrain contracted == base case dispatch
mpopt = mpoption(mpopt, 'model', 'DC');

if have_fcn('gurobi')
    slvr = 'GUROBI';
elseif have_fcn('cplex')
    slvr = 'CPLEX';
elseif have_fcn('mosek')
    slvr = 'MOSEK';
elseif have_fcn('linprog_ds')
    slvr = 'OT';
elseif have_fcn('glpk')
    slvr = 'GLPK';
elseif have_fcn('linprog')
    slvr = 'OT';
else
    slvr = 'MIPS';
end
% slvr = 'BPMPD';
% slvr = 'CLP';
% slvr = 'CPLEX';
% slvr = 'GLPK';
% slvr = 'GUROBI';
% slvr = 'IPOPT';
% slvr = 'MOSEK';
% slvr = 'OT';
% slvr = 'MIPS';
mpopt = mpoption(mpopt, 'opf.dc.solver', slvr);

%% turn off warnings
if have_fcn('octave')
    if have_fcn('octave', 'vnum') >= 4
        file_in_path_warn_id = 'Octave:data-file-in-path';
    else
        file_in_path_warn_id = 'Octave:load-file-in-path';
    end
    s1 = warning('query', file_in_path_warn_id);
    warning('off', file_in_path_warn_id);
end
s7 = warning('query', 'MATLAB:nearlySingularMatrix');
s6 = warning('query', 'MATLAB:nearlySingularMatrixUMFPACK');
warning('off', 'MATLAB:nearlySingularMatrix');
warning('off', 'MATLAB:nearlySingularMatrixUMFPACK');

%% define named indices into data matrices
[PQ, PV, REF, NONE, BUS_I, BUS_TYPE, PD, QD, GS, BS, BUS_AREA, VM, ...
    VA, BASE_KV, ZONE, VMAX, VMIN, LAM_P, LAM_Q, MU_VMAX, MU_VMIN] = idx_bus;
[GEN_BUS, PG, QG, QMAX, QMIN, VG, MBASE, GEN_STATUS, PMAX, PMIN, ...
    MU_PMAX, MU_PMIN, MU_QMAX, MU_QMIN, PC1, PC2, QC1MIN, QC1MAX, ...
    QC2MIN, QC2MAX, RAMP_AGC, RAMP_10, RAMP_30, RAMP_Q, APF] = idx_gen;
[F_BUS, T_BUS, BR_R, BR_X, BR_B, RATE_A, RATE_B, RATE_C, ...
    TAP, SHIFT, BR_STATUS, PF, QF, PT, QT, MU_SF, MU_ST, ...
    ANGMIN, ANGMAX, MU_ANGMIN, MU_ANGMAX] = idx_brch;
[CT_LABEL, CT_PROB, CT_TABLE, CT_TBUS, CT_TGEN, CT_TBRCH, CT_TAREABUS, ...
    CT_TAREAGEN, CT_TAREABRCH, CT_ROW, CT_COL, CT_CHGTYPE, CT_REP, ...
    CT_REL, CT_ADD, CT_NEWVAL, CT_TLOAD, CT_TAREALOAD, CT_LOAD_ALL_PQ, ...
    CT_LOAD_FIX_PQ, CT_LOAD_DIS_PQ, CT_LOAD_ALL_P, CT_LOAD_FIX_P, ...
    CT_LOAD_DIS_P, CT_TGENCOST, CT_TAREAGENCOST, CT_MODCOST_F, ...
    CT_MODCOST_X] = idx_ct;
c = idx_dcline;

%% reserve and delta offers
%     +      +        -      -       +      -
%  active  active  active  active  active active
% reserve  reserve reserve reserve delta  delta
%  price    qty    price    qty    price  price
roffer = [
    10      15      10      15      0       0;
    10      30      10      30      0       0;
    10      20      10      20      0       0;
    10      25      10      25      0       0;
    20      25      20      25      0       0;
    20      15      20      15      0       0;
    20      30      20      30      0       0;
    20      15      20      15      0       0;
    30      15      30      15      0       0;
    30      30      30      30      0       0;
    30      25      30      25      0       0;
    30      30      30      30      0       0;
    0.001   50      0.002   50      0       0;
    0.001   50      0.002   50      0       0;
    0.001   50      0.002   50      0       0;
    0.001   50      0.002   50      0       0;
    0.001   50      0.002   50      0       0;
    0.001   50      0.002   50      0       0;
    0.001   50      0.002   50      0       0;
    0.001   50      0.002   50      0       0;
    0.001   50      0.002   50      0       0;
    0.001   50      0.002   50      0       0;
    0.001   50      0.002   50      0       0;
    0.001   50      0.002   50      0       0;
    0.001   50      0.002   50      0       0;
    0.001   50      0.002   50      0       0;
    0.001   50      0.002   50      0       0;
    0.001   50      0.002   50      0       0;
    0.001   50      0.002   50      0       0;
    0.001   50      0.002   50      0       0;
    0.001   50      0.002   50      0       0;
    0.001   50      0.002   50      0       0;
];

%% changes table
% label probty  type        row column          chgtype newvalue
contab = [
    1   0.002   CT_TBRCH    1   BR_STATUS       CT_REP  0;      %% line 1-2
    2   0.002   CT_TBRCH    2   BR_STATUS       CT_REP  0;      %% line 1-3, all power from gen1 flows via gen2
    3   0.002   CT_TBRCH    3   BR_STATUS       CT_REP  0;      %% line 2-4, a path to loads @ buses 7 & 8
    4   0.002   CT_TBRCH    5   BR_STATUS       CT_REP  0;      %% line 2-5, a path to loads @ buses 7 & 8
    5   0.002   CT_TBRCH    6   BR_STATUS       CT_REP  0;      %% line 2-6, a path to loads @ buses 7 & 8
    6   0.002   CT_TBRCH    36  BR_STATUS       CT_REP  0;      %% line 28-27, tie line between areas 1 & 3
    7   0.002   CT_TBRCH    15  BR_STATUS       CT_REP  0;      %% line 4-12, tie line between areas 1 & 2
    8   0.002   CT_TBRCH    12  BR_STATUS       CT_REP  0;      %% line 6-10, tie line between areas 1 & 3
    9   0.002   CT_TBRCH    14  BR_STATUS       CT_REP  0;      %% line 9-10, tie line between areas 1 & 3
    10  0.002   CT_TGEN     1   GEN_STATUS      CT_REP  0;      %% gen 1 at bus 1
    11  0.002   CT_TGEN     2   GEN_STATUS      CT_REP  0;      %% gen 2 at bus 2
    12  0.002   CT_TGEN     3   GEN_STATUS      CT_REP  0;      %% gen 3 at bus 22
    13  0.002   CT_TGEN     4   GEN_STATUS      CT_REP  0;      %% gen 4 at bus 27
    14  0.002   CT_TGEN     5   GEN_STATUS      CT_REP  0;      %% gen 5 at bus 23
    15  0.002   CT_TGEN     6   GEN_STATUS      CT_REP  0;      %% gen 6 at bus 13
    20  0.010   CT_TLOAD    0   CT_LOAD_ALL_PQ  CT_REL  1.1;    %% 10% load increase
    21  0.010   CT_TLOAD    0   CT_LOAD_ALL_PQ  CT_REL  0.9;    %% 10% load decrease
];

if have_fcn('glpk') || have_fcn('gurobi') || have_fcn('cplex') || ...
        have_fcn('mosek') || have_fcn('linprog') ||  have_fcn('clp') || ...
        have_fcn('ipopt')
    %% load the case
    mpc = loadcase(casename);
    mpc = toggle_iflims(mpc, 'on');
    mpc = toggle_dcline(mpc, 'on');

    cn = load('t_e4st_costnoise');
    ng = size(mpc.gen, 1);
    mpc.gencost(1:12, 8) = mpc.gencost(1:12, 8) + cn.costnoise(1:12, 1);
    mpc.gencost(13:end, 5) = mpc.gencost(13:end, 5) + cn.costnoise(1:20, 6);
    roffer(1:12, 1) = roffer(1:12, 1) + cn.costnoise(1:12, 2);
    roffer(1:12, 3) = roffer(1:12, 3) + cn.costnoise(1:12, 3);
%     roffer(5:12, 5) = roffer(5:12, 5) + cn.costnoise(5:12, 4);
%     roffer(5:12, 6) = roffer(5:12, 6) + cn.costnoise(5:12, 5);
    
    %% force active contracts to zero, expected for e4st_solve()
    roffer = e4st_offer2mat(roffer, ng);
    roffer(:, 11:12) = 0;

    %% set total output constraints (e.g. emission caps)
    toc_max  = { [40; 100; 8.2], [30; 100; 8.2] };
    %% load solution results
    solns = {'t_e4st_solve_soln1', 't_e4st_solve_soln2'};

    %%-----  run it  -----
    for k = 1:length(toc_max)
        mpc.total_output.max = toc_max{k};
        s = load(solns{k});

        [results1, f1, success1, info, et, g, jac, xr, pimul] = ...
                    e4st_solve(mpc, roffer, contab, mpopt);


%     fname = sprintf('t_e4st_solve_soln%d', k);
%     results1.opf_results = rmfield(results1.opf_results, 'userfcn');
%     results1.opf_results = rmfield(results1.opf_results, 'om');
%     save(fname, 'f1', 'results1');

%     results1.total_output.qty
%     results1.total_output.mu

    %%-----  test the results  -----
    t = 'success1';
    t_ok(success1, t);

    t = 'f1';
    t_is(f1, s.f1, 5, t);

    t = 'results1.energy.Pc';
    t_is(results1.energy.Pc, s.results1.energy.Pc, 5, t);

    t = 'results1.energy.Gmax';
    t_is(results1.energy.Gmax, s.results1.energy.Gmax, 5, t);

    t = 'results1.energy.Gmin';
    t_is(results1.energy.Gmin, s.results1.energy.Gmin, 5, t);

    t = 'results1.energy.Qmax';
    t_is(results1.energy.Qmax, s.results1.energy.Qmax, 5, t);

    t = 'results1.energy.Qmin';
    t_is(results1.energy.Qmin, s.results1.energy.Qmin, 5, t);

%     t = 'results1.energy.mu.*';
%     g1 =   results1.energy.sum_muPmax;
%     e1 = s.results1.energy.sum_muPmax;
%     g1 = g1 -   results1.energy.sum_muPmin;
%     e1 = e1 - s.results1.energy.sum_muPmin;
%     g1 = g1 +   results1.energy.mu.Pc;
%     e1 = e1 + s.results1.energy.mu.Pc;
%     g1 = g1 -   results1.energy.sumlamPikplus;
%     e1 = e1 - s.results1.energy.sumlamPikplus;
%     g1 = g1 +   results1.energy.sumlamPikminus;
%     e1 = e1 + s.results1.energy.sumlamPikminus;
% %     g1 = g1 - sum(  results1.energy.delta.mu.P_pos_GEQ0, 2);
% %     e1 = e1 - sum(s.results1.energy.delta.mu.P_pos_GEQ0, 2);
% %     g1 = g1 + sum(  results1.energy.delta.mu.P_neg_GEQ0, 2);
% %     e1 = e1 + sum(s.results1.energy.delta.mu.P_neg_GEQ0, 2);
%     t_is(g1, e1, 6, t);

    t = 'results1.energy.sum_muPmax';
    t_is(results1.energy.sum_muPmax, s.results1.energy.sum_muPmax, 5, t);

%     t = 'results1.energy.sum_muPmin';
%     t_is(results1.energy.sum_muPmin, s.results1.energy.sum_muPmin, 1, t);

    t = 'results1.energy.prc.sum_bus_lam_p';
    t_is(results1.energy.prc.sum_bus_lam_p, s.results1.energy.prc.sum_bus_lam_p, 5, t);

    t = 'results1.energy.prc.sum_bus_lam_q';
    t_is(results1.energy.prc.sum_bus_lam_q, s.results1.energy.prc.sum_bus_lam_q, 5, t);

    t = 'results1.energy.mu.alphaP';
    g3 = results1.energy.mu.alphaP;
    e3 = s.results1.energy.mu.alphaP;
%     t_is(g1-e1, g3-e3, 5, t);
    t_is(g3, e3, 5, t);

    kp = find(results1.reserve.qty.Rp_pos);

    t = 'results1.reserve.mu.Rp_pos';
    t_is(sum(results1.reserve.mu.Rp_pos(kp, :), 2), sum(s.results1.reserve.mu.Rp_pos(kp, :), 2), 5, t);

    t = 'results1.reserve.mu.Rp_neg';
    t_is(sum(results1.reserve.mu.Rp_neg, 2), sum(s.results1.reserve.mu.Rp_neg, 2), 5, t);

    t = 'results1.reserve.mu.Rpmax_pos';
    t_is(results1.reserve.mu.Rpmax_pos, s.results1.reserve.mu.Rpmax_pos, 5, t);

    t = 'results1.reserve.mu.Rpmax_neg';
    t_is(results1.reserve.mu.Rpmax_neg, s.results1.reserve.mu.Rpmax_neg, 5, t);

    t = 'results1.reserve.qty.Rp_pos';
    t_is(results1.reserve.qty.Rp_pos, s.results1.reserve.qty.Rp_pos, 5, t);

    t = 'results1.reserve.qty.Rp_neg';
    t_is(results1.reserve.qty.Rp_neg, s.results1.reserve.qty.Rp_neg, 5, t);

    t = 'results1.reserve.prc.Rp_pos';
    t_is(results1.reserve.prc.Rp_pos(kp), s.results1.reserve.prc.Rp_pos(kp), 5, t);

    t = 'results1.reserve.prc.Rp_neg';
    t_is(results1.reserve.prc.Rp_neg, s.results1.reserve.prc.Rp_neg, 5, t);

    t = 'results1.opf_results.x';
    t_is(results1.opf_results.x, s.results1.opf_results.x, 4, t);

    t = 'results1.total_output.qty';
    t_is(results1.total_output.qty, s.results1.total_output.qty, 2, t);

    t = 'results1.total_output.mu';
    t_is(results1.total_output.mu, s.results1.total_output.mu, 2, t);
    %% base case quantities
    t = 'results1.base.bus(:, VA)';
    t_is(results1.base.bus(:, VA), s.results1.base.bus(:, VA), 6, t);

    t = 'results1.base.gen(:, PG)';
    t_is(results1.base.gen(:, PG), s.results1.base.gen(:, PG), 6, t);

%     t = 'results1.base.gen(:, MU_PMIN)';
%     t_is(results1.base.gen(:, MU_PMIN), s.results1.base.gen(:, MU_PMIN), 1, t);

    t = 'results1.base.dcline(:, c.PF)';
    t_is(results1.base.dcline(:, c.PF), s.results1.base.dcline(:, c.PF), 6, t);

    t = 'results1.base.dcline(:, c.PT)';
    t_is(results1.base.dcline(:, c.PT), s.results1.base.dcline(:, c.PT), 6, t);

    t = 'results1.base.dcline(:, c.MU_PMIN)';
    t_is(results1.base.dcline(:, c.MU_PMIN), s.results1.base.dcline(:, c.MU_PMIN), 2, t);

    t = 'results1.base.dcline(:, c.MU_PMAX)';
    t_is(results1.base.dcline(:, c.MU_PMAX), s.results1.base.dcline(:, c.MU_PMAX), 6, t);

    t = 'results1.base.if.P';
    t_is(results1.base.if.P, s.results1.base.if.P, 6, t);

    t = 'results1.base.if.mu.l';
    t_is(results1.base.if.mu.l, s.results1.base.if.mu.l, 6, t);

    t = 'results1.base.if.mu.u';
    t_is(results1.base.if.mu.u, s.results1.base.if.mu.u, 6, t);

% [results1.base.if.P results1.base.if.mu.l results1.base.if.mu.u]

    %% contingency quantities
    nc = length(results1.cont);
    for k = 1:nc
        p = 6;
        t = sprintf('results1.cont(%d).bus(:, VA)', k);
        t_is(results1.cont(k).bus(:, VA), s.results1.cont(k).bus(:, VA), p, t);

        t = sprintf('results1.cont(%d).gen(:, PG)', k);
        t_is(results1.cont(k).gen(:, PG), s.results1.cont(k).gen(:, PG), p, t);

%         t = sprintf('results1.cont(%d).gen(:, MU_PMIN)', k);
%         t_is(results1.cont(k).gen(:, MU_PMIN), s.results1.cont(k).gen(:, MU_PMIN), 1, t);

        t = sprintf('results1.cont(%d).dcline(:, c.PF)', k);
        t_is(results1.cont(k).dcline(:, c.PF), s.results1.cont(k).dcline(:, c.PF), 6, t);

        t = sprintf('results1.cont(%d).dcline(:, c.PT)', k);
        t_is(results1.cont(k).dcline(:, c.PT), s.results1.cont(k).dcline(:, c.PT), 6, t);

        t = sprintf('results1.cont(%d).dcline(:, c.MU_PMIN)', k);
        t_is(results1.cont(k).dcline(:, c.MU_PMIN), s.results1.cont(k).dcline(:, c.MU_PMIN), 2, t);

        t = sprintf('results1.cont(%d).dcline(:, c.MU_PMAX)', k);
        t_is(results1.cont(k).dcline(:, c.MU_PMAX), s.results1.cont(k).dcline(:, c.MU_PMAX), 6, t);

        t = sprintf('results1.cont(%d).if.mu.l', k);
        t_is(results1.cont(k).if.mu.l, s.results1.cont(k).if.mu.l, 6, t);

        t = sprintf('results1.cont(%d).if.mu.u', k);
        t_is(results1.cont(k).if.mu.u, s.results1.cont(k).if.mu.u, 6, t);
% [results1.cont(k).if.P results1.cont(k).if.mu.l results1.cont(k).if.mu.u]
    end
    end
else
    t_skip(n_tests, 'no adequate LP solver available');
end

%% turn warnings back on
if have_fcn('octave')
    warning(s1.state, file_in_path_warn_id);
end
warning(s7.state, 'MATLAB:nearlySingularMatrix');
warning(s6.state, 'MATLAB:nearlySingularMatrixUMFPACK');

t_end;
