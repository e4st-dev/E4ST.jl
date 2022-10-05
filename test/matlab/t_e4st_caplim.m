function t_e4st_caplim(quiet)
%T_E4ST_CAPLIM  Tests for E4ST_SOLVE.
%
%   Includes build capacity limits, DC lines, interface limits and total
%   output constraints.

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

n_tests = 206;

t_begin(n_tests, quiet);

casename = 't_case30_e4st_caplim';

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

%% cost to build, cost to keep
ctk1 = 1;   %% cost to keep
ctb1 = 10;  %% cost to build (expensive)
ctb2 = 4;   %% cost to build (cheap)
%     +      +        -      -       +      -
%  active  active  active  active  active active
% reserve  reserve reserve reserve delta  delta
%  price    qty    price    qty    price  price
roffer = [
    ctk1    100      10      0      0       0;
    ctk1    100      10      0      0       0;
    ctk1    100      10      0      0       0;
    ctk1    100      10      0      0       0;
    ctk1    100      10      0      0       0;
    ctk1    100      10      0      0       0;
    ctk1    100      10      0      0       0;
    ctk1    100      10      0      0       0;
    ctk1    100      10      0      0       0;
    ctk1    100      10      0      0       0;
    ctk1    100      10      0      0       0;
    ctk1    100      10      0      0       0;
% new gens
    ctb1    100      10      0      0       0;
    ctb2    100      10      0      0       0;
    ctb1    100      10      0      0       0;
    ctb2    100      10      0      0       0;
    ctb1    100      10      0      0       0;
    ctb2    100      10      0      0       0;
    ctb1    100      10      0      0       0;
    ctb2    100      10      0      0       0;
    ctb1    100      10      0      0       0;
    ctb2    100      10      0      0       0;
    ctb1    100      10      0      0       0;
    ctb2    100      10      0      0       0;
% dispatchable loads
    10      0       0.001   50      0       0;
    10      0       0.001   50      0       0;
    10      0       0.001   50      0       0;
    10      0       0.001   50      0       0;
    10      0       0.001   50      0       0;
    10      0       0.001   50      0       0;
    10      0       0.001   50      0       0;
    10      0       0.001   50      0       0;
    10      0       0.001   50      0       0;
    10      0       0.001   50      0       0;
    10      0       0.001   50      0       0;
    10      0       0.001   50      0       0;
    10      0       0.001   50      0       0;
    10      0       0.001   50      0       0;
    10      0       0.001   50      0       0;
    10      0       0.001   50      0       0;
    10      0       0.001   50      0       0;
    10      0       0.001   50      0       0;
    10      0       0.001   50      0       0;
    10      0       0.001   50      0       0;
];

%% changes table
lo = 0.8;
hi = 1.2;
% label probty  type            row column          chgtype newvalue
contab = [
    1   0.2     CT_TAREALOAD    1   CT_LOAD_ALL_P   CT_REL  lo;
    1   0.0     CT_TAREALOAD    2   CT_LOAD_ALL_P   CT_REL  lo;
    1   0.0     CT_TAREALOAD    3   CT_LOAD_ALL_P   CT_REL  1.0;
    2   0.2     CT_TAREALOAD    1   CT_LOAD_ALL_P   CT_REL  hi;
    2   0.0     CT_TAREALOAD    2   CT_LOAD_ALL_P   CT_REL  hi;
    2   0.0     CT_TAREALOAD    3   CT_LOAD_ALL_P   CT_REL  1.0;
    3   0.2     CT_TAREALOAD    1   CT_LOAD_ALL_P   CT_REL  lo;
    3   0.0     CT_TAREALOAD    2   CT_LOAD_ALL_P   CT_REL  hi;
    3   0.0     CT_TAREALOAD    3   CT_LOAD_ALL_P   CT_REL  1.0;
    4   0.2     CT_TAREALOAD    1   CT_LOAD_ALL_P   CT_REL  hi;
    4   0.0     CT_TAREALOAD    2   CT_LOAD_ALL_P   CT_REL  lo;
    4   0.0     CT_TAREALOAD    3   CT_LOAD_ALL_P   CT_REL  1.0;
];

if have_fcn('glpk') || have_fcn('gurobi') || have_fcn('cplex') || ...
        have_fcn('mosek') || have_fcn('linprog') ||  have_fcn('clp') || ...
        have_fcn('ipopt')
    %% load the case
    mpc = loadcase(casename);
    mpc = toggle_iflims(mpc, 'on');
    mpc = toggle_dcline(mpc, 'on');
    ng = size(mpc.gen, 1);

    cn = load('t_e4st_costnoise');
    mpc.gencost( 1:12, 8)  = mpc.gencost( 1:12, 8) + cn.costnoise(1:12, 1);
    mpc.gencost(13:24, 8)  = mpc.gencost(13:24, 8) + cn.costnoise(1:12, 2);
    mpc.gencost(25:end, 5) = mpc.gencost(25:end, 5) + cn.costnoise(1:20, 6);
%     roffer(1:12, 1) = roffer(1:12, 1) + cn.costnoise(1:12, 2);
    roffer(13:24, 1) = roffer(13:24, 1) + cn.costnoise(1:12, 3);
%     roffer(1:12, 3) = roffer(1:12, 3) + cn.costnoise(1:12, 3);
%     roffer(5:12, 5) = roffer(5:12, 5) + cn.costnoise(5:12, 4);
%     roffer(5:12, 6) = roffer(5:12, 6) + cn.costnoise(5:12, 5);
    
    %% force active contracts to zero, expected for e4st_solve()
    roffer = e4st_offer2mat(roffer, ng);
    roffer(:, 11:12) = 0;

    tot_out = mpc.total_output;
    caplim_map = mpc.caplim.map;
    caplim_max = mpc.caplim.max;
    caplim_min = mpc.caplim.min;

    %% load solution results
    solns = {   't_e4st_caplim_soln1', 't_e4st_caplim_soln2', ...
                't_e4st_caplim_soln3', 't_e4st_caplim_soln4', ...
                't_e4st_caplim_soln5' };

    %%-----  run it  -----
    for k = 1:5
        if isfield(mpc, 'caplim')
            mpc = rmfield(mpc, 'caplim');
        end
        if isfield(mpc, 'total_output')
            mpc = rmfield(mpc, 'total_output');
        end
        mpc.caplim.map = caplim_map;
        switch k
            case 1  %% no cap lims
                sum_ebuilt = [7.4; 50];
            case 2  %% upper limit
                mpc.caplim.max = caplim_max;
                sum_ebuilt = [15.91; 40];
            case 3  %% lower limit
                mpc.caplim.min = caplim_min;
                sum_ebuilt = [16; 50];
            case 4  %% both limits
                mpc.caplim.max = caplim_max;
                mpc.caplim.min = caplim_min;
                sum_ebuilt = [16; 40];
            case 5  %% both limits
                mpc.caplim.max = caplim_max;
                mpc.caplim.min = caplim_min;
                sum_ebuilt = [16; 40];
                mpc.total_output = tot_out;
                mpc.total_output.max = [30; 80; 8.35];
        end
        s = load(solns{k});

        [results, f, success, info, et, g, jac, xr, pimul] = ...
                    e4st_solve(mpc, roffer, contab, mpopt);

%     fname = sprintf('t_e4st_caplim_soln%d', k);
%     results.opf_results = rmfield(results.opf_results, 'userfcn');
%     results.opf_results = rmfield(results.opf_results, 'om');
%     save(fname, 'f', 'results');

%     results.total_output.qty
%     results.total_output.mu

%     results.base.if.P
%     results.cont(1).if.P
%     results.cont(2).if.P
%     results.cont(3).if.P
%     results.cont(4).if.P
% 
%     mean([
%     results.base.if.mu.l'
%     results.cont(1).if.mu.l'
%     results.cont(2).if.mu.l'
%     results.cont(3).if.mu.l'
%     results.cont(4).if.mu.l' ])'
% 
%     mean([
%     results.base.if.mu.u'
%     results.cont(1).if.mu.u'
%     results.cont(2).if.mu.u'
%     results.cont(3).if.mu.u'
%     results.cont(4).if.mu.u' ])'
% 
%     results.base.dcline(:, c.PF:c.PT)
%     results.cont(1).dcline(:, c.PF:c.PT)
%     results.cont(2).dcline(:, c.PF:c.PT)
%     results.cont(3).dcline(:, c.PF:c.PT)
%     results.cont(4).dcline(:, c.PF:c.PT)

    %%-----  test the results  -----
    t = 'success';
    t_ok(success, t);

    t = 'f';
    t_is(f, s.f, 5, t);

    t = 'built';
    built = [results.energy.Gmax(13:2:24) results.energy.Gmax(14:2:24)];
    ebuilt = [s.results.energy.Gmax(13:2:24) s.results.energy.Gmax(14:2:24)];
%    sum(built)
%    sum(sum(built))
    t_is(built, ebuilt, 11, t);
    t_is(sum(built)', sum_ebuilt, 5, t);
    if k > 1
        t = 'caplim.qty';
        t_is(results.caplim.qty, sum_ebuilt, 5, t);
%         t = 'caplim.mu';
%         t_is(results.caplim.mu, s.results.caplim.mu, 1, t);
    end

    t = 'results.energy.Pc';
    t_is(results.energy.Pc, s.results.energy.Pc, 5, t);

    t = 'results.energy.Gmax';
    t_is(results.energy.Gmax, s.results.energy.Gmax, 5, t);

    t = 'results.energy.Gmin';
    t_is(results.energy.Gmin, s.results.energy.Gmin, 5, t);

    t = 'results.energy.Qmax';
    t_is(results.energy.Qmax, s.results.energy.Qmax, 5, t);

    t = 'results.energy.Qmin';
    t_is(results.energy.Qmin, s.results.energy.Qmin, 5, t);

%     t = 'results.energy.mu.*';
%     g1 =   results.energy.sum_muPmax;
%     e1 = s.results.energy.sum_muPmax;
%     g1 = g1 -   results.energy.sum_muPmin;
%     e1 = e1 - s.results.energy.sum_muPmin;
%     g1 = g1 +   results.energy.mu.Pc;
%     e1 = e1 + s.results.energy.mu.Pc;
%     g1 = g1 -   results.energy.sumlamPikplus;
%     e1 = e1 - s.results.energy.sumlamPikplus;
%     g1 = g1 +   results.energy.sumlamPikminus;
%     e1 = e1 + s.results.energy.sumlamPikminus;
% %     g1 = g1 - sum(  results.energy.delta.mu.P_pos_GEQ0, 2);
% %     e1 = e1 - sum(s.results.energy.delta.mu.P_pos_GEQ0, 2);
% %     g1 = g1 + sum(  results.energy.delta.mu.P_neg_GEQ0, 2);
% %     e1 = e1 + sum(s.results.energy.delta.mu.P_neg_GEQ0, 2);
%     t_is(g1, e1, 6, t);

%     t = 'results.energy.sum_muPmax';
%     t_is(results.energy.sum_muPmax, s.results.energy.sum_muPmax, 5, t);
% 
%     t = 'results.energy.sum_muPmin';
%     t_is(results.energy.sum_muPmin, s.results.energy.sum_muPmin, 1, t);

    t = 'results.energy.prc.sum_bus_lam_p';
    t_is(results.energy.prc.sum_bus_lam_p, s.results.energy.prc.sum_bus_lam_p, 5, t);

    t = 'results.energy.prc.sum_bus_lam_q';
    t_is(results.energy.prc.sum_bus_lam_q, s.results.energy.prc.sum_bus_lam_q, 5, t);

%     g1 = sum(results.energy.delta.mu.P_pos_GEQ0, 2);
%     g2 = sum(results.energy.delta.mu.P_neg_GEQ0, 2);
%     e1 = sum(s.results.energy.delta.mu.P_pos_GEQ0, 2);
%     e2 = sum(s.results.energy.delta.mu.P_neg_GEQ0, 2);
%     t = 'results.energy.delta.mu.P_pos/neg_GEQ0';
% %     t_is(g1-e1, e2-g2, 5, t);
% %     t_is(g1, e1, 5, t);
% %     t_is(g2, e2, 5, t);
%     t_is(g1+g2, e1+e2, 5, t);

    t = 'results.energy.mu.alphaP';
    g3 = results.energy.mu.alphaP;
    e3 = s.results.energy.mu.alphaP;
%     t_is(g1-e1, g3-e3, 5, t);
    t_is(g3, e3, 5, t);

%     t = 'results.energy.sumlamPikplus';
%     t_is(results.energy.sumlamPikplus, s.results.energy.sumlamPikplus, 5, t);
% 
%     t = 'results.energy.sumlamPikminus';
%     t_is(results.energy.sumlamPikminus, s.results.energy.sumlamPikminus, 5, t);
% 
%     t = 'results.energy.(mu.Pc - sumlamPikplus + sumlamPikminus)';
%     g1 =   results.energy.mu.Pc;
%     e1 = s.results.energy.mu.Pc;
%     g1 = g1 -   results.energy.sumlamPikplus;
%     e1 = e1 - s.results.energy.sumlamPikplus;
%     g1 = g1 +   results.energy.sumlamPikminus;
%     e1 = e1 + s.results.energy.sumlamPikminus;
% %     t_is(results.energy.mu.Pc, s.results.energy.mu.Pc, 5, t);
%     t_is(g1, e1, 5, t);
% 
%     t = 'results.reserve.mu.Rp_pos';
%     t_is(sum(results.reserve.mu.Rp_pos, 2), sum(s.results.reserve.mu.Rp_pos, 2), 5, t);
% 
%     t = 'results.reserve.mu.Rp_neg';
%     t_is(sum(results.reserve.mu.Rp_neg, 2), sum(s.results.reserve.mu.Rp_neg, 2), 5, t);
% 
%     t = 'results.reserve.mu.Rpmax_pos';
%     t_is(results.reserve.mu.Rpmax_pos, s.results.reserve.mu.Rpmax_pos, 5, t);
% 
%     t = 'results.reserve.mu.Rpmax_neg';
%     t_is(results.reserve.mu.Rpmax_neg, s.results.reserve.mu.Rpmax_neg, 5, t);

    t = 'results.reserve.qty.Rp_pos';
    t_is(results.reserve.qty.Rp_pos, s.results.reserve.qty.Rp_pos, 5, t);

    t = 'results.reserve.qty.Rp_neg';
    t_is(results.reserve.qty.Rp_neg, s.results.reserve.qty.Rp_neg, 5, t);

%     t = 'results.reserve.prc.Rp_pos';
%     t_is(results.reserve.prc.Rp_pos, s.results.reserve.prc.Rp_pos, 5, t);
% 
%     t = 'results.reserve.prc.Rp_neg';
%     t_is(results.reserve.prc.Rp_neg, s.results.reserve.prc.Rp_neg, 5, t);

    t = 'results.opf_results.x';
    t_is(results.opf_results.x, s.results.opf_results.x, 4, t);

    if k > 4
% results.total_output.qty
% results.total_output.mu
        t = 'results.total_output.qty';
        t_is(results.total_output.qty, s.results.total_output.qty, 2, t);

        t = 'results.total_output.mu';
        t_is(results.total_output.mu, s.results.total_output.mu, 2, t);
    end

    %% base case quantities
    t = 'results.base.bus(:, VA)';
    t_is(results.base.bus(:, VA), s.results.base.bus(:, VA), 6, t);

    t = 'results.base.gen(:, PG)';
    t_is(results.base.gen(:, PG), s.results.base.gen(:, PG), 6, t);

%     t = 'results.base.gen(:, MU_PMIN)';
%     t_is(results.base.gen(:, MU_PMIN), s.results.base.gen(:, MU_PMIN), 1, t);

    t = 'results.base.dcline(:, c.PF)';
    t_is(results.base.dcline(:, c.PF), s.results.base.dcline(:, c.PF), 6, t);

    t = 'results.base.dcline(:, c.PT)';
    t_is(results.base.dcline(:, c.PT), s.results.base.dcline(:, c.PT), 6, t);

%     t = 'results.base.dcline(:, c.MU_PMIN)';
%     t_is(results.base.dcline(:, c.MU_PMIN), s.results.base.dcline(:, c.MU_PMIN), 2, t);
% 
%     t = 'results.base.dcline(:, c.MU_PMAX)';
%     t_is(results.base.dcline(:, c.MU_PMAX), s.results.base.dcline(:, c.MU_PMAX), 6, t);

    t = 'results.base.if.P';
    t_is(results.base.if.P, s.results.base.if.P, 6, t);

%     t = 'results.base.if.mu.l';
%     t_is(results.base.if.mu.l, s.results.base.if.mu.l, 6, t);
% 
%     t = 'results.base.if.mu.u';
%     t_is(results.base.if.mu.u, s.results.base.if.mu.u, 6, t);

% [results.base.if.P results.base.if.mu.l results.base.if.mu.u]

    %% contingency quantities
    nc = length(results.cont);
    for k = 1:nc
        p = 6;
        t = sprintf('results.cont(%d).bus(:, VA)', k);
        t_is(results.cont(k).bus(:, VA), s.results.cont(k).bus(:, VA), p, t);

        t = sprintf('results.cont(%d).gen(:, PG)', k);
        t_is(results.cont(k).gen(:, PG), s.results.cont(k).gen(:, PG), p, t);

%         t = sprintf('results.cont(%d).gen(:, MU_PMIN)', k);
%         t_is(results.cont(k).gen(:, MU_PMIN), s.results.cont(k).gen(:, MU_PMIN), 1, t);

        t = sprintf('results.cont(%d).dcline(:, c.PF)', k);
        t_is(results.cont(k).dcline(:, c.PF), s.results.cont(k).dcline(:, c.PF), 6, t);

        t = sprintf('results.cont(%d).dcline(:, c.PT)', k);
        t_is(results.cont(k).dcline(:, c.PT), s.results.cont(k).dcline(:, c.PT), 6, t);

%         t = sprintf('results.cont(%d).dcline(:, c.MU_PMIN)', k);
%         t_is(results.cont(k).dcline(:, c.MU_PMIN), s.results.cont(k).dcline(:, c.MU_PMIN), 2, t);
% 
%         t = sprintf('results.cont(%d).dcline(:, c.MU_PMAX)', k);
%         t_is(results.cont(k).dcline(:, c.MU_PMAX), s.results.cont(k).dcline(:, c.MU_PMAX), 6, t);

        t = sprintf('results.cont(%d).if.P', k);
        t_is(results.cont(k).if.P, s.results.cont(k).if.P, 6, t);

%         t = sprintf('results.cont(%d).if.mu.l', k);
%         t_is(results.cont(k).if.mu.l, s.results.cont(k).if.mu.l, 6, t);
% 
%         t = sprintf('results.cont(%d).if.mu.u', k);
%         t_is(results.cont(k).if.mu.u, s.results.cont(k).if.mu.u, 6, t);
% [results.cont(k).if.P results.cont(k).if.mu.l results.cont(k).if.mu.u]
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
